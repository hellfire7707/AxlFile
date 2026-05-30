import Foundation

// actor 대신 nonisolated 함수로 — MainActor default isolation 환경에서 actor 기반 로딩이 데드락을 유발함
nonisolated func loadDirectory(url: URL, showHidden: Bool) throws -> [FileItem] {
    let keys: Set<URLResourceKey> = [
        .nameKey, .fileSizeKey, .contentModificationDateKey,
        .isDirectoryKey, .isHiddenKey, .isSymbolicLinkKey
    ]
    let options: FileManager.DirectoryEnumerationOptions =
        showHidden ? [] : .skipsHiddenFiles
    let contents = try FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: Array(keys), options: options)
    return contents.map { u -> FileItem in
        let res = (try? u.resourceValues(forKeys: keys)) ?? URLResourceValues()
        return FileItem(
            url: u,
            name: res.name ?? u.lastPathComponent,
            size: Int64(res.fileSize ?? 0),
            modificationDate: res.contentModificationDate ?? Date(),
            isDirectory: res.isDirectory ?? false,
            isHidden: res.isHidden ?? false,
            isSymlink: res.isSymbolicLink ?? false
        )
    }
}
