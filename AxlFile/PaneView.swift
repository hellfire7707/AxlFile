import SwiftUI
import AppKit

// MARK: - PaneView

struct PaneView: View {
    @Environment(AppState.self) private var appState
    var pane: PaneState
    var paneID: PaneID
    var focusedPane: FocusState<PaneID?>.Binding

    private var isActive: Bool { appState.activePaneID == paneID }

    var body: some View {
        VStack(spacing: 0) {
            // 활성 패널 표시선
            Rectangle()
                .frame(height: 2)
                .foregroundStyle(isActive ? Color.accentColor : Color.clear)

            TabBarView(pane: pane, paneID: paneID)
                .environment(appState)

            if let tab = pane.activeTab {
                PathBarView(tab: tab)
                    .environment(appState)

                FolderInfoBar(tab: tab)
                    .environment(appState)

                FileListView(
                    tab: tab,
                    paneID: paneID,
                    isActive: isActive,
                    focusedPane: focusedPane
                )
                .environment(appState)

                PaneFileInfoBar(tab: tab)
            } else {
                Spacer()
            }
        }
        .background(NX.bg)
    }
}

// MARK: - Tab Bar

struct TabBarView: View {
    @Environment(AppState.self) private var appState
    var pane: PaneState
    var paneID: PaneID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 1) {
                ForEach(Array(pane.tabs.enumerated()), id: \.element.id) { idx, tab in
                    TabCell(
                        tab: tab,
                        isActive: pane.activeIndex == idx,
                        onSelect: {
                            pane.activeIndex = idx
                            appState.activePaneID = paneID
                            Task { await appState.loadTab(tab, showHidden: appState.showHidden) }
                        },
                        onClose: { pane.closeTab(at: idx) }
                    )
                }
                Button {
                    appState.activePaneID = paneID
                    appState.addNewTab(in: pane)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .frame(width: 22, height: 24)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 26)
        .background(NX.tabBarBg)
        .overlay(alignment: .bottom) {
            Rectangle().frame(height: 1).foregroundStyle(NX.separator)
        }
    }
}

struct TabCell: View {
    var tab: TabInfo
    var isActive: Bool
    var onSelect: () -> Void
    var onClose: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 4) {
            Text(tab.title)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.white : NX.tabText)
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .leading)
            Group {
                if hovered {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(NX.tabText)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Spacer().frame(width: 12)
                }
            }
            .frame(width: 14)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(isActive ? NX.tabActive : NX.tabInactive)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(NX.separator, lineWidth: 0.5)
            }
        }
        .onHover { hovered = $0 }
        .onTapGesture { onSelect() }
    }
}

// MARK: - Path Bar

struct PathBarView: View {
    @Environment(AppState.self) private var appState
    var tab: TabInfo
    @State private var isEditing = false
    @State private var editText  = ""
    @FocusState private var editFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Button {
                let parent = tab.url.deletingLastPathComponent()
                if parent != tab.url {
                    let name = tab.url.lastPathComponent
                    appState.navigate(tab: tab, to: parent, selectingName: name)
                }
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(tab.url.pathComponents.count <= 1)

            if isEditing {
                TextField("경로", text: $editText)
                    .font(.system(size: 11, design: .monospaced))
                    .textFieldStyle(.plain)
                    .focused($editFocused)
                    .onSubmit { commitEdit(); isEditing = false }
                    .onKeyPress(.escape) { isEditing = false; return .handled }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { i, url in
                                Button {
                                    appState.navigate(tab: tab, to: url)
                                } label: {
                                    Text(url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent)
                                        .font(.system(size: 11))
                                        .foregroundStyle(i == breadcrumbs.count - 1 ? Color.white : NX.pathText)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(
                                            i == breadcrumbs.count - 1
                                                ? NX.cursor.opacity(0.7)
                                                : Color.clear
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                                .id(i)
                                if i < breadcrumbs.count - 1 {
                                    Text("›").font(.system(size: 11)).foregroundStyle(NX.separator)
                                }
                            }
                        }
                    }
                    .onChange(of: tab.url) { _, _ in
                        proxy.scrollTo(breadcrumbs.count - 1, anchor: .trailing)
                    }
                    .onAppear {
                        proxy.scrollTo(breadcrumbs.count - 1, anchor: .trailing)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editText  = tab.url.path
                    isEditing = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { editFocused = true }
                }

                Button {
                    Task { await appState.loadTab(tab, showHidden: appState.showHidden) }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10)).foregroundStyle(NX.infoText)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(NX.pathBg)
        .overlay(alignment: .bottom) { Divider() }
        .onChange(of: tab.url) { _, _ in
            if isEditing {
                editText  = tab.url.path
                isEditing = false
            }
        }
    }

    private func commitEdit() {
        let p = editText.trimmingCharacters(in: .whitespaces)
        if tab.isSFTP, let client = tab.sftpClient {
            let url = appState.sftpURL(client: client, path: p)
            appState.navigate(tab: tab, to: url)
        } else {
            let url = URL(fileURLWithPath: p)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                appState.navigate(tab: tab, to: url)
            }
        }
    }

    private var breadcrumbs: [URL] {
        var result: [URL] = []
        var built = URL(fileURLWithPath: "/")
        result.append(built)
        for component in tab.url.pathComponents.dropFirst() {
            built = built.appendingPathComponent(component)
            result.append(built)
        }
        return result
    }
}

