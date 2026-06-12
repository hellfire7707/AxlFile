import Foundation

// MARK: - Overwrite policy

enum OverwriteAction: Sendable {
    case skip, skipAll, rename, renameAll, overwrite, overwriteAll
}

// MARK: - FileOperationManager

actor FileOperationManager {
    private(set) var cancelled = false

    func cancel() { cancelled = true }

    typealias ConflictResolver = @Sendable (URL, URL) async -> OverwriteAction

    // MARK: - 복사 / 이동

    func perform(op: ClipboardOp,
                 items: [URL],
                 destination: URL,
                 conflictResolver: ConflictResolver = { _, _ in .rename },
                 onTotal: @escaping (Int) -> Void = { _ in },
                 onFile: @escaping (String, String, String, Int64) -> Void = { _, _, _, _ in },
                 progress: @escaping (Double) -> Void) async throws {
        cancelled = false
        let fm = FileManager.default

        if op == .move {
            let total = max(1, items.count)
            await MainActor.run { onTotal(total) }
            for (i, src) in items.enumerated() {
                if cancelled { throw CancellationError() }
                var dst = destination.appendingPathComponent(src.lastPathComponent)
                let size = fileSize(src)

                if fm.fileExists(atPath: dst.path) {
                    let action = await conflictResolver(src, dst)
                    switch action {
                    case .skip, .skipAll:
                        await MainActor.run { progress(Double(i + 1) / Double(total)) }
                        continue
                    case .rename, .renameAll:
                        dst = uniqueDst(fm: fm, dst: destination, name: src.lastPathComponent)
                    case .overwrite, .overwriteAll:
                        break
                    }
                }

                await MainActor.run { onFile(src.lastPathComponent, src.path, dst.path, size) }
                try await bg { try fm.moveItem(at: src, to: dst) }
                await MainActor.run { progress(Double(i + 1) / Double(total)) }
            }
            return
        }

        // 복사: 폴더를 파일 단위로 열거해 개별 진행 표시
        var tasks: [(src: URL, dst: URL, size: Int64, isDir: Bool)] = []
        for src in items {
            let dst = destination.appendingPathComponent(src.lastPathComponent)
            collect(fm: fm, src: src, dst: dst, into: &tasks)
        }

        let total = max(1, tasks.count)
        await MainActor.run { onTotal(total) }

        for (i, task) in tasks.enumerated() {
            if cancelled { throw CancellationError() }
            var dst = task.dst
            let src = task.src
            let size = task.size
            let isDir = task.isDir

            // 파일 충돌 감지 (디렉토리는 병합)
            if !isDir && fm.fileExists(atPath: dst.path) {
                let action = await conflictResolver(src, dst)
                switch action {
                case .skip, .skipAll:
                    await MainActor.run { progress(Double(i + 1) / Double(total)) }
                    continue
                case .rename, .renameAll:
                    dst = uniqueDst(fm: fm, dst: dst.deletingLastPathComponent(), name: dst.lastPathComponent)
                case .overwrite, .overwriteAll:
                    break
                }
            }

            await MainActor.run { onFile(src.lastPathComponent, src.path, dst.path, size) }
            try await bg {
                let parent = dst.deletingLastPathComponent()
                try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
                if isDir {
                    if !fm.fileExists(atPath: dst.path) {
                        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
                    }
                } else {
                    if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
                    try fm.copyItem(at: src, to: dst)
                }
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

    private func collect(fm: FileManager, src: URL, dst: URL,
                         into tasks: inout [(src: URL, dst: URL, size: Int64, isDir: Bool)]) {
        var isDir: ObjCBool = false
        fm.fileExists(atPath: src.path, isDirectory: &isDir)

        if isDir.boolValue {
            tasks.append((src: src, dst: dst, size: 0, isDir: true))
            let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
            guard let enumerator = fm.enumerator(
                at: src,
                includingPropertiesForKeys: keys,
                options: [.skipsSubdirectoryDescendants]
            ) else { return }
            for case let child as URL in enumerator {
                let rel = child.lastPathComponent
                collect(fm: fm, src: child, dst: dst.appendingPathComponent(rel), into: &tasks)
            }
        } else {
            tasks.append((src: src, dst: dst, size: fileSize(src), isDir: false))
        }
    }

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
