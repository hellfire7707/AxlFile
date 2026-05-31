import Foundation
import SwiftUI

enum PaneID: Equatable { case left, right }

enum SortField: String, CaseIterable {
    case name = "Name"
    case size = "Size"
    case date = "Date"
    case ext  = "Ext"
}

// MARK: - FileItem

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let modificationDate: Date
    let isDirectory: Bool
    let isHidden: Bool
    let isSymlink: Bool

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var ext: String { url.pathExtension.lowercased() }

    var sizeString: String {
        guard !isDirectory else { return "<DIR>" }
        if size == 0 { return "0 B" }
        if size < 1024 { return "\(size) B" }
        if size < 1_048_576 { return String(format: "%.1f KB", Double(size) / 1024) }
        if size < 1_073_741_824 { return String(format: "%.1f MB", Double(size) / 1_048_576) }
        return String(format: "%.2f GB", Double(size) / 1_073_741_824)
    }

    var attrString: String {
        var s = ""
        s += isHidden  ? "H" : "_"
        s += isSymlink ? "L" : "_"
        s += FileManager.default.isExecutableFile(atPath: url.path) && !isDirectory ? "X" : "_"
        return s
    }

    // 파일 정보 바용: 쉼표 구분 바이트 수
    var sizeBytesFormatted: String {
        guard !isDirectory else { return "<DIR>" }
        return FileItem.numFmt.string(from: NSNumber(value: size)) ?? "\(size)"
    }

    private static let numFmt: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yy-MM-dd HH:mm"; return f
    }()
    // 파일 정보 바용: 4자리 연도
    private static let infoDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()
    var dateString: String     { FileItem.dateFmt.string(from: modificationDate) }
    var infoDateString: String { FileItem.infoDateFmt.string(from: modificationDate) }

    var sfSymbol: String {
        if isDirectory { return "folder.fill" }
        if isSymlink   { return "arrow.triangle.branch" }
        switch ext {
        case "txt","md","swift","py","js","ts","json","xml","html","css","sh","c","h","cpp","java","go","rs","kt","rb","php":
            return "doc.text.fill"
        case "jpg","jpeg","png","gif","webp","heic","tiff","bmp","svg","ico","raw":
            return "photo.fill"
        case "mp4","mov","avi","mkv","wmv","m4v","flv","webm","ts":
            return "video.fill"
        case "mp3","m4a","aac","flac","wav","ogg","opus","wma","aiff":
            return "music.note"
        case "pdf":
            return "doc.richtext.fill"
        case "zip","gz","tar","7z","rar","bz2","xz","zst","br":
            return "archivebox.fill"
        case "app":
            return "app.fill"
        case "dmg","iso","img":
            return "opticaldiscdrive.fill"
        case "xcodeproj","xcworkspace":
            return "hammer.fill"
        case "pkg","deb","rpm":
            return "shippingbox.fill"
        default:
            return "doc.fill"
        }
    }

    var symbolColor: Color {
        if isDirectory { return .blue }
        switch ext {
        case "jpg","jpeg","png","gif","webp","heic","tiff","bmp","svg","raw":
            return .orange
        case "mp4","mov","avi","mkv","wmv","m4v","flv","webm":
            return .purple
        case "mp3","m4a","aac","flac","wav","ogg","opus":
            return .pink
        case "pdf":
            return .red
        case "zip","gz","tar","7z","rar","bz2","xz":
            return .yellow
        case "swift","py","js","ts","c","cpp","go","rs","java","kt","rb","php":
            return .green
        case "app":
            return .indigo
        default:
            return Color(nsColor: .secondaryLabelColor)
        }
    }

    var isViewable: Bool {
        isTextFile || isImageFile || isVideoFile
    }

    var isTextFile: Bool {
        ["txt","md","swift","py","js","ts","json","xml","html","css","sh","c","h","cpp",
         "java","go","rs","kt","rb","php","yaml","yml","toml","ini","conf","log",
         "gitignore","gitattributes","dockerfile","makefile","cmake"].contains(ext)
        || ext.isEmpty
    }

    var isImageFile: Bool {
        ["jpg","jpeg","png","gif","webp","heic","tiff","bmp","svg","ico"].contains(ext)
    }

    var isVideoFile: Bool {
        ["mp4","mov","avi","mkv","m4v","flv","webm"].contains(ext)
    }
}

// MARK: - TabInfo

@Observable
class TabInfo: Identifiable {
    let id = UUID()
    var url: URL
    var files: [FileItem] = []
    var selectedIDs: Set<UUID> = []
    var cursorID: UUID?
    var sortField: SortField = .name
    var sortAscending = true
    var isLoading = false

    // SFTP 탭: nil이면 로컬 파일시스템
    var sftpClient: SFTPClient?

    var isSFTP: Bool { sftpClient != nil }

    init(url: URL) { self.url = url }

    var title: String {
        if let client = sftpClient { return client.host }
        let n = url.lastPathComponent
        return n.isEmpty ? "/" : n
    }

    func displayFiles(showHidden: Bool) -> [FileItem] {
        var items = showHidden ? files : files.filter { !$0.isHidden }
        items.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            let asc: Bool
            switch sortField {
            case .name: asc = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .size: asc = a.size < b.size
            case .date: asc = a.modificationDate < b.modificationDate
            case .ext:  asc = a.ext.localizedCaseInsensitiveCompare(b.ext) == .orderedAscending
            }
            return sortAscending ? asc : !asc
        }
        return items
    }

    var cursorFile: FileItem? {
        guard let id = cursorID else { return nil }
        return files.first { $0.id == id }
    }

    var effectiveSelections: [FileItem] {
        let sel = files.filter { selectedIDs.contains($0.id) }
        if !sel.isEmpty { return sel }
        if let c = cursorFile { return [c] }
        return []
    }

    func moveCursor(to item: FileItem?) {
        cursorID = item?.id
    }

    func folderInfo(showHidden: Bool) -> (dirs: Int, files: Int, totalSize: Int64) {
        let items = showHidden ? self.files : self.files.filter { !$0.isHidden }
        let dirCount  = items.filter { $0.isDirectory }.count
        let fileItems = items.filter { !$0.isDirectory }
        let totalSize = fileItems.reduce(Int64(0)) { $0 + $1.size }
        return (dirs: dirCount, files: fileItems.count, totalSize: totalSize)
    }
}

// MARK: - PaneState

@Observable
class PaneState {
    var tabs: [TabInfo] = []
    var activeIndex: Int = 0

    init(url: URL) {
        tabs = [TabInfo(url: url)]
    }

    var activeTab: TabInfo? {
        tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil
    }

    func addTab(url: URL, sftpClient: SFTPClient? = nil) {
        let t = TabInfo(url: url)
        t.sftpClient = sftpClient
        tabs.append(t)
        activeIndex = tabs.count - 1
    }

    func closeTab(at index: Int) {
        guard tabs.count > 1 else { return }
        tabs.remove(at: index)
        activeIndex = max(0, min(activeIndex, tabs.count - 1))
    }
}
