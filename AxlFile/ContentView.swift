import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView()
                .environment(appState)
            DualPaneView()
                .environment(appState)
            FileInfoBar()
                .environment(appState)
            FunctionKeyBar()
                .environment(appState)
        }
        .sheet(isPresented: Binding(get: { appState.showNewFolder }, set: { appState.showNewFolder = $0 })) {
            NewFolderDialog().environment(appState)
        }
        .sheet(isPresented: Binding(get: { appState.showRename }, set: { appState.showRename = $0 })) {
            RenameDialog().environment(appState)
        }
        .sheet(isPresented: Binding(get: { appState.showViewer }, set: { appState.showViewer = $0 })) {
            if let url = appState.viewerURL { ViewerView(url: url) }
        }
        .sheet(isPresented: Binding(get: { appState.showFTP }, set: { appState.showFTP = $0 })) {
            FTPConnectView().environment(appState)
        }
        .sheet(isPresented: Binding(get: { appState.showProperties }, set: { appState.showProperties = $0 })) {
            if let url = appState.propertiesTarget {
                PropertiesView(url: url)
            }
        }
        .overlay {
            if appState.isWorking { WorkingOverlay().environment(appState) }
        }
        .task {
            if let lt = appState.leftPane.activeTab {
                await appState.loadTab(lt, showHidden: appState.showHidden)
            }
            if let rt = appState.rightPane.activeTab {
                await appState.loadTab(rt, showHidden: appState.showHidden)
            }
        }
        .preferredColorScheme(.dark)  // Nexus File 스타일 다크 테마 고정
    }
}

// MARK: - Toolbar (상단 아이콘 바)

struct ToolbarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 2) {
            // 탐색
            tbBtn("chevron.left", "뒤로") {
                let tab = appState.activePane.activeTab
                if let t = tab {
                    let parent = t.url.deletingLastPathComponent()
                    if parent != t.url { appState.navigate(tab: t, to: parent) }
                }
            }

            Divider().frame(height: 20).padding(.horizontal, 4)

            // 파일 작업
            tbBtn("doc.on.doc",           "복사 (F5)") { appState.copySelectionToOpposite() }
            tbBtn("arrow.right.doc.on.clipboard", "이동 (F6)") { appState.moveSelectionToOpposite() }
            tbBtn("folder.badge.plus",    "새 폴더 (F7)") {
                appState.newFolderName = ""
                appState.showNewFolder = true
            }
            tbBtn("trash",                "삭제 (F8)") { appState.deleteSelection() }

            Divider().frame(height: 20).padding(.horizontal, 4)

            // 보기
            tbBtn("eye",                  "보기 (F3)") {
                if let item = appState.activePane.activeTab?.cursorFile, !item.isDirectory {
                    appState.viewerURL = item.url
                    appState.showViewer = true
                }
            }
            tbBtn("pencil",               "편집 (F4)") {
                if let item = appState.activePane.activeTab?.cursorFile {
                    NSWorkspace.shared.open(item.url)
                }
            }

            Divider().frame(height: 20).padding(.horizontal, 4)
            tbBtn("network",              "FTP") { appState.showFTP = true }

            Spacer()

            // 숨김 파일 토글
            Toggle(isOn: Binding(
                get: { appState.showHidden },
                set: { v in
                    appState.showHidden = v
                    Task {
                        await appState.reload(pane: appState.leftPane)
                        await appState.reload(pane: appState.rightPane)
                    }
                }
            )) {
                Label("숨김", systemImage: "eye.slash")
                    .font(.system(size: 10))
            }
            .toggleStyle(.button)
            .controlSize(.small)

