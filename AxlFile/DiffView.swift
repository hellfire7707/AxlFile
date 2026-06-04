import SwiftUI

// MARK: - Diff Data

private enum DiffKind { case same, added, removed }

private struct DiffLine: Identifiable {
    let id = UUID()
    let kind: DiffKind
    let leftNum: Int?
    let rightNum: Int?
    let leftText: String
    let rightText: String
}

private func computeDiff(left: [String], right: [String]) -> [DiffLine] {
    let m = left.count, n = right.count
    guard m > 0 || n > 0 else { return [] }
    // LCS table
    var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
    for i in 1...m {
        for j in 1...n {
            dp[i][j] = left[i-1] == right[j-1]
                ? dp[i-1][j-1] + 1
                : max(dp[i-1][j], dp[i][j-1])
        }
    }
    // Backtrack
    var edits: [(DiffKind, Int?, Int?)] = []
    var li = m, ri = n
    while li > 0 || ri > 0 {
        if li > 0 && ri > 0 && left[li-1] == right[ri-1] {
            edits.append((.same, li-1, ri-1))
            li -= 1; ri -= 1
        } else if ri > 0 && (li == 0 || dp[li][ri-1] >= dp[li-1][ri]) {
            edits.append((.added, nil, ri-1))
            ri -= 1
        } else {
            edits.append((.removed, li-1, nil))
            li -= 1
        }
    }
    return edits.reversed().map { kind, l, r in
        DiffLine(kind: kind,
                 leftNum:  l.map { $0 + 1 },
                 rightNum: r.map { $0 + 1 },
                 leftText:  l.map { left[$0] }  ?? "",
                 rightText: r.map { right[$0] } ?? "")
    }
}

// MARK: - DiffView

struct DiffView: View {
    let leftURL: URL
    let rightURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var diffLines: [DiffLine] = []
    @State private var isLoading = true
    @State private var errorMsg: String?
    @State private var showOnlyChanges = false

    private let maxLines = 10_000

    var body: some View {
        VStack(spacing: 0) {
            header
            if isLoading {
                Spacer()
                ProgressView("비교 중...")
                Spacer()
            } else if let err = errorMsg {
                Spacer()
                Text(err).foregroundStyle(.secondary).padding()
                Spacer()
            } else {
                diffTable
            }
        }
        .frame(minWidth: 880, minHeight: 500)
        .background(NX.bg)
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left file label
                Text(leftURL.lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NX.fileText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                Rectangle().frame(width: 1).foregroundStyle(NX.separator)
                // Right file label
                Text(rightURL.lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NX.fileText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                // Controls
                Toggle("변경만", isOn: $showOnlyChanges)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .padding(.horizontal, 6)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NX.infoText)
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 10)
            }
            .frame(height: 30)
            .background(NX.headerBg)
            // Path sub-header
            HStack(spacing: 0) {
                Text(leftURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(NX.pathText)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                Rectangle().frame(width: 1).foregroundStyle(NX.separator)
                Text(rightURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(NX.pathText)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
            }
            .frame(height: 20)
            .background(NX.pathBg)
            Rectangle().frame(height: 1).foregroundStyle(NX.separator)
        }
    }

    // MARK: - Table

    private var visibleLines: [DiffLine] {
        showOnlyChanges ? diffLines.filter { $0.kind != .same } : diffLines
    }

    private var diffTable: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(visibleLines) { line in
                    DiffLineRow(line: line)
                }
            }
        }
        .background(Color.black)
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        errorMsg = nil
        do {
            let leftText  = try String(contentsOf: leftURL,  encoding: .utf8)
            let rightText = try String(contentsOf: rightURL, encoding: .utf8)
            let leftLines  = leftText.components(separatedBy: "\n")
            let rightLines = rightText.components(separatedBy: "\n")
            if leftLines.count > maxLines || rightLines.count > maxLines {
                errorMsg = "파일이 너무 큽니다 (\(maxLines)줄 초과)"
                isLoading = false
                return
            }
            let result = computeDiff(left: leftLines, right: rightLines)
            diffLines = result
        } catch {
            errorMsg = "파일 읽기 실패: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

// MARK: - DiffLineRow

private struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            // Left side
            HStack(spacing: 4) {
                lineNum(line.leftNum)
                Text(line.leftText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(line.kind == .removed ? Color.white : NX.fileText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(leftBg)
            // Separator
            Rectangle().frame(width: 1).foregroundStyle(NX.separator)
            // Right side
            HStack(spacing: 4) {
                lineNum(line.rightNum)
                Text(line.rightText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(line.kind == .added ? Color.white : NX.fileText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(rightBg)
        }
        .frame(height: 18)
    }

    @ViewBuilder
    private func lineNum(_ n: Int?) -> some View {
        Text(n.map { "\($0)" } ?? "")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(NX.attrText)
            .frame(width: 40, alignment: .trailing)
    }

    private var leftBg: Color {
        switch line.kind {
        case .removed: return Color(hex: "#3D1010")
        case .added:   return Color(hex: "#0A0A0A")
        case .same:    return Color.clear
        }
    }

    private var rightBg: Color {
        switch line.kind {
        case .added:   return Color(hex: "#0D2A0D")
        case .removed: return Color(hex: "#0A0A0A")
        case .same:    return Color.clear
        }
    }
}
