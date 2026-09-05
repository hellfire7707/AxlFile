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
        ZStack {
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
            .sheet(isPresented: Binding(get: { appState.showViewer }, set: { appState.showViewer = $0 })) {
                if let url = appState.viewerURL { ViewerView(url: url) }
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

            // 다이얼로그 — ZStack 최상단 레이어로 패널 테두리보다 위에 렌더링
            //              (시트를 쓰면 창 모서리가 둥글게 잘리므로 각진 오버레이로 표시)
            if appState.showNewFolder {
                NewFolderDialog().environment(appState)
            }
            if appState.showNewFile {
                NewFileDialog().environment(appState)
            }
            if appState.showRename {
                RenameDialog().environment(appState)
            }
            if appState.showZipName {
                ZipNameDialog().environment(appState)
            }
            if appState.showDeleteConfirm {
                DeleteConfirmDialog().environment(appState)
            }
            if appState.work != nil {
                WorkingOverlay().environment(appState)
            }
            if appState.showFTP {
                SFTPConnectView().environment(appState)
            }
            if let alert = appState.errorAlert {
                ErrorAlertDialog(alert: alert) { appState.errorAlert = nil }
            }
            if let conflict = appState.overwriteConflict {
                OverwriteConflictDialog(conflict: conflict) { action in
                    appState.overwriteConflict = nil
                    conflict.resolve(action)
                }
            }
        }
        .task {
            if let lt = appState.leftPane.activeTab {
                await appState.loadTab(lt)
            }
            if let rt = appState.rightPane.activeTab {
                await appState.loadTab(rt)
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
                        appState.beginRename(item)
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
    var body: some View {
        WorkProgressPanel()
    }
}

struct WorkProgressPanel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let work = appState.work {
            panel(work: work)
        }
    }

    @ViewBuilder
    private func panel(work: WorkState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(work.message)
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
            .background(Color(hex: "#404040"))
            .overlay(alignment: .bottom) { Rectangle().frame(height: 1).foregroundStyle(Color(hex: "#555555")) }

            VStack(alignment: .leading, spacing: 5) {
                pathLine(work.sourcePath)
                if !work.destPath.isEmpty {
                    pathLine(work.destPath)
                }

                Spacer().frame(height: 2)

                Text(work.currentFile.isEmpty ? " " : work.currentFile)
                    .font(.system(size: 11))
                    .foregroundStyle(NX.infoText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ProgressView(value: max(0.001, work.progress))
                    .tint(Color(hex: "#E8820A"))
                    .animation(.linear(duration: 0.1), value: work.progress)

                HStack(spacing: 8) {
                    Text(fmtBytes(work.bytes))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(NX.infoText)
                    Text(work.totalCount > 0
                         ? "\(work.fileCount) / \(work.totalCount)"
                         : "\(work.fileCount)")
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
        .background(Color(hex: "#323232"))
        .overlay {
            Rectangle().strokeBorder(Color(hex: "#555555"), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.8), radius: 20, x: 0, y: 8)
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

// MARK: - Error Alert Dialog

struct ErrorAlertDialog: View {
    let alert: ErrorAlert
    var onDismiss: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }
            panel
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.red)
                Text(alert.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NX.fileText)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(hex: "#404040"))
            .overlay(alignment: .bottom) { Rectangle().frame(height: 1).foregroundStyle(Color(hex: "#555555")) }

            ScrollView {
                Text(alert.message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(NX.infoText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(maxHeight: 200)

            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Text("확인")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 5)
                        .background(NX.cursor)
                        .overlay { Rectangle().strokeBorder(NX.separator, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(hex: "#323232"))
        .overlay { Rectangle().strokeBorder(Color(hex: "#555555"), lineWidth: 1) }
        .shadow(color: .black.opacity(0.8), radius: 20, x: 0, y: 8)
        // Esc 로도 닫히도록 포커스 확보
        .background(
            Color.clear
                .focusable()
                .focused($focused)
                .focusEffectDisabled()
                .onKeyPress(.escape) { onDismiss(); return .handled }
                .onKeyPress(.return) { onDismiss(); return .handled }
        )
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true } }
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
        NXDialogPanel(title: "삭제 확인", icon: "trash", iconColor: .red, width: 380) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(NX.fileText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Spacer()
                    dialogBtn("취소", isSelected: selected == 0, isDestructive: false) { cancel() }
                    dialogBtn("삭제", isSelected: selected == 1, isDestructive: true) { confirm() }
                }
            }
            // 포커스용 투명 뷰로 키보드 이벤트 수신
            .background(
                Color.clear
                    .focusable()
                    .focused($focused)
                    .focusEffectDisabled()
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
    }

    @ViewBuilder
    private func dialogBtn(_ label: String, isSelected: Bool,
                           isDestructive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .frame(width: 76, height: 24)
                .foregroundStyle(isSelected
                    ? (isDestructive ? .white : NX.fileText)
                    : NX.infoText)
                .background(isSelected
                    ? (isDestructive ? Color.red.opacity(0.85) : NX.cursor)
                    : NX.headerBg)
                .overlay { Rectangle().strokeBorder(NX.separator, lineWidth: 1) }
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

// MARK: - 공통 다이얼로그 크롬 (각진 패널 — 라운드 없음)

/// 딤 배경 + 타이틀 바 + 각진 테두리를 가진 오버레이 패널.
struct NXDialogPanel<Content: View>: View {
    let title: String
    var icon: String?
    var iconColor: Color
    var width: CGFloat
    let content: Content

    init(title: String, icon: String? = nil, iconColor: Color = NX.folderText,
         width: CGFloat = 360, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.width = width
        self.content = content()
    }

    var body: some View {
        ZStack {
            // 뒤쪽 UI를 가리는 딤 배경 (클릭 차단)
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundStyle(iconColor)
                    }
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NX.fileText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(hex: "#404040"))
                .overlay(alignment: .bottom) {
                    Rectangle().frame(height: 1).foregroundStyle(Color(hex: "#555555"))
                }

                content
                    .padding(12)
            }
            .frame(width: width)
            // 세로는 내용 크기로 고정 — ZStack 안에서 화면 전체로 늘어나지 않도록
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(hex: "#323232"))
            .overlay { Rectangle().strokeBorder(Color(hex: "#555555"), lineWidth: 1) }
            .shadow(color: .black.opacity(0.8), radius: 20, x: 0, y: 8)
        }
    }
}