            tbBtn("arrow.clockwise", "새로고침 (⌘R)") {
                Task {
                    await appState.reload(pane: appState.leftPane)
                    await appState.reload(pane: appState.rightPane)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(NX.bg)
        .overlay(alignment: .bottom) {
            Rectangle().frame(height: 1).foregroundStyle(NX.separator)
        }
    }

    @ViewBuilder
    private func tbBtn(_ icon: String, _ tip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(NX.infoText)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help(tip)
    }
}

// MARK: - File Info Bar (글로벌 상태바)

struct FileInfoBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 6) {
            // 활성 패널 커서 파일 정보 — Nexus File 하단 표시줄 스타일
            if let tab = appState.activePane.activeTab {
                if !tab.selectedIDs.isEmpty {
                    let sel = tab.files.filter { tab.selectedIDs.contains($0.id) }
                    let sz  = sel.reduce(Int64(0)) { $0 + $1.size }
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(NX.selected)
                        .font(.system(size: 10))
                    Text("\(sel.count)개 선택")
                        .foregroundStyle(NX.selected)
                    sep()
                    Text(ByteCountFormatter.string(fromByteCount: sz, countStyle: .file))
                        .foregroundStyle(NX.sizeText)
                } else if let item = tab.cursorFile {
                    Image(systemName: item.sfSymbol)
                        .foregroundStyle(item.isDirectory ? NX.folderIcon : NX.fileIcon)
                        .font(.system(size: 10))
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
                }
            }
            Spacer()
            if !appState.statusMessage.isEmpty {
                Text(appState.statusMessage)
                    .foregroundStyle(NX.infoText)
                    .transition(.opacity)
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(NX.infoBg)
        .overlay(alignment: .top)    { Rectangle().frame(height: 1).foregroundStyle(NX.separator) }
        .overlay(alignment: .bottom) { Rectangle().frame(height: 1).foregroundStyle(NX.separator) }
    }

    @ViewBuilder private func sep() -> some View {
        Text("|").foregroundStyle(NX.separator)
    }
}

// MARK: - Function Key Bar (하단 F키 버튼)

struct FunctionKeyBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 2) {
            fKey("F2", "이름변경") {
                if let item = appState.activePane.activeTab?.cursorFile {
                    appState.renameText = item.name
                    appState.showRename = true
                }
            }
            fKey("F3", "보기") {
                if let item = appState.activePane.activeTab?.cursorFile, !item.isDirectory {
                    appState.viewerURL = item.url
                    appState.showViewer = true
                }
            }
            fKey("F4", "편집") {
                if let item = appState.activePane.activeTab?.cursorFile {
                    NSWorkspace.shared.open(item.url)
                }
            }
            fKey("F5", "복사") { appState.copySelectionToOpposite() }
            fKey("F6", "이동")  { appState.moveSelectionToOpposite() }
            fKey("F7", "새폴더") {
                appState.newFolderName = ""
                appState.showNewFolder = true
            }
            fKey("F8", "삭제") { appState.deleteSelection() }
            fKey("F9", "FTP")  { appState.showFTP = true }
            fKey("F10","종료")  { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(NX.fkeyBg)
    }

    @ViewBuilder
    private func fKey(_ key: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(key)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(NX.fkeyNum)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(NX.fkeyText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .padding(.horizontal, 4)
            .background(NX.fkeyBtnBg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(NX.fkeyBtnBorder, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Working Overlay

struct WorkingOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: appState.workProgress).frame(width: 260)
                Text(appState.workMessage).font(.callout)
                Button("취소") {}.keyboardShortcut(.escape)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - New Folder Dialog

struct NewFolderDialog: View {
    @Environment(AppState.self) private var appState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("새 폴더 만들기").font(.headline)
            TextField("폴더 이름", text: Binding(
                get: { appState.newFolderName },
                set: { appState.newFolderName = $0 }
            ))
            .focused($focused)
            .textFieldStyle(.roundedBorder)
            .frame(width: 280)
            .onSubmit { appState.createFolder(); appState.showNewFolder = false }
            HStack {
                Button("취소") { appState.showNewFolder = false }.keyboardShortcut(.escape)
                Button("만들기") { appState.createFolder(); appState.showNewFolder = false }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .onAppear { focused = true }
    }
}

// MARK: - Rename Dialog

struct RenameDialog: View {
    @Environment(AppState.self) private var appState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Text("이름 변경").font(.headline)
            TextField("새 이름", text: Binding(
                get: { appState.renameText },
                set: { appState.renameText = $0 }
            ))
            .focused($focused)
            .textFieldStyle(.roundedBorder)
            .frame(width: 280)
            .onSubmit { appState.renameActive(); appState.showRename = false }
            HStack {
                Button("취소") { appState.showRename = false }.keyboardShortcut(.escape)
                Button("변경") { appState.renameActive(); appState.showRename = false }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .onAppear { focused = true }
    }
}
