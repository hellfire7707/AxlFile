import Foundation

// MARK: - SFTP Errors

enum SFTPError: LocalizedError {
    case connectionFailed(String)
    case authFailed
    case commandFailed(String)
    case transferFailed(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let m): return "연결 실패: \(m)"
        case .authFailed:              return "인증 실패 — 비밀번호 또는 SSH 키를 확인하세요"
        case .commandFailed(let m):    return "명령 오류: \(m)"
        case .transferFailed(let m):   return "전송 오류: \(m)"
        case .notConnected:            return "연결되어 있지 않습니다"
        }
    }
}

// MARK: - SFTP Entry

struct SFTPEntry: Identifiable {
    let id           = UUID()
    let name:         String
    let isDirectory:  Bool
    let isSymlink:    Bool
    let size:         Int64
    let permissions:  String
    let modifiedDate: Date?
    var path:         String = ""
}

// MARK: - Process Result

struct ProcessResult {
    let exitCode: Int
    let stdout:   String
    let stderr:   String
}

// MARK: - SFTP Client (ssh ControlMaster 기반)

final class SFTPClient: @unchecked Sendable {

    let host:     String
    let port:     Int
    let username: String

    private let password:    String
    private let useKeyAuth:  Bool
    private let controlPath: String
    nonisolated(unsafe) private var askpassPath: String?

    nonisolated(unsafe) private(set) var isConnected = false
    nonisolated(unsafe) private(set) var currentPath = "/"

    // 재연결 직렬화 + 최근 검증 시각 캐시
    private let reconnectLock = NSLock()
    nonisolated(unsafe) private var lastVerified = Date.distantPast

    // 진행 중인 전송(scp) 프로세스 — 취소 시 종료용
    private let transferLock = NSLock()
    nonisolated(unsafe) private var activeTransfer: Process?

    init(host: String, port: Int = 22, username: String,
         password: String = "", useKeyAuth: Bool = false) {
        self.host       = host
        self.port       = port
        self.username   = username
        self.password   = password
        self.useKeyAuth = useKeyAuth
        let safe = host
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        controlPath = "/tmp/axlfile_ctrl_\(safe)_\(port)_\(username)"
    }

    // MARK: - Connect / Disconnect

