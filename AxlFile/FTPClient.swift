import Foundation

// MARK: - FTP Errors

enum FTPError: LocalizedError {
    case connectionFailed
    case authFailed(String)
    case commandFailed(String)
    case dataConnectionFailed
    case transferFailed(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .connectionFailed:     return "서버에 연결할 수 없습니다"
        case .authFailed(let m):    return "인증 실패: \(m)"
        case .commandFailed(let m): return "명령 오류: \(m)"
        case .dataConnectionFailed: return "데이터 연결 실패"
        case .transferFailed(let m):return "전송 오류: \(m)"
        case .notConnected:         return "연결되어 있지 않습니다"
        }
    }
}

// MARK: - FTP File Entry

struct FTPEntry: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: String
    var path: String = ""
}

// MARK: - FTP Client

// nonisolated으로 선언해 MainActor 격리에서 제외 — FTP는 백그라운드 스레드에서 동작함
nonisolated(unsafe) class FTPClient: @unchecked Sendable {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private(set) var isConnected = false
    private(set) var currentPath = "/"
    var host = ""
    var port = 21

    // MARK: Connect

    func connect(host: String, port: Int = 21, username: String, password: String) throws {
        self.host = host
        self.port = port

        var inp: InputStream?
        var out: OutputStream?
        Stream.getStreamsToHost(withName: host, port: port, inputStream: &inp, outputStream: &out)
        guard let i = inp, let o = out else { throw FTPError.connectionFailed }
        inputStream = i
        outputStream = o
        i.open(); o.open()

        // Give streams time to connect
        Thread.sleep(forTimeInterval: 0.5)
        guard i.streamStatus == .open || i.streamStatus == .reading else {
            throw FTPError.connectionFailed
        }

        let welcome = try readLine()
        guard welcome.hasPrefix("220") else { throw FTPError.commandFailed(welcome) }

        // Login
        try sendCommand("USER \(username)")
        let userResp = try readLine()
        if userResp.hasPrefix("331") {
            try sendCommand("PASS \(password)")
            let passResp = try readLine()
            guard passResp.hasPrefix("230") else { throw FTPError.authFailed(passResp) }
        } else if !userResp.hasPrefix("230") {
            throw FTPError.authFailed(userResp)
        }

        // Binary mode
        try sendCommand("TYPE I")
        _ = try readLine()

        isConnected = true
        currentPath = try pwd()
    }

    func disconnect() {
        try? sendCommand("QUIT")
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
        isConnected = false
    }

    // MARK: Navigation

    func pwd() throws -> String {
        try sendCommand("PWD")
        let resp = try readLine()
        // 257 "/path" is the current directory
        if resp.hasPrefix("257") {
            let parts = resp.components(separatedBy: "\"")
            return parts.count >= 2 ? parts[1] : "/"
        }
        return "/"
    }

    func cd(path: String) throws {
        try sendCommand("CWD \(path)")
        let resp = try readLine()
        guard resp.hasPrefix("250") else { throw FTPError.commandFailed(resp) }
        currentPath = try pwd()
    }

    // MARK: List

    func list(path: String? = nil) throws -> [FTPEntry] {
        let (dataIn, dataOut) = try openPassive()
        defer { dataIn.close(); dataOut.close() }

        let cmd = path.map { "LIST \($0)" } ?? "LIST"
        try sendCommand(cmd)
        let resp = try readLine()
        guard resp.hasPrefix("125") || resp.hasPrefix("150") else {
            throw FTPError.commandFailed(resp)
        }

        // Read listing from data connection
        var listing = ""
        var buf = [UInt8](repeating: 0, count: 4096)
        Thread.sleep(forTimeInterval: 0.2)
        while dataIn.hasBytesAvailable {
            let n = dataIn.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            listing += String(bytes: buf.prefix(n), encoding: .utf8) ?? ""
        }

        _ = try? readLine() // 226 Transfer complete

        return parseListing(listing)
    }

    // MARK: Download

    func download(remotePath: String, localURL: URL,
                  progress: @escaping (Double) -> Void) throws {
        let size = try getSize(path: remotePath)
        let (dataIn, dataOut) = try openPassive()
        defer { dataIn.close(); dataOut.close() }

        try sendCommand("RETR \(remotePath)")
        let resp = try readLine()
        guard resp.hasPrefix("125") || resp.hasPrefix("150") else {
            throw FTPError.commandFailed(resp)
        }

        let fm = FileManager.default
        fm.createFile(atPath: localURL.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: localURL.path) else {
            throw FTPError.transferFailed("로컬 파일 생성 실패")
        }
        defer { handle.closeFile() }

        var received: Int64 = 0
        var buf = [UInt8](repeating: 0, count: 65536)
        while dataIn.hasBytesAvailable || dataIn.streamStatus == .open {
            let n = dataIn.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            handle.write(Data(buf.prefix(n)))
            received += Int64(n)
            if size > 0 { progress(Double(received) / Double(size)) }
        }

        _ = try? readLine() // 226
    }

    // MARK: Upload

    func upload(localURL: URL, remotePath: String,
                progress: @escaping (Double) -> Void) throws {
        guard let data = try? Data(contentsOf: localURL) else {
            throw FTPError.transferFailed("로컬 파일 읽기 실패")
        }
        let total = data.count

        let (dataIn, dataOut) = try openPassive()
        defer { dataIn.close(); dataOut.close() }

        try sendCommand("STOR \(remotePath)")
        let resp = try readLine()
        guard resp.hasPrefix("125") || resp.hasPrefix("150") else {
            throw FTPError.commandFailed(resp)
        }

        let chunkSize = 65536
        var sent = 0
        while sent < total {
            let end = min(sent + chunkSize, total)
            let chunk = Array(data[sent..<end])
            var written = 0
            while written < chunk.count {
                let slice = Array(chunk[written...])
                let n = dataOut.write(slice, maxLength: slice.count)
                if n <= 0 { throw FTPError.transferFailed("쓰기 실패") }
                written += n
            }
            sent += chunk.count
            progress(Double(sent) / Double(total))
        }
        dataOut.close()
        _ = try? readLine() // 226
    }

    // MARK: File Operations

    func mkdir(path: String) throws {
        try sendCommand("MKD \(path)")
        let resp = try readLine()
        guard resp.hasPrefix("257") else { throw FTPError.commandFailed(resp) }
    }

    func delete(path: String, isDirectory: Bool) throws {
        let cmd = isDirectory ? "RMD \(path)" : "DELE \(path)"
        try sendCommand(cmd)
        let resp = try readLine()
        guard resp.hasPrefix("250") else { throw FTPError.commandFailed(resp) }
    }

    func rename(from: String, to: String) throws {
        try sendCommand("RNFR \(from)")
        let r1 = try readLine()
        guard r1.hasPrefix("350") else { throw FTPError.commandFailed(r1) }
        try sendCommand("RNTO \(to)")
        let r2 = try readLine()
        guard r2.hasPrefix("250") else { throw FTPError.commandFailed(r2) }
    }

    func getSize(path: String) throws -> Int64 {
        try sendCommand("SIZE \(path)")
        let resp = try readLine()
        if resp.hasPrefix("213") {
            let parts = resp.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            return Int64(parts.last ?? "0") ?? 0
        }
        return 0
    }

    // MARK: - Internal Helpers

    private func sendCommand(_ cmd: String) throws {
        guard let out = outputStream else { throw FTPError.notConnected }
        let line = cmd + "\r\n"
        var bytes = Array(line.utf8)
        let n = out.write(&bytes, maxLength: bytes.count)
        if n <= 0 { throw FTPError.connectionFailed }
    }

    // Reads a full response (handles multi-line responses like "220-...\r\n220 \r\n")
    private func readLine() throws -> String {
        guard let inp = inputStream else { throw FTPError.notConnected }
        var result = ""
        var attempts = 0
        while attempts < 200 {
            if inp.hasBytesAvailable {
                var line = ""
                var byte = [UInt8](repeating: 0, count: 1)
                while inp.hasBytesAvailable {
                    let n = inp.read(&byte, maxLength: 1)
                    if n <= 0 { break }
                    if byte[0] == UInt8(ascii: "\n") {
                        result += line
                        // Multi-line: "123-..." continues until "123 "
                        if result.count >= 4 {
                            let sep  = result.count > 3 ? String(result[result.index(result.startIndex, offsetBy: 3)]) : "-"
                            if sep == " " { return result }
                            // Keep reading
                            result += "\n"
                        } else {
                            return result
                        }
                        line = ""
                        continue
                    }
                    if byte[0] != UInt8(ascii: "\r") {
                        line.append(Character(UnicodeScalar(byte[0])))
                    }
                }
                result += line
            }
            Thread.sleep(forTimeInterval: 0.05)
            attempts += 1
        }
        return result
    }

    // PASV mode: returns (input, output) streams for data connection
    private func openPassive() throws -> (InputStream, OutputStream) {
        try sendCommand("PASV")
        let resp = try readLine()
        guard resp.hasPrefix("227") else { throw FTPError.commandFailed(resp) }

        // Parse (h1,h2,h3,h4,p1,p2)
        guard let start = resp.firstIndex(of: "("),
              let end   = resp.firstIndex(of: ")") else {
            throw FTPError.dataConnectionFailed
        }
        let inner = String(resp[resp.index(after: start)..<end])
        let nums  = inner.components(separatedBy: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard nums.count == 6 else { throw FTPError.dataConnectionFailed }

        let dataHost = "\(nums[0]).\(nums[1]).\(nums[2]).\(nums[3])"
        let dataPort = nums[4] * 256 + nums[5]

        var dataIn: InputStream?
        var dataOut: OutputStream?
        Stream.getStreamsToHost(withName: dataHost, port: dataPort,
                                inputStream: &dataIn, outputStream: &dataOut)
        guard let di = dataIn, let dout = dataOut else { throw FTPError.dataConnectionFailed }
        di.open(); dout.open()
        Thread.sleep(forTimeInterval: 0.1)
        return (di, dout)
    }

    // MARK: - Directory Listing Parser

    // Parses Unix-style "ls -l" output from FTP LIST command
    private func parseListing(_ listing: String) -> [FTPEntry] {
        listing.components(separatedBy: "\n").compactMap { line -> FTPEntry? in
            let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard l.count > 10 else { return nil }

            // Unix format: "drwxr-xr-x  2 user group    4096 Jan  1 12:00 dirname"
            let isDir = l.hasPrefix("d")
            let parts = l.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 9 else { return nil }

            let name = parts[8...].joined(separator: " ")
            guard name != "." && name != ".." else { return nil }
            let size = Int64(parts[4]) ?? 0
            let month = parts[5]
            let day   = parts[6]
            let time  = parts[7]
            let modified = "\(month) \(day) \(time)"

            return FTPEntry(name: name, isDirectory: isDir, size: size, modified: modified)
        }
    }
}
