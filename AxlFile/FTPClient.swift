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
        let pwd = runRemote("pwd")
        if pwd.exitCode == 0 {
            currentPath = pwd.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    nonisolated func disconnect() {
        _ = sshExec(["-S", controlPath, "-O", "exit", "\(username)@\(host)"], timeout: 5)
        cleanup()
        isConnected = false
    }

    // MARK: - Directory List

    nonisolated func list(path: String) throws -> [SFTPEntry] {
        guard isConnected else { throw SFTPError.notConnected }
        let r = runRemote("LC_ALL=C ls -la \(q(path)) 2>&1")
        return parseLs(r.stdout, base: path)
    }

    // MARK: - File Operations (원격)

    nonisolated func mkdir(path: String) throws {
        guard isConnected else { throw SFTPError.notConnected }
        let r = runRemote("mkdir -p \(q(path))")
        guard r.exitCode == 0 else { throw SFTPError.commandFailed(r.stderr) }
    }

    nonisolated func deleteItem(path: String, isDirectory: Bool) throws {
        guard isConnected else { throw SFTPError.notConnected }
        let cmd = isDirectory ? "rm -rf \(q(path))" : "rm -f \(q(path))"
        let r = runRemote(cmd)
        guard r.exitCode == 0 else { throw SFTPError.commandFailed(r.stderr) }
    }

    nonisolated func rename(from: String, to: String) throws {
        guard isConnected else { throw SFTPError.notConnected }
        let r = runRemote("mv \(q(from)) \(q(to))")
        guard r.exitCode == 0 else { throw SFTPError.commandFailed(r.stderr) }
    }

    nonisolated func copyRemote(from: String, to: String) throws {
        guard isConnected else { throw SFTPError.notConnected }
        let r = runRemote("cp -r \(q(from)) \(q(to))")
        guard r.exitCode == 0 else { throw SFTPError.commandFailed(r.stderr) }
    }

    nonisolated func createFile(path: String) throws {
        guard isConnected else { throw SFTPError.notConnected }
        let r = runRemote("touch \(q(path))")
        guard r.exitCode == 0 else { throw SFTPError.commandFailed(r.stderr) }
    }

    // MARK: - Upload / Download (scp)

    nonisolated func upload(localURL: URL, remotePath: String) throws {
        guard isConnected else { throw SFTPError.notConnected }
        let r = execProcess("/usr/bin/scp", args: [
            "-r", "-P", "\(port)",
            "-o", "ControlPath=\(controlPath)",
            "-o", "StrictHostKeyChecking=accept-new",
            localURL.path,
            "\(username)@\(host):\(remotePath)"
        ], env: [:], timeout: 300)
        guard r.exitCode == 0 else { throw SFTPError.transferFailed(r.stderr) }
    }

    nonisolated func download(remotePath: String, localURL: URL) throws {
        guard isConnected else { throw SFTPError.notConnected }
        let r = execProcess("/usr/bin/scp", args: [
            "-r", "-P", "\(port)",
            "-o", "ControlPath=\(controlPath)",
            "-o", "StrictHostKeyChecking=accept-new",
            "\(username)@\(host):\(remotePath)",
            localURL.path
        ], env: [:], timeout: 300)
        guard r.exitCode == 0 else { throw SFTPError.transferFailed(r.stderr) }
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
