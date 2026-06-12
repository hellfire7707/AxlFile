import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    private var deleteDialogTitle: String {
        let targets = appState.deleteTargets
        if targets.count == 1 {
            return "\"\(targets[0].name)\"을(를) 삭제하시겠습니까?"
        }
        return "\(targets.count)개 항목을 삭제하시겠습니까?"
    }

    var body: some View {
        VStack(spacing: 0) {
            DualPaneView()
                .environment(appState)
            if appState.showCommandBar {
                CommandBarView()
                    .environment(appState)
            }
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
            SFTPConnectView().environment(appState)
        }
        .sheet(isPresented: Binding(get: { appState.showProperties }, set: { appState.showProperties = $0 })) {
            if let url = appState.propertiesTarget { PropertiesView(url: url) }
        }
        .sheet(isPresented: Binding(get: { appState.showBookmarks }, set: { appState.showBookmarks = $0 })) {
            BookmarkView().environment(appState)
        }
        .sheet(isPresented: Binding(get: { appState.showDiff }, set: { appState.showDiff = $0 })) {
            if let l = appState.diffLeftURL, let r = appState.diffRightURL {
                DiffView(leftURL: l, rightURL: r)
            }
        }
        .sheet(isPresented: Binding(get: { appState.showPermissions }, set: { appState.showPermissions = $0 })) {
            if let url = appState.permissionsTarget { PermissionsView(url: url) }
        }
        .sheet(isPresented: Binding(get: { appState.showZipName }, set: { appState.showZipName = $0 })) {
            ZipNameDialog().environment(appState)
        }
        .overlay {
            if appState.isWorking { WorkingOverlay().environment(appState) }
        }
        .sheet(isPresented: Binding(
            get: { appState.showDeleteConfirm },
            set: { appState.showDeleteConfirm = $0 }
        )) {
            DeleteConfirmDialog().environment(appState)
        }
        .task {
            if let lt = appState.leftPane.activeTab {
                await appState.loadTab(lt, showHidden: appState.showHidden)
            }
            if let rt = appState.rightPane.activeTab {
                await appState.loadTab(rt, showHidden: appState.showHidden)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Toolbar (상단 아이콘 바)

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

// MARK: - Function Key Bar  ── F2 Rename | F3 Copy To | F4 Move To | F5 Refresh | F7 New Folder | F8 Delete | F9 SFTP | F10 Quit

struct FunctionKeyBar: View {
    @Environment(AppState.self) private var appState
    @State private var showQuitConfirm = false

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                // F2 이름 변경
                fKey("F2", "Rename", disabled: appState.activePane.activeTab?.cursorFile == nil) {
                    if let item = appState.activePane.activeTab?.cursorFile {
                        appState.renameText = item.name
                        appState.showRename = true
                    }
                }
                div()
                // F3 반대 패널로 복사
                fKey("F3", "Copy To") { appState.copySelectionToOpposite() }
                div()
                // F4 반대 패널로 이동
                fKey("F4", "Move To") { appState.moveSelectionToOpposite() }
                div()
                // F5 새로고침
                fKey("F5", "Refresh") {
                    Task {
                        await appState.reload(pane: appState.leftPane)
                        await appState.reload(pane: appState.rightPane)
                    }
                }
                div()
                // F6 ZIP 압축
                fKey("F6", "Pack") { appState.packSelection() }
                div()
                // F7 새 폴더
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
                fKey("F9", "SFTP") { appState.showFTP = true }
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

// MARK: - Work Progress Panel  (Nexus File 스타일)

struct WorkingOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            WorkProgressPanel(appState: appState)
        }
    }
}

struct WorkProgressPanel: View {
    var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 제목 바
            HStack {
                Text(appState.workMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NX.fileText)
                Spacer()
                Button { appState.cancelWork() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NX.infoText)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(NX.headerBg)
            .overlay(alignment: .bottom) { Rectangle().frame(height: 1).foregroundStyle(NX.separator) }

            VStack(alignment: .leading, spacing: 5) {
                // 소스 경로
                pathLine(appState.workSourcePath)
                // 목적지 경로
                if !appState.workDestPath.isEmpty {
                    pathLine(appState.workDestPath)
                }

                Spacer().frame(height: 2)

                // 현재 파일명
                Text(appState.workCurrentFile.isEmpty ? " " : appState.workCurrentFile)
                    .font(.system(size: 11))
                    .foregroundStyle(NX.infoText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // 프로그레스 바
                ProgressView(value: max(0.001, appState.workProgress))
                    .tint(Color(hex: "#3DB06B"))  // 녹색

                // 하단: 크기 + 파일수 + 취소 버튼
                HStack(spacing: 8) {
                    Text(fmtBytes(appState.workBytes))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(NX.infoText)
                    Text(appState.workTotalCount > 0
                         ? "\(appState.workFileCount) / \(appState.workTotalCount)"
                         : "\(appState.workFileCount)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(NX.infoText)
                    Spacer()
                    Button("취소(C)") { appState.cancelWork() }
                        .controlSize(.small)
                        .keyboardShortcut("c", modifiers: [])
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 430)
        .background(NX.bg)
        .overlay {
            Rectangle().strokeBorder(NX.separator, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.6), radius: 24, x: 0, y: 10)
    }

    @ViewBuilder
    private func pathLine(_ path: String) -> some View {
        Text(path.isEmpty ? " " : path)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(NX.pathText)
            .lineLimit(1)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fmtBytes(_ b: Int64) -> String {
        if b < 1024          { return "\(b) B" }
        if b < 1_048_576     { return String(format: "%.2f KB", Double(b) / 1024) }
        if b < 1_073_741_824 { return String(format: "%.2f MB", Double(b) / 1_048_576) }
        return String(format: "%.2f GB", Double(b) / 1_073_741_824)
    }
}

// MARK: - Delete Confirm Dialog

struct DeleteConfirmDialog: View {
    @Environment(AppState.self) private var appState
    // 0 = 취소 선택, 1 = 삭제 선택
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var title: String {
        let t = appState.deleteTargets
        if t.count == 1 { return "\"\(t[0].name)\"을(를) 삭제하시겠습니까?" }
        return "\(t.count)개 항목을 삭제하시겠습니까?"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash")
                .font(.system(size: 28))
                .foregroundStyle(.red)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                dialogBtn("취소", isSelected: selected == 0, isDestructive: false) {
                    cancel()
                }
                dialogBtn("삭제", isSelected: selected == 1, isDestructive: true) {
                    confirm()
                }
            }
        }
        .padding(28)
        .frame(width: 340)
        // 포커스용 투명 뷰로 키보드 이벤트 수신
        .background(
            Color.clear
                .focusable()
                .focused($focused)
                .onKeyPress(.leftArrow)  { selected = 0; return .handled }
                .onKeyPress(.rightArrow) { selected = 1; return .handled }
                .onKeyPress(.return) {
                    if selected == 1 { confirm() } else { cancel() }
                    return .handled
                }
                .onKeyPress(.escape) { cancel(); return .handled }
        )
        .onAppear {
            selected = 0       // 기본값: 취소 선택 (안전)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
    }

    @ViewBuilder
    private func dialogBtn(_ label: String, isSelected: Bool,
                           isDestructive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .frame(width: 80, height: 28)
                .foregroundStyle(isSelected
                    ? (isDestructive ? .white : NX.fileText)
                    : NX.infoText)
                .background(isSelected
                    ? (isDestructive ? Color.red : NX.cursor)
                    : NX.headerBg)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isSelected ? Color.clear : NX.separator, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func confirm() {
        appState.showDeleteConfirm = false
        appState.confirmDelete()
    }

    private func cancel() {
        appState.showDeleteConfirm = false
        appState.deleteTargets = []
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

// MARK: - Zip Name Dialog

struct ZipNameDialog: View {
    @Environment(AppState.self) private var appState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "archivebox.fill")
                    .font(.title2)
                    .foregroundStyle(NX.folderText)
                Text("ZIP 압축").font(.headline)
            }
            TextField("압축 파일 이름", text: Binding(
                get: { appState.zipNameText },
                set: { appState.zipNameText = $0 }
            ))
            .focused($focused)
            .textFieldStyle(.roundedBorder)
            .frame(width: 300)
            .onSubmit { confirm() }
            HStack {
                Button("취소") { appState.showZipName = false }
                    .keyboardShortcut(.escape)
                Button("압축") { confirm() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.zipNameText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .onAppear { focused = true }
    }

    private func confirm() {
        let name = appState.zipNameText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        appState.showZipName = false
        appState.confirmPackSelection()
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