/// 각진 다이얼로그 버튼
struct NXDialogButton: View {
    let label: String
    var prominent = false
    var destructive = false
    var disabled = false
    let action: () -> Void

    init(_ label: String, prominent: Bool = false, destructive: Bool = false,
         disabled: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.prominent = prominent
        self.destructive = destructive
        self.disabled = disabled
        self.action = action
    }

    private var bg: Color {
        if disabled { return NX.headerBg }
        if destructive { return Color.red.opacity(0.85) }
        return prominent ? NX.cursor : NX.headerBg
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(disabled ? NX.attrText
                                 : ((prominent || destructive) ? .white : NX.fileText))
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(bg)
                .overlay { Rectangle().strokeBorder(NX.separator, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// 다이얼로그 입력 필드 레이블
struct NXFieldLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(NX.headerText)
    }
}

// MARK: - New File Dialog

struct NewFileDialog: View {
    @Environment(AppState.self) private var appState
    @FocusState private var focused: Bool

    private var isEmpty: Bool {
        appState.newFileName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NXDialogPanel(title: "새 파일 만들기", icon: "doc.badge.plus", width: 380) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("파일 이름 (예: memo.txt)", text: Binding(
                    get: { appState.newFileName },
                    set: { appState.newFileName = $0 }
                ))
                .focused($focused)
                .textFieldStyle(.squareBorder)
                .focusEffectDisabled()
                .overlay { Rectangle().strokeBorder(focused ? NX.focusBorder : .clear, lineWidth: 1) }
                .onSubmit { confirm() }

                HStack(spacing: 8) {
                    Spacer()
                    NXDialogButton("취소") { appState.showNewFile = false }
                        .keyboardShortcut(.escape)
                    NXDialogButton("만들기", prominent: true, disabled: isEmpty) { confirm() }
                        .keyboardShortcut(.return)
                }
            }
            // 시트가 아니므로 패널 뒤 파일목록으로 키가 새지 않도록 입력 필드에 포커스
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true } }
        }
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

    private var isEmpty: Bool {
        appState.newFolderName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NXDialogPanel(title: "새 폴더 만들기", icon: "folder.badge.plus", width: 360) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("폴더 이름", text: Binding(
                    get: { appState.newFolderName },
                    set: { appState.newFolderName = $0 }
                ))
                .focused($focused)
                .textFieldStyle(.squareBorder)
                .focusEffectDisabled()
                .overlay { Rectangle().strokeBorder(focused ? NX.focusBorder : .clear, lineWidth: 1) }
                .onSubmit { confirm() }

                HStack(spacing: 8) {
                    Spacer()
                    NXDialogButton("취소") { appState.showNewFolder = false }
                        .keyboardShortcut(.escape)
                    NXDialogButton("만들기", prominent: true, disabled: isEmpty) { confirm() }
                        .keyboardShortcut(.return)
                }
            }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true } }
        }
    }

    private func confirm() {
        guard !isEmpty else { return }
        appState.createFolder()
        appState.showNewFolder = false
    }
}