    nonisolated func connect() throws {
        try? FileManager.default.removeItem(atPath: controlPath)

        var env: [String: String] = [:]
        if !password.isEmpty && !useKeyAuth {
            let s = makeAskpassScript()
            askpassPath = s
            env["SSH_ASKPASS"]         = s
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["DISPLAY"]             = ":0"
        }

        let args: [String] = [
            "-M", "-S", controlPath, "-f", "-N",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "PasswordAuthentication=\(useKeyAuth ? "no" : "yes")",
            "-o", "BatchMode=\(useKeyAuth ? "yes" : "no")",
            "-o", "ConnectTimeout=15",
            // 연결 유지(keepalive). 서버가 응답 없으면 마스터가 종료돼
            // 소켓이 정리되므로 controlMasterAlive()가 끊김을 감지할 수 있다.
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-p", "\(port)",
            "\(username)@\(host)"
        ]
        let r = execProcess("/usr/bin/ssh", args: args, env: env, timeout: 20)
        if r.exitCode != 0 {
            cleanup()
            let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if msg.lowercased().contains("permission denied") ||
               msg.lowercased().contains("authentication failed") {
                throw SFTPError.authFailed
            }
            throw SFTPError.connectionFailed(msg.isEmpty ? "exit \(r.exitCode)" : msg)
        }

        // ControlMaster 활성 확인
        let chk = sshExec(["-S", controlPath, "-O", "check", "\(username)@\(host)"], timeout: 5)
        guard chk.exitCode == 0 else {
            cleanup()
            throw SFTPError.connectionFailed("ControlMaster 확인 실패")
        }

        isConnected = true
        lastVerified = Date()
        let pwd = runRemote("pwd")
        if pwd.exitCode == 0 {
            currentPath = pwd.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    nonisolated func disconnect() {
        _ = sshExec(["-S", controlPath, "-O", "exit", "\(username)@\(host)"], timeout: 5)
        cleanup()
        isConnected = false
        lastVerified = .distantPast
    }

    // MARK: - 연결 검증 / 자동 재연결

    /// ControlMaster 소켓이 살아있는지 확인.
    nonisolated private func controlMasterAlive() -> Bool {
        let chk = sshExec(["-S", controlPath, "-O", "check", "\(username)@\(host)"], timeout: 8)
        return chk.exitCode == 0
    }

    /// 작업 전 연결 상태를 검증하고, 끊겼으면 재연결한다.
    /// 짧은 시간(3초) 내 재검증은 캐시해 재귀 작업의 오버헤드를 줄인다.
    nonisolated func ensureConnected() throws {
        reconnectLock.lock()
        defer { reconnectLock.unlock() }

        // 최근에 검증됐으면 통과
        if isConnected && Date().timeIntervalSince(lastVerified) < 3 { return }

        // 소켓 생존 확인
        if isConnected && controlMasterAlive() {
            lastVerified = Date()
            return
        }

        // 끊김 → 재연결 (connect 내부에서 controlPath 정리 후 새로 연결)
        isConnected = false
        try connect()
    }

    // MARK: - Directory List

    nonisolated func list(path: String) throws -> [SFTPEntry] {
        try ensureConnected()
        // stderr 를 stdout 으로 합치면 오류 메시지가 목록 항목으로 파싱되므로 분리해서 받는다
        let r = runRemote("LC_ALL=C ls -la -- \(q(path))")
        guard r.exitCode == 0 else {
            let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SFTPError.commandFailed(msg.isEmpty ? "\(path) 목록 조회 실패" : msg)
        }
        return parseLs(r.stdout, base: path)
    }

    // MARK: - File Operations (원격)

    nonisolated func mkdir(path: String) throws {
        try ensureConnected()
        let p = q(path)
        // mkdir -p 는 이미 존재해도 0을 반환하므로 사전 검사로 구분한다
        try runChecked("if [ -e \(p) ]; then echo '이미 존재합니다' >&2; exit 1; fi; mkdir -p -- \(p)",
                       fallback: "폴더 생성 실패")
    }

    nonisolated func deleteItem(path: String, isDirectory: Bool) throws {
        try ensureConnected()
        let p = q(path)
        // rm -f 는 대상이 없거나 일부 실패에도 0을 반환해 성공으로 오인된다.
        // 삭제 후 실제로 사라졌는지 검증해서 조용한 실패를 막는다. (-L: 깨진 심볼릭 링크)
        let rm  = isDirectory ? "rm -rf -- \(p)" : "rm -f -- \(p)"
        let cmd = "\(rm); if [ -e \(p) ] || [ -L \(p) ]; then echo '삭제되지 않음 — 권한을 확인하세요' >&2; exit 1; fi"
        let r = runRemote(cmd)
        guard r.exitCode == 0 else {
            let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SFTPError.commandFailed(
                msg.isEmpty ? "\((path as NSString).lastPathComponent) 삭제 실패" : msg)
        }
    }

    nonisolated func rename(from: String, to: String) throws {
        try ensureConnected()
        let f = q(from); let t = q(to)
        // mv 는 대상이 있으면 조용히 덮어쓰므로 사전에 막는다
        try runChecked("if [ -e \(t) ]; then echo '대상 이름이 이미 존재합니다' >&2; exit 1; fi; mv -- \(f) \(t)",
                       fallback: "이름 변경 실패")
    }

    nonisolated func copyRemote(from: String, to: String) throws {
        try ensureConnected()
        try runChecked("cp -r -- \(q(from)) \(q(to))", fallback: "복사 실패")
    }

    nonisolated func createFile(path: String) throws {
        try ensureConnected()
        let p = q(path)
        // touch 는 이미 있는 파일이면 타임스탬프만 갱신하고 0을 반환한다
        try runChecked("if [ -e \(p) ]; then echo '이미 존재합니다' >&2; exit 1; fi; touch -- \(p)",
                       fallback: "파일 생성 실패")
    }

    /// 원격 명령 실행 후 종료 코드를 검사하고, 실패하면 stderr 를 그대로 오류로 올린다
    nonisolated private func runChecked(_ command: String, fallback: String) throws {
        let r = runRemote(command)
        guard r.exitCode == 0 else {
            let msg = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SFTPError.commandFailed(msg.isEmpty ? fallback : msg)
        }
    }

    // MARK: - Upload / Download (scp)

    nonisolated func upload(localURL: URL, remotePath: String) throws {
        try ensureConnected()
        let r = runTransfer(args: [
            "-r", "-P", "\(port)",
            "-o", "ControlPath=\(controlPath)",
            "-o", "StrictHostKeyChecking=accept-new",
            localURL.path,
            "\(username)@\(host):\(remotePath)"
        ])
        guard r.exitCode == 0 else { throw SFTPError.transferFailed(r.stderr) }
    }

    nonisolated func download(remotePath: String, localURL: URL) throws {
        try ensureConnected()
        let r = runTransfer(args: [
            "-r", "-P", "\(port)",
            "-o", "ControlPath=\(controlPath)",
            "-o", "StrictHostKeyChecking=accept-new",
            "\(username)@\(host):\(remotePath)",
            localURL.path
        ])
        guard r.exitCode == 0 else { throw SFTPError.transferFailed(r.stderr) }
    }

    /// 원격 파일의 바이트 크기 (진행률 폴링용). 실패 시 0.
    nonisolated func remoteFileSize(path: String) -> Int64 {
        let r = runRemote("stat -c %s \(q(path)) 2>/dev/null || stat -f %z \(q(path)) 2>/dev/null")
        return Int64(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// 진행 중인 전송(scp)을 즉시 종료한다 (취소).
    nonisolated func cancelActiveTransfer() {
        transferLock.lock()
        let p = activeTransfer
        transferLock.unlock()
        p?.terminate()
    }

    /// scp 전송 실행 — 취소가 가능하도록 프로세스를 추적한다.
    nonisolated private func runTransfer(args: [String]) -> ProcessResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment
        let outPipe = Pipe(); let errPipe = Pipe()
        p.standardOutput = outPipe; p.standardError = errPipe
        guard (try? p.run()) != nil else {
            return ProcessResult(exitCode: -1, stdout: "", stderr: "프로세스 실행 실패")
        }
        transferLock.lock(); activeTransfer = p; transferLock.unlock()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        let err = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        transferLock.lock(); activeTransfer = nil; transferLock.unlock()
        return ProcessResult(
            exitCode: Int(p.terminationStatus),
            stdout: String(data: out, encoding: .utf8) ?? "",
            stderr: String(data: err, encoding: .utf8) ?? ""
        )
    }

    nonisolated func mkdir(remotePath: String) {
        let escaped = remotePath.replacingOccurrences(of: "'", with: "'\\''")
        runRemote("mkdir -p '\(escaped)'")
    }

    // MARK: - Internal Helpers

    @discardableResult
    nonisolated func runRemote(_ command: String) -> ProcessResult {
        sshExec(["-S", controlPath, "\(username)@\(host)", command], timeout: 30)
    }

    @discardableResult
    nonisolated private func sshExec(_ args: [String], timeout: TimeInterval) -> ProcessResult {
        execProcess("/usr/bin/ssh", args: args, env: [:], timeout: timeout)
    }

    nonisolated private func execProcess(_ exe: String, args: [String],
                                         env: [String: String], timeout: TimeInterval) -> ProcessResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        var environment = ProcessInfo.processInfo.environment
        for (k, v) in env { environment[k] = v }
        p.environment = environment
        let outPipe = Pipe(); let errPipe = Pipe()
        p.standardOutput = outPipe; p.standardError = errPipe
        guard (try? p.run()) != nil else {
            return ProcessResult(exitCode: -1, stdout: "", stderr: "프로세스 실행 실패")
        }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate(); return ProcessResult(exitCode: -1, stdout: "", stderr: "타임아웃") }
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessResult(exitCode: Int(p.terminationStatus), stdout: out, stderr: err)
    }

    nonisolated private func makeAskpassScript() -> String {
        let path = "/tmp/axlfile_askpass_\(UUID().uuidString.prefix(8)).sh"
        let escaped = password.replacingOccurrences(of: "'", with: "'\\''")
        let script = "#!/bin/sh\necho '\(escaped)'\n"
        try? script.write(toFile: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        return path
    }

    nonisolated private func cleanup() {
        if let p = askpassPath {
            try? FileManager.default.removeItem(atPath: p)
            askpassPath = nil
        }
        try? FileManager.default.removeItem(atPath: controlPath)
    }

    nonisolated private func q(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - ls -la 파서

    nonisolated private func parseLs(_ output: String, base: String) -> [SFTPEntry] {
        let lines = output.components(separatedBy: "\n")
        var entries: [SFTPEntry] = []
        let curYear = Calendar.current.component(.year, from: Date())

        for line in lines {
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard l.count > 10, !l.hasPrefix("total"), !l.hasPrefix("ls:") else { continue }
            let parts = l.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 9 else { continue }

            let perms = parts[0]
            let isDir  = perms.hasPrefix("d")
            let isLink = perms.hasPrefix("l")
            let size   = Int64(parts[4]) ?? 0
            let month = parts[5]; let day = parts[6]; let timeOrYear = parts[7]

            var rawName = parts[8...].joined(separator: " ")
            if isLink, let r = rawName.range(of: " -> ") { rawName = String(rawName[..<r.lowerBound]) }
            guard rawName != "." && rawName != ".." && !rawName.isEmpty else { continue }

            var date: Date?
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            if timeOrYear.contains(":") {
                df.dateFormat = "MMM d HH:mm yyyy"
                date = df.date(from: "\(month) \(day) \(timeOrYear) \(curYear)")
            } else {
                df.dateFormat = "MMM d yyyy"
                date = df.date(from: "\(month) \(day) \(timeOrYear)")
            }

            let normalBase = (base != "/" && base.hasSuffix("/")) ? String(base.dropLast()) : base
            let entryPath  = normalBase == "/" ? "/\(rawName)" : "\(normalBase)/\(rawName)"

            entries.append(SFTPEntry(
                name: rawName, isDirectory: isDir, isSymlink: isLink,
                size: size, permissions: perms, modifiedDate: date, path: entryPath
            ))
        }

        return entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
