import SwiftUI

struct PermissionsView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var perms: Int = 0
    @State private var owner = ""
    @State private var group = ""
    @State private var errorMsg: String?
    @State private var successMsg: String?

    // bit masks: [owner-r, owner-w, owner-x, group-r, group-w, group-x, other-r, other-w, other-x]
    private let masks = [0o400, 0o200, 0o100, 0o040, 0o020, 0o010, 0o004, 0o002, 0o001]
    private let labels = ["읽기", "쓰기", "실행"]
    private let categories = ["소유자", "그룹", "기타"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundStyle(NX.folderText)
                Text("파일 권한")
                    .font(.headline)
                    .foregroundStyle(NX.fileText)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NX.infoText)
                }
                .buttonStyle(.borderless)
            }
            .padding(14)
            .background(NX.headerBg)
            .overlay(alignment: .bottom) { Rectangle().frame(height: 1).foregroundStyle(NX.separator) }

            VStack(alignment: .leading, spacing: 16) {
                // File name
                Text(url.lastPathComponent)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(NX.pathText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Owner / Group
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("소유자").font(.system(size: 10)).foregroundStyle(NX.infoText)
                        Text(owner).font(.system(size: 11, design: .monospaced)).foregroundStyle(NX.fileText)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("그룹").font(.system(size: 10)).foregroundStyle(NX.infoText)
                        Text(group).font(.system(size: 11, design: .monospaced)).foregroundStyle(NX.fileText)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("8진수").font(.system(size: 10)).foregroundStyle(NX.infoText)
                        Text(String(format: "%04o", perms))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(NX.folderText)
                    }
                }

                // Permission grid
                VStack(spacing: 2) {
                    // Header
                    HStack(spacing: 0) {
                        Text("").frame(width: 56)
                        ForEach(labels, id: \.self) { lbl in
                            Text(lbl)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(NX.headerText)
                                .frame(width: 60, alignment: .center)
                        }
                    }
                    Divider()
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 0) {
                            Text(categories[row])
                                .font(.system(size: 11))
                                .foregroundStyle(NX.fileText)
                                .frame(width: 56, alignment: .leading)
                            ForEach(0..<3, id: \.self) { col in
                                let bit = masks[row * 3 + col]
                                Toggle("", isOn: Binding(
                                    get: { perms & bit != 0 },
                                    set: { v in
                                        if v { perms |= bit } else { perms &= ~bit }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .frame(width: 60, alignment: .center)
                            }
                        }
                        .frame(height: 24)
                        .background(row % 2 == 0 ? NX.rowEven : NX.rowOdd)
                    }
                }

                // Symbolic display
                Text(symbolicString)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(NX.pathText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                    .background(NX.headerBg)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // Messages
                if let err = errorMsg {
                    Text(err).font(.system(size: 11)).foregroundStyle(.red)
                }
                if let ok = successMsg {
                    Text(ok).font(.system(size: 11)).foregroundStyle(Color(hex: "#3DB06B"))
                }

                // Buttons
                HStack {
                    Spacer()
                    Button("취소") { dismiss() }
                        .keyboardShortcut(.escape)
                    Button("적용") { applyPermissions() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return)
                }
            }
            .padding(16)
        }
        .frame(width: 300)
        .background(NX.bg)
        .preferredColorScheme(.dark)
        .onAppear { loadPermissions() }
    }

    private var symbolicString: String {
        var s = ""
        for (i, mask) in masks.enumerated() {
            let on = perms & mask != 0
            if i % 3 == 0 { s += on ? "r" : "-" }
            else if i % 3 == 1 { s += on ? "w" : "-" }
            else { s += on ? "x" : "-" }
        }
        return s
    }

    private func loadPermissions() {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            perms = (attrs[.posixPermissions] as? Int) ?? 0
            if let ownerName = attrs[.ownerAccountName] as? String { owner = ownerName }
            if let groupName = attrs[.groupOwnerAccountName] as? String { group = groupName }
        } catch {
            errorMsg = "권한 읽기 실패: \(error.localizedDescription)"
        }
    }

    private func applyPermissions() {
        errorMsg = nil; successMsg = nil
        do {
            try FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: url.path)
            successMsg = "권한이 변경되었습니다"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
        } catch {
            errorMsg = "권한 변경 실패: \(error.localizedDescription)"
        }
    }
}