// MARK: - Zip Name Dialog

struct ZipNameDialog: View {
    @Environment(AppState.self) private var appState
    @FocusState private var focused: Bool

    private var isEmpty: Bool {
        appState.zipNameText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NXDialogPanel(title: "ZIP 압축", icon: "archivebox.fill", width: 380) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("압축 파일 이름", text: Binding(
                    get: { appState.zipNameText },
                    set: { appState.zipNameText = $0 }
                ))
                .focused($focused)
                .textFieldStyle(.squareBorder)
                .focusEffectDisabled()
                .overlay { Rectangle().strokeBorder(focused ? NX.focusBorder : .clear, lineWidth: 1) }
                .onSubmit { confirm() }

                HStack(spacing: 8) {
                    Spacer()
                    NXDialogButton("취소") { appState.showZipName = false }
                        .keyboardShortcut(.escape)
                    NXDialogButton("압축", prominent: true, disabled: isEmpty) { confirm() }
                        .keyboardShortcut(.return)
                }
            }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true } }
        }
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
    private enum Field { case base, ext }

    @Environment(AppState.self) private var appState
    @FocusState private var focused: Field?

    var body: some View {
        NXDialogPanel(title: "이름 변경", icon: "pencil.line", width: 420) {
            VStack(alignment: .leading, spacing: 10) {
                // 이름 / 확장자 분리 입력 — Tab 으로 이동
                HStack(alignment: .bottom, spacing: 5) {
                    VStack(alignment: .leading, spacing: 3) {
                        NXFieldLabel("이름")
                        TextField("이름", text: Binding(
                            get: { appState.renameText },
                            set: { appState.renameText = $0 }
                        ))
                        .focused($focused, equals: .base)
                        .textFieldStyle(.squareBorder)
                        .focusEffectDisabled()
                        .overlay { Rectangle().strokeBorder(focused == .base ? NX.focusBorder : .clear, lineWidth: 1) }
                        .onSubmit(confirm)
                    }

                    Text(".")
                        .font(.system(size: 11))
                        .foregroundStyle(NX.infoText)
                        .padding(.bottom, 4)

                    VStack(alignment: .leading, spacing: 3) {
                        NXFieldLabel("확장자")
                        TextField("확장자", text: Binding(
                            get: { appState.renameExt },
                            set: { appState.renameExt = $0 }
                        ))
                        .focused($focused, equals: .ext)
                        .textFieldStyle(.squareBorder)
                        .focusEffectDisabled()
                        .overlay { Rectangle().strokeBorder(focused == .ext ? NX.focusBorder : .clear, lineWidth: 1) }
                        .frame(width: 96)
                        .onSubmit(confirm)
                    }
                }

                // 합쳐진 최종 이름 미리보기
                Text(appState.renameFullName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(NX.infoText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Spacer()
                    NXDialogButton("취소") { appState.showRename = false }
                        .keyboardShortcut(.escape)
                    NXDialogButton("변경", prominent: true,
                                   disabled: appState.renameFullName.isEmpty) { confirm() }
                        .keyboardShortcut(.return)
                }
            }
            // 시트가 아니므로 패널 뒤 파일목록으로 키가 새지 않도록 첫 필드에 포커스
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = .base } }
        }
    }

    private func confirm() {
        guard !appState.renameFullName.isEmpty else { return }
        appState.renameActive()
        appState.showRename = false
    }
}
