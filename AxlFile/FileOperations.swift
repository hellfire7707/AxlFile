import Foundation

actor FileOperationManager {
    private var cancelled = false

    func cancel() { cancelled = true }

    func perform(op: ClipboardOp, items: [URL], destination: URL,
                 progress: @escaping (Double) -> Void) async throws {
        switch op {
        case .copy: try await copyItems(items, to: destination, progress: progress)
        case .move: try await moveItems(items, to: destination, progress: progress)
        }
    }

    func copyItems(_ items: [URL], to dst: URL,
                   progress: @escaping (Double) -> Void) async throws {
        cancelled = false
        let fm = FileManager.default
        for (i, src) in items.enumerated() {
            if cancelled { throw CancellationError() }
            let target = uniqueDestination(fm: fm, dst: dst, name: src.lastPathComponent)
            try fm.copyItem(at: src, to: target)
            await MainActor.run { progress(Double(i + 1) / Double(items.count)) }
        }
    }

    func moveItems(_ items: [URL], to dst: URL,
                   progress: @escaping (Double) -> Void) async throws {
        cancelled = false
        let fm = FileManager.default
        for (i, src) in items.enumerated() {
            if cancelled { throw CancellationError() }
            let target = uniqueDestination(fm: fm, dst: dst, name: src.lastPathComponent)
            try fm.moveItem(at: src, to: target)
            await MainActor.run { progress(Double(i + 1) / Double(items.count)) }
        }
    }

    func deleteItems(_ items: [URL], progress: @escaping (Double) -> Void) async throws {
        cancelled = false
        let fm = FileManager.default
        for (i, url) in items.enumerated() {
            if cancelled { throw CancellationError() }
            try fm.trashItem(at: url, resultingItemURL: nil)
            await MainActor.run { progress(Double(i + 1) / Double(items.count)) }
        }
    }

    private func uniqueDestination(fm: FileManager, dst: URL, name: String) -> URL {
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