// MARK: - Folder Info Bar

struct FolderInfoBar: View {
    @Environment(AppState.self) private var appState
    var tab: TabInfo
    @State private var diskFree: Int64 = 0

    var body: some View {
        let info = tab.folderInfo(showHidden: appState.showHidden)
        HStack(spacing: 6) {
            Text("\(info.dirs)개 폴더")
                .font(.system(size: 10))
                .foregroundStyle(NX.infoText)
            Text("·").foregroundStyle(NX.separator).font(.system(size: 10))
            Text("\(info.files)개 파일")
                .font(.system(size: 10))
                .foregroundStyle(NX.infoText)
            if info.totalSize > 0 {
                Text("(\(fmtSize(info.totalSize)))")
                    .font(.system(size: 10))
                    .foregroundStyle(NX.attrText)
            }
            Spacer()
            if diskFree > 0 {
                Text("여유 \(fmtSize(diskFree))")
                    .font(.system(size: 10))
                    .foregroundStyle(NX.infoText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(NX.headerBg)
        .overlay(alignment: .bottom) {
            Rectangle().frame(height: 1).foregroundStyle(NX.separator)
        }
        .task(id: tab.url) {
            let path = tab.url.path
            let attrs = (try? FileManager.default.attributesOfFileSystem(forPath: path)) ?? [:]
            diskFree = (attrs[.systemFreeSize] as? Int64) ?? 0
        }
    }

    private func fmtSize(_ b: Int64) -> String {
        if b < 1024          { return "\(b) B" }
        if b < 1_048_576     { return String(format: "%.1f KB", Double(b)/1024) }
        if b < 1_073_741_824 { return String(format: "%.1f MB", Double(b)/1_048_576) }
        return String(format: "%.2f GB", Double(b)/1_073_741_824)
    }
}

// MARK: - Pane File Info Bar  ── 67,584 | 2026-04-13 23:52 | ___ | filename

struct PaneFileInfoBar: View {
    var tab: TabInfo

    var body: some View {
        HStack(spacing: 0) {
            if !tab.selectedIDs.isEmpty {
                // 다중 선택: N개 선택 | 합계 크기
                let sel     = tab.files.filter { tab.selectedIDs.contains($0.id) }
                let selSize = sel.reduce(Int64(0)) { $0 + $1.size }
                let szStr = { let f = NumberFormatter(); f.numberStyle = .decimal; return f.string(from: NSNumber(value: selSize)) ?? "\(selSize)" }()
                Text("\(sel.count)개 선택")
                    .foregroundStyle(NX.selected)
                    .font(.system(size: 11))
                pipe()
                Text("\(szStr) B")
                    .foregroundStyle(NX.sizeText)
                    .font(.system(size: 11))
            } else if let item = tab.cursorFile {
                // 단일 커서: size | date | attr | name
                if !item.isDirectory {
                    Text(item.sizeBytesFormatted)
                        .foregroundStyle(NX.infoText)
                        .font(.system(size: 11))
                    pipe()
                    Text(item.infoDateString)
                        .foregroundStyle(NX.infoText)
                        .font(.system(size: 11))
                    pipe()
                    Text(item.attrString)
                        .foregroundStyle(NX.folderText)
                        .font(.system(size: 11, design: .monospaced))
                    pipe()
                }
                Text(item.name)
                    .foregroundStyle(NX.fileText)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(" ").font(.system(size: 11))
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(height: 22)
        .background(NX.infoBg)
        .overlay(alignment: .top) { Rectangle().frame(height: 1).foregroundStyle(NX.separator) }
    }

    @ViewBuilder private func pipe() -> some View {
        Text("  |  ").font(.system(size: 11)).foregroundStyle(NX.separator)
    }
}

struct VolumeInfo: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let totalBytes: Int64
    let freeBytes: Int64

    var freeString: String {
        let b = freeBytes
        if b <= 0 { return "" }
        if b < 1_073_741_824 { return String(format: "%.1f MB 남음", Double(b)/1_048_576) }
        return String(format: "%.1f GB 남음", Double(b)/1_073_741_824)
    }

    var usedRatio: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(totalBytes - freeBytes) / Double(totalBytes)
    }
}

struct DriveRowView: View {
    var vol: VolumeInfo
    var isCursor: Bool = false
    var onTap: () -> Void
    @State private var icon: NSImage?
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let icon { Image(nsImage: icon).resizable().scaledToFit() }
                else { Image(systemName: "internaldrive").font(.system(size: 12)) }
            }
            .frame(width: 16, height: 16)

            Text(vol.name)
                .font(.system(size: 11))
                .foregroundStyle(isCursor ? NX.cursorText : Color(hex: "#4A9EFF"))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if vol.totalBytes > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.1))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(vol.usedRatio > 0.9 ? Color.red.opacity(0.7) : Color(hex: "#3A6EA5"))
                            .frame(width: geo.size.width * vol.usedRatio)
                    }
                }
                .frame(width: 60, height: 6)

                Text(vol.freeString)
                    .font(.system(size: 10))
                    .foregroundStyle(NX.infoText)
                    .frame(width: 80, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(isCursor ? NX.cursor : hovered ? NX.cursor.opacity(0.4) : Color.clear)
        .onHover { hovered = $0 }
        .onTapGesture { onTap() }
        .onAppear {
            icon = NSWorkspace.shared.icon(forFile: vol.url.path)
        }
    }
}

