import Foundation

let archiveExtensions: Set<String> = ["zip","tar","gz","bz2","xz","7z","rar","tgz","tbz2"]

func isArchiveFile(_ url: URL) -> Bool {
    archiveExtensions.contains(url.pathExtension.lowercased())
}

func extractArchive(at src: URL, to dst: URL) async throws {
    try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
    let ext = src.pathExtension.lowercased()
    let process = Process()
    let errPipe = Pipe()
    process.standardOutput = Pipe()
    process.standardError = errPipe
    switch ext {
    case "zip":
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", src.path, "-d", dst.path]
    default:
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", src.path, "-C", dst.path]
    }
    try process.run()
    let code: Int32 = await withCheckedContinuation { cont in
        process.terminationHandler = { p in cont.resume(returning: p.terminationStatus) }
    }
    if code != 0 {
        let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "압축 해제 실패"
        throw NSError(domain: "Archive", code: Int(code), userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "압축 해제 실패" : msg])
    }
}

func createZip(from urls: [URL], to destination: URL) async throws {
    guard !urls.isEmpty else { return }
    var tmpDir: URL? = nil
    let sourceArg: String
    let keepParent: Bool
    if urls.count == 1 {
        sourceArg = urls[0].path
        keepParent = true
    } else {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        for url in urls {
            try FileManager.default.copyItem(at: url, to: tmp.appendingPathComponent(url.lastPathComponent))
        }
        tmpDir = tmp
        sourceArg = tmp.path
        keepParent = false
    }
    let process = Process()
    let errPipe = Pipe()
    process.standardOutput = Pipe()
    process.standardError = errPipe
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    var args = ["-c", "-k", "--sequesterRsrc"]
    if keepParent { args.append("--keepParent") }
    args += [sourceArg, destination.path]
    process.arguments = args
    try process.run()
    let capturedTmpDir = tmpDir
    let code: Int32 = await withCheckedContinuation { cont in
        process.terminationHandler = { p in
            if let t = capturedTmpDir { try? FileManager.default.removeItem(at: t) }
            cont.resume(returning: p.terminationStatus)
        }
    }
    if code != 0 {
        let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "압축 실패"
        throw NSError(domain: "Archive", code: Int(code), userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "압축 실패" : msg])
    }
}
