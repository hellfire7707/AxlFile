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
        .sheet(isPresented: Binding(get: { appState.showNewFile }, set: { appState.showNewFile = $0 })) {
            NewFileDialog().environment(appState)
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

// MARK: - File Info Bar  ── 67,584 | 2013-03-10 16:43 | A_S | bootstat.dat

struct FileInfoBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            if let tab = appState.activePane.activeTab {
                if !tab.selectedIDs.isEmpty {
                    // 다중 선택 상태
                    let sel = tab.files.filter { tab.selectedIDs.contains($0.id) }
                    let sz  = sel.reduce(Int64(0)) { $0 + $1.size }
                    let szStr = NumberFormatter().apply { $0.numberStyle = .decimal }
                              .string(from: NSNumber(value: sz)) ?? "\(sz)"
                    infoText("\(sel.count)개 선택")
                    pipe()
                    infoText(szStr + " B")
                } else if let item = tab.cursorFile {
                    // Nexus File 스타일: 67,584 | 2013-03-10 16:43 | A_S | bootstat.dat
                    if !item.isDirectory {
                        infoText(item.sizeBytesFormatted)
                        pipe()
                        infoText(item.infoDateString)
                        pipe()
                        Text(item.attrString)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(NX.folderText)  // 황금색
                        pipe()
                    }
                    Text(item.name)
                        .font(.system(size: 11))
                        .foregroundStyle(NX.fileText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if !appState.statusMessage.isEmpty {
                Text(appState.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(NX.infoText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: 22)
        .background(NX.infoBg)
        .overlay(alignment: .top) { Rectangle().frame(height: 1).foregroundStyle(NX.separator) }
    }

    @ViewBuilder private func infoText(_ s: String) -> some View {
        Text(s).font(.system(size: 11)).foregroundStyle(NX.infoText)
    }

    @ViewBuilder private func pipe() -> some View {
        Text("  |  ").font(.system(size: 11)).foregroundStyle(NX.separator)
    }
}

// MARK: - Function Key Bar  ── F2 Rename | F3 Copy To | F4 Move To ...

struct FunctionKeyBar: View {
    @Environment(AppState.self) private var appState
    @State private var showQuitConfirm = false

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // F2 이름 변경 — 커서 파일 없으면 비활성
                fKey("F2", "Rename", disabled: appState.activePane.activeTab?.cursorFile == nil) {
                    if let item = appState.activePane.activeTab?.cursorFile {
                        appState.renameText = item.name
                        appState.showRename = true
                    }
                }
                div()
                // F3 보기 — 파일일 때만 활성
                fKey("F3", "View", disabled: {
                    guard let item = appState.activePane.activeTab?.cursorFile else { return true }
                    return item.isDirectory || !item.isViewable
                }()) {
                    if let item = appState.activePane.activeTab?.cursorFile, !item.isDirectory {
                        appState.viewerURL = item.url
                        appState.showViewer = true
                    }
                }
                div()
                // F4 편집 — 파일일 때만 활성
                fKey("F4", "Edit", disabled: appState.activePane.activeTab?.cursorFile?.isDirectory == true) {
                    if let item = appState.activePane.activeTab?.cursorFile {
                        NSWorkspace.shared.open(item.url)
                    }
                }
                div()
                fKey("F5", "Copy To")  { appState.copySelectionToOpposite() }
                div()
                fKey("F6", "Move To")  { appState.moveSelectionToOpposite() }
                div()
                fKey("F7", "New Folder") {
                    appState.newFolderName = ""
                    appState.showNewFolder = true
                }
                div()
                // F8 삭제 — 선택/커서 없으면 비활성
                fKey("F8", "Delete",
                     disabled: appState.activePane.activeTab?.effectiveSelections.isEmpty == true
                ) {
                    appState.deleteSelection()
                }
                div()
                fKey("F9", "FTP") { appState.showFTP = true }
                div()
                fKey("F10", "Quit") { showQuitConfirm = true }
            }
            .frame(width: geo.size.width, height: 26)
        }
        .frame(height: 26)
        .background(Color(hex: "#161616"))
        .overlay(alignment: .top) { Rectangle().frame(height: 1).foregroundStyle(NX.separator) }
        .confirmationDialog("AxlFile를 종료하시겠습니까?", isPresented: $showQuitConfirm) {
            Button("종료", role: .destructive) { NSApplication.shared.terminate(nil) }
            Button("취소", role: .cancel) {}
        }
    }

    // F키 버튼: 번호(황금) + 레이블(흰색), disabled 시 흐리게
    @ViewBuilder
    private func fKey(_ key: String, _ label: String,
                      disabled: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(key)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(disabled ? NX.attrText : NX.folderText)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(disabled ? NX.attrText : NX.fkeyText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // 구분선 |
    @ViewBuilder
    private func div() -> some View {
        Text("|")
            .font(.system(size: 11))
            .foregroundStyle(NX.separator)
            .frame(width: 12, height: 26)
    }
}

// NumberFormatter 체이닝 헬퍼
extension NumberFormatter {
    func apply(_ configure: (NumberFormatter) -> Void) -> NumberFormatter {
        configure(self); return self
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

// MARK: - New File Dialog

struct NewFileDialog: View {
    @Environment(AppState.self) private var appState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "doc.badge.plus")
                    .font(.title2)
                    .foregroundStyle(NX.folderText)
                Text("새 파일 만들기").font(.headline)
            }
            TextField("파일 이름 (예: memo.txt)", text: Binding(
                get: { appState.newFileName },
                set: { appState.newFileName = $0 }
            ))
            .focused($focused)
            .textFieldStyle(.roundedBorder)
            .frame(width: 300)
            .onSubmit { confirm() }
            HStack {
                Button("취소") { appState.showNewFile = false }
                    .keyboardShortcut(.escape)
                Button("만들기") { confirm() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.newFileName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .onAppear { focused = true }
    }

    private func confirm() {
        guard !appState.newFileName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        appState.createFile()
        appState.showNewFile = false
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
