import Foundation

actor FileOperationManager {
    private(set) var cancelled = false

    func cancel() { cancelled = true }

    // MARK: - 복사 / 이동

    func perform(op: ClipboardOp,
                 items: [URL],
                 destination: URL,
                 onTotal: @escaping (Int) -> Void = { _ in },
                 onFile: @escaping (String, String, String, Int64) -> Void = { _, _, _, _ in },
                 progress: @escaping (Double) -> Void) async throws {
        cancelled = false
        let fm = FileManager.default

        if op == .move {
            // 이동은 atomic이므로 항목 단위로 처리
            let total = max(1, items.count)
            await MainActor.run { onTotal(total) }
            for (i, src) in items.enumerated() {
                if cancelled { throw CancellationError() }
                let dst = uniqueDst(fm: fm, dst: destination, name: src.lastPathComponent)
                let size = fileSize(src)
                await MainActor.run { onFile(src.lastPathComponent, src.path, dst.path, size) }
                try await bg { try fm.moveItem(at: src, to: dst) }
                await MainActor.run { progress(Double(i + 1) / Double(total)) }
            }
            return
        }

        // 복사: 폴더를 파일 단위로 열거해 개별 진행 표시
        var tasks: [(src: URL, dst: URL, size: Int64)] = []
        for src in items {
            let dst = uniqueDst(fm: fm, dst: destination, name: src.lastPathComponent)
            collect(fm: fm, src: src, dst: dst, into: &tasks)
        }

        let total = max(1, tasks.count)
        await MainActor.run { onTotal(total) }
        for (i, task) in tasks.enumerated() {
            if cancelled { throw CancellationError() }
            let src = task.src, dst = task.dst, size = task.size
            await MainActor.run { onFile(src.lastPathComponent, src.path, dst.path, size) }
            try await bg {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: src.path, isDirectory: &isDir)
                let parent = dst.deletingLastPathComponent()
                try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
                if isDir.boolValue {
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

    // src 아래 모든 항목(폴더 포함)을 재귀적으로 수집
    private func collect(fm: FileManager, src: URL, dst: URL,
                         into tasks: inout [(src: URL, dst: URL, size: Int64)]) {
        var isDir: ObjCBool = false
        fm.fileExists(atPath: src.path, isDirectory: &isDir)

        if isDir.boolValue {
            // 폴더 자체를 먼저 추가 (생성 작업)
            tasks.append((src: src, dst: dst, size: 0))
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
            tasks.append((src: src, dst: dst, size: fileSize(src)))
        }
    }

    // 블로킹 작업을 GCD 백그라운드에서 실행
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
