import SwiftUI
import AppKit

struct PropertiesView: View {
    var url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var info: FileProperties?
    @State private var folderSize: String = "계산 중..."

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Text("속성").font(.headline)
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(NX.headerBg)

            Divider()

            if let info {
                ScrollView {
                    VStack(spacing: 0) {
                        // 아이콘 + 이름
                        VStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 64, height: 64)

                            Text(url.lastPathComponent)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(NX.fileText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 20)

                        Divider().background(NX.separator)

                        // 상세 정보
                        VStack(spacing: 0) {
                            row("종류",    info.kind)
                            row("경로",    url.deletingLastPathComponent().path)
                            if info.isDirectory {
                                rowWithIndicator("크기", folderSize)
                            } else {
                                row("크기",    info.sizeString)
                            }
                            row("생성일",  info.createdString)
                            row("수정일",  info.modifiedString)
                            row("권한",    info.permissions)
                            if info.isHidden {
                                row("숨김",    "예")
                            }
                            if info.isSymlink {
                                row("심볼릭 링크", "예")
                                if let dest = info.symlinkDest {
                                    row("링크 대상", dest)
                                }
                            }
                        }

                        Divider().background(NX.separator).padding(.top, 8)

                        // Finder 열기 버튼
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                            dismiss()
                        } label: {
                            Label("Finder에서 보기", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                        }
                        .buttonStyle(.bordered)
                        .padding(16)
                    }
                }
            } else {
                ProgressView().padding(40)
            }
        }
        .frame(width: 360)
        .background(NX.bg)
        .task {
            info = FileProperties(url: url)
            guard info?.isDirectory == true else { return }
            let bytes = await Task.detached(priority: .userInitiated) {
                FileProperties.calcDirectorySize(url: url)
            }.value
            folderSize = FileProperties.formatBytes(bytes)
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(NX.infoText)
                .frame(width: 90, alignment: .trailing)
                .padding(.trailing, 10)
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(NX.fileText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .background(Color.clear)
    }

    @ViewBuilder
    private func rowWithIndicator(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(NX.infoText)
                .frame(width: 90, alignment: .trailing)
                .padding(.trailing, 10)
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(size: 11))
                    .foregroundStyle(NX.fileText)
                    .textSelection(.enabled)
                if value == "계산 중..." {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .background(Color.clear)
    }
}

// MARK: - FileProperties

struct FileProperties {
    let kind: String
    let sizeString: String
    let createdString: String
    let modifiedString: String
    let permissions: String
    let isDirectory: Bool
    let isHidden: Bool
    let isSymlink: Bool
    let symlinkDest: String?

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    init(url: URL) {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isHiddenKey, .isSymbolicLinkKey,
            .fileSizeKey, .creationDateKey, .contentModificationDateKey,
            .localizedTypeDescriptionKey
        ]
        let res = (try? url.resourceValues(forKeys: keys)) ?? URLResourceValues()

        isDirectory = res.isDirectory ?? false
        isHidden    = res.isHidden    ?? false
        isSymlink   = res.isSymbolicLink ?? false

        // Kind
        if isDirectory {
            kind = res.localizedTypeDescription ?? "폴더"
        } else {
            kind = res.localizedTypeDescription ?? url.pathExtension.uppercased() + " 파일"
        }

        // Size
        let bytes = Int64(res.fileSize ?? 0)
        sizeString = FileProperties.formatBytes(bytes)

        // Dates
        createdString  = res.creationDate.map { Self.dateFmt.string(from: $0) } ?? "-"
        modifiedString = res.contentModificationDate.map { Self.dateFmt.string(from: $0) } ?? "-"

        // Permissions
        let fm = FileManager.default
        var perms = ""
        perms += fm.isReadableFile(atPath: url.path)   ? "읽기 " : ""
        perms += fm.isWritableFile(atPath: url.path)   ? "쓰기 " : ""
        perms += fm.isExecutableFile(atPath: url.path) ? "실행"  : ""
        permissions = perms.trimmingCharacters(in: .whitespaces).isEmpty ? "-" : perms.trimmingCharacters(in: .whitespaces)

        // Symlink destination
        if isSymlink {
            symlinkDest = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
        } else {
            symlinkDest = nil
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let n = NSNumber(value: bytes)
        let comma = numFmt.string(from: n) ?? "\(bytes)"
        if bytes < 1024 { return "\(bytes) B" }
        else if bytes < 1_048_576 { return String(format: "%.1f KB (%@ 바이트)", Double(bytes)/1024, comma) }
        else if bytes < 1_073_741_824 { return String(format: "%.1f MB (%@ 바이트)", Double(bytes)/1_048_576, comma) }
        else { return String(format: "%.2f GB (%@ 바이트)", Double(bytes)/1_073_741_824, comma) }
    }

    static func calcDirectorySize(url: URL) -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: []
        ) else { return 0 }
        for case let fileURL as URL in enumerator {
            let res = try? fileURL.resourceValues(forKeys: Set(keys))
            if res?.isRegularFile == true {
                total += Int64(res?.fileSize ?? 0)
            }
        }
        return total
    }

    private static let numFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()
}
