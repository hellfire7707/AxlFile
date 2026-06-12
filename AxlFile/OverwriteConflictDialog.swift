import SwiftUI

// MARK: - OverwriteConflict  (AppState에 저장, continuation 보유)

final class OverwriteConflict: @unchecked Sendable {
    let srcURL: URL
    let dstURL: URL
    private let cont: CheckedContinuation<OverwriteAction, Never>

    init(srcURL: URL, dstURL: URL, continuation: CheckedContinuation<OverwriteAction, Never>) {
        self.srcURL = srcURL
        self.dstURL = dstURL
        self.cont = continuation
    }

    func resolve(_ action: OverwriteAction) {
        cont.resume(returning: action)
    }
}

// MARK: - OverwriteConflictDialog

struct OverwriteConflictDialog: View {
    let conflict: OverwriteConflict
    var onResolve: (OverwriteAction) -> Void

    private var srcAttrs: FileAttrs { FileAttrs(url: conflict.srcURL) }
    private var dstAttrs: FileAttrs { FileAttrs(url: conflict.dstURL) }

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 16))
                Text("파일 충돌")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NX.fileText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(NX.headerBg)
            .overlay(alignment: .bottom) { Rectangle().frame(height: 1).foregroundStyle(NX.separator) }

            // 파일명 요약
            Text("\"\(conflict.dstURL.lastPathComponent)\" 이(가) 대상 폴더에 이미 존재합니다")
                .font(.system(size: 11))
                .foregroundStyle(NX.infoText)
                .lineLimit(2)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 비교 테이블
            comparisonTable
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Divider()
                .padding(.top, 12)
                .overlay(NX.separator)

            // 버튼 행
            buttonRow
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 500)
        .background(NX.bg)
        .overlay { Rectangle().strokeBorder(NX.separator, lineWidth: 1) }
    }

    // MARK: - Comparison Table

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            // 헤더 행
            HStack(spacing: 0) {
                colLabel("항목").frame(width: 70, alignment: .leading)
                colLabel("원본").frame(maxWidth: .infinity, alignment: .leading)
                colLabel("대상").frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(NX.headerBg)

            Divider().overlay(NX.separator)

            // 파일 이름 행
            tableRow(
                label: "이름",
                srcVal: conflict.srcURL.lastPathComponent,
                dstVal: conflict.dstURL.lastPathComponent,
                highlight: false
            )

            Divider().overlay(NX.separator)

            // 크기 행
            let srcSize = srcAttrs.size
            let dstSize = dstAttrs.size
            let sizeHighlight = (srcSize ?? 0) < (dstSize ?? 0)
            let sizeNote: String? = {
                guard let s = srcSize, let d = dstSize else { return nil }
                if d > s { return "더 큼" }
                if d < s { return "더 작음" }
                return nil
            }()
            tableRow(
                label: "크기",
                srcVal: fmtSize(srcSize),
                dstVal: fmtSize(dstSize),
                highlight: sizeHighlight,
                dstNote: sizeNote
            )

            Divider().overlay(NX.separator)

            // 수정일 행
            let srcDate = srcAttrs.modified
            let dstDate = dstAttrs.modified
            tableRow(
                label: "수정일",
                srcVal: fmtDate(srcDate),
                dstVal: fmtDate(dstDate),
                highlight: dstDate != nil && srcDate != nil && dstDate! > srcDate!,
                dstNote: dstDate != nil && srcDate != nil
                    ? (dstDate! > srcDate! ? "더 최신" : (dstDate! < srcDate! ? "더 오래됨" : nil))
                    : nil
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(NX.separator, lineWidth: 1) }
    }

    @ViewBuilder
    private func tableRow(label: String, srcVal: String, dstVal: String,
                          highlight: Bool, dstNote: String? = nil) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(NX.headerText)
                .frame(width: 70, alignment: .leading)

            Text(srcVal)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(NX.fileText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Text(dstVal)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(highlight ? Color.orange : NX.fileText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let note = dstNote {
                    Text("(\(note))")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(NX.rowEven)
    }

    @ViewBuilder
    private func colLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NX.headerText)
    }

    // MARK: - Button Row

    private var buttonRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                actionBtn("건너뛰기",    style: .normal) { onResolve(.skip) }
                actionBtn("모두 건너뛰기", style: .normal) { onResolve(.skipAll) }
                Spacer()
                actionBtn("이름 변경",    style: .normal) { onResolve(.rename) }
                actionBtn("모두 이름 변경", style: .normal) { onResolve(.renameAll) }
            }
            HStack(spacing: 8) {
                Spacer()
                actionBtn("덮어쓰기",    style: .destructive) { onResolve(.overwrite) }
                actionBtn("모두 덮어쓰기", style: .destructive) { onResolve(.overwriteAll) }
            }
        }
    }

    @ViewBuilder
    private func actionBtn(_ label: String, style: BtnStyle,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(style == .destructive ? .white : NX.fileText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(style == .destructive ? Color.red.opacity(0.8) : NX.headerBg)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(style == .destructive ? Color.clear : NX.separator, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private enum BtnStyle { case normal, destructive }

    // MARK: - Helpers

    private func fmtSize(_ size: Int64?) -> String {
        guard let size else { return "–" }
        if size == 0 { return "0 B" }
        if size < 1024 { return "\(size) B" }
        if size < 1_048_576 { return String(format: "%.1f KB", Double(size) / 1024) }
        if size < 1_073_741_824 { return String(format: "%.1f MB", Double(size) / 1_048_576) }
        return String(format: "%.2f GB", Double(size) / 1_073_741_824)
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f
    }()

    private func fmtDate(_ date: Date?) -> String {
        guard let date else { return "–" }
        return Self.dateFmt.string(from: date)
    }
}

// MARK: - FileAttrs  (파일 속성 읽기)

private struct FileAttrs {
    let size: Int64?
    let modified: Date?

    init(url: URL) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let vals = try? url.resourceValues(forKeys: keys)
        size     = vals?.fileSize.map { Int64($0) }
        modified = vals?.contentModificationDate
    }
}
