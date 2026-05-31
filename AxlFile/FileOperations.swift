import Foundation

actor FileOperationManager {
    private(set) var cancelled = false

    func cancel() { cancelled = true }

    // MARK: - 복사 / 이동

    func perform(op: ClipboardOp,
                 items: [URL],
                 destination: URL,
                 onFile: @escaping (String, String, String, Int64) -> Void = { _, _, _, _ in },
                 progress: @escaping (Double) -> Void) async throws {
        cancelled = false
        let fm = FileManager.default
        let total = items.count

        for (i, src) in items.enumerated() {
            if cancelled { throw CancellationError() }

            let target = uniqueDst(fm: fm, dst: destination, name: src.lastPathComponent)
            let size   = fileSize(src)
            await MainActor.run { onFile(src.lastPathComponent, src.path, target.path, size) }

            // 블로킹 파일 작업을 백그라운드 스레드에서 실행 → actor·MainActor 해방
            switch op {
            case .copy: try await bg { try fm.copyItem(at: src, to: target) }
            case .move: try await bg { try fm.moveItem(at: src, to: target) }
            }

            await MainActor.run { progress(Double(i + 1) / Double(total)) }
        }
    }

    // MARK: - 삭제 (FileItem 기반)

    func deleteItems(items: [FileItem],
                     onFile: @escaping (String, String, Int64) -> Void,
                     progress: @escaping (Double) -> Void) async throws {
        cancelled = false
        let fm = FileManager.default
        let total = items.count

        for (i, item) in items.enumerated() {
            if cancelled { throw CancellationError() }

            let url = item.url
            await MainActor.run { onFile(item.name, item.url.path, item.size) }
            try await bg { try fm.trashItem(at: url, resultingItemURL: nil) }
            await MainActor.run { progress(Double(i + 1) / Double(total)) }
        }
    }

    // MARK: - 내부 헬퍼

    // 블로킹 작업을 GCD 백그라운드에서 실행.
    // actor가 await에서 suspend되어 cancel() 등 다른 메시지를 처리할 수 있게 됨.
    private func bg(_ block: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try block(); cont.resume() }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    private func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map { Int64($0) } ?? 0
    }

    private func uniqueDst(fm: FileManager, dst: URL, name: String) -> URL {
        var target = dst.appendingPathComponent(name)
        guard fm.fileExists(atPath: target.path) else { return target }
        let base = (name as NSString).deletingPathExtension
        let ext  = (name as NSString).pathExtension
        var i = 2
        repeat {
            let newName = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            target = dst.appendingPathComponent(newName)
            i += 1
        } while fm.fileExists(atPath: target.path)
        return target
    }
}
