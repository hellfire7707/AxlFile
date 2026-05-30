import SwiftUI

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
                    .environment(appState)
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
                    if let url = pane.activeTab?.url {
                        pane.addTab(url: url)
                        appState.activePaneID = paneID
                        Task {
                            if let t = pane.activeTab {
                                await appState.loadTab(t, showHidden: appState.showHidden)
                            }
                        }
                    }
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
                if parent != tab.url { appState.navigate(tab: tab, to: parent) }
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
                            if i < breadcrumbs.count - 1 {
                                Text("›").font(.system(size: 11)).foregroundStyle(NX.separator)
                            }
                        }
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
    }

    private func commitEdit() {
        let p = editText.trimmingCharacters(in: .whitespaces)
        let url = URL(fileURLWithPath: p)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            appState.navigate(tab: tab, to: url)
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

// MARK: - Pane File Info Bar

struct PaneFileInfoBar: View {
    @Environment(AppState.self) private var appState
    var tab: TabInfo

    var body: some View {
        HStack(spacing: 6) {
            if !tab.selectedIDs.isEmpty {
                let sel     = tab.files.filter { tab.selectedIDs.contains($0.id) }
                let selSize = sel.reduce(Int64(0)) { $0 + $1.size }
                Text("\(sel.count)개 선택").foregroundStyle(NX.selected)
                sep()
                Text(ByteCountFormatter.string(fromByteCount: selSize, countStyle: .file))
                    .foregroundStyle(NX.sizeText)
            } else if let item = tab.cursorFile {
                if !item.isDirectory {
                    Text(item.sizeString).foregroundStyle(NX.sizeText)
                    sep()
                    Text(item.dateString).foregroundStyle(NX.dateText)
                    sep()
                    Text(item.attrString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(NX.attrText)
                    sep()
                }
                Text(item.name)
                    .foregroundStyle(NX.fileText)
                    .lineLimit(1).truncationMode(.middle)
            } else {
                Text(" ")
            }
            Spacer()
        }
        .font(.system(size: 10))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(NX.infoBg)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private func sep() -> some View {
        Text("|").foregroundStyle(.quaternary)
    }
}
