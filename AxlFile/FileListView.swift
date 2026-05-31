import SwiftUI
import UniformTypeIdentifiers

// MARK: - FileListView

struct FileListView: View {
    @Environment(AppState.self) private var appState
    var tab: TabInfo
    var paneID: PaneID
    var isActive: Bool
    var focusedPane: FocusState<PaneID?>.Binding

    // Shift 범위 선택의 기준점
    @State private var anchorID: UUID?

    private var files: [FileItem] { tab.displayFiles(showHidden: appState.showHidden) }

    var body: some View {
        VStack(spacing: 0) {
            ColumnHeaderView(tab: tab)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(files.enumerated()), id: \.element.id) { idx, item in
                            FileRowView(
                                item: item,
                                rowIndex: idx,
                                isSelected: tab.selectedIDs.contains(item.id),
                                isCursor: tab.cursorID == item.id,
                                isActive: isActive
                            )
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.activePaneID = paneID
                                focusedPane.wrappedValue = paneID
                                tab.cursorID    = item.id
                                tab.selectedIDs = []
                                anchorID        = nil
                            }
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                openItem(item)
                            })
                            .contextMenu { rowContextMenu(for: item) }
                        }
                    }
                }
                .onChange(of: tab.cursorID) { _, newID in
                    if let id = newID {
                        withAnimation(.easeInOut(duration: 0.08)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(NX.listBg)
        .focusable()
        .focused(focusedPane, equals: paneID)
        .onKeyPress { handleKey($0) }
        .overlay {
            if tab.isLoading {
                ZStack {
                    NX.listBg.opacity(0.8)
                    ProgressView()
                }
            }
        }
    }

    // MARK: - Key Handling

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow:
            if press.modifiers.contains(.shift) {
                shiftSelect(by: -1)
            } else {
                anchorID = nil
                moveCursor(by: -1)
            }
            return .handled
        case .downArrow:
            if press.modifiers.contains(.shift) {
                shiftSelect(by: 1)
            } else {
                anchorID = nil
                moveCursor(by: 1)
            }
            return .handled
        case .pageUp:    anchorID = nil; moveCursor(by: -20); return .handled
        case .pageDown:  anchorID = nil; moveCursor(by:  20); return .handled
        case .home:      anchorID = nil; setCursor(files.first);  return .handled
        case .end:       anchorID = nil; setCursor(files.last);   return .handled
        case .return:
            if let item = tab.cursorFile { openItem(item) }
            return .handled
        case .tab:
            appState.switchActivePane()
            focusedPane.wrappedValue = appState.activePaneID
            return .handled
        case .space:
            if let item = tab.cursorFile {
                if tab.selectedIDs.contains(item.id) { tab.selectedIDs.remove(item.id) }
                else { tab.selectedIDs.insert(item.id) }
                moveCursor(by: 1)
            }
            return .handled
        default: break
        }

        switch press.characters {
        case _ where press.modifiers.contains(.command) && press.characters == "a":
            tab.selectedIDs = Set(files.map { $0.id })
            return .handled
        case _ where press.modifiers.contains(.command) && press.characters == "n":
            appState.newFileName = ""
            appState.showNewFile = true
            return .handled
        case _ where press.modifiers.contains(.command) && press.characters == "t":
            appState.addNewTab(in: currentPane)
            return .handled
        case _ where press.modifiers.contains(.command) && press.characters == "w":
            if let idx = currentPane.tabs.firstIndex(where: { $0.id == tab.id }) {
                currentPane.closeTab(at: idx)
            }
            return .handled

        // Backspace — 상위 폴더
        case "\u{7F}", "\u{8}": goUp(); return .handled

        // ── F키 (macOS: F1=\u{F704}, F2=\u{F705}, F3=\u{F706}, ...) ──
        // F2 이름 변경
        case "\u{F705}":
            if let item = tab.cursorFile {
                appState.renameText = item.name
                appState.showRename = true
            }
            return .handled

        // F3 반대 패널로 복사
        case "\u{F706}": appState.copySelectionToOpposite(); return .handled

        // F4 반대 패널로 이동
        case "\u{F707}": appState.moveSelectionToOpposite(); return .handled

        // F5 새로고침
        case "\u{F708}":
            Task {
                await appState.reload(pane: appState.leftPane)
                await appState.reload(pane: appState.rightPane)
            }
            return .handled

        // F7 새 폴더
        case "\u{F70A}":
            appState.newFolderName = ""
            appState.showNewFolder = true
            return .handled

        // F8 삭제 (휴지통)  |  fn+Delete(Forward Delete) 도 동일
        case "\u{F70B}", "\u{F728}": appState.deleteSelection(); return .handled

        // F9 FTP
        case "\u{F70C}": appState.showFTP = true; return .handled

        default: return .ignored
        }
    }

    // MARK: - Helpers

    private var currentPane: PaneState {
        paneID == .left ? appState.leftPane : appState.rightPane
    }

    private func moveCursor(by delta: Int) {
        guard !files.isEmpty else { return }
        let cur  = files.firstIndex { $0.id == tab.cursorID } ?? 0
        let next = max(0, min(files.count - 1, cur + delta))
        tab.cursorID = files[next].id
    }

    private func setCursor(_ item: FileItem?) { tab.cursorID = item?.id }

    // Shift+방향키: 앵커~커서 사이 범위 선택
    private func shiftSelect(by delta: Int) {
        guard !files.isEmpty else { return }
        // 앵커가 없으면 현재 커서 위치로 설정
        if anchorID == nil { anchorID = tab.cursorID ?? files.first?.id }
        moveCursor(by: delta)
        guard let anchorID,
              let anchorIdx = files.firstIndex(where: { $0.id == anchorID }),
              let cursorIdx = files.firstIndex(where: { $0.id == tab.cursorID })
        else { return }
        let lo = min(anchorIdx, cursorIdx)
        let hi = max(anchorIdx, cursorIdx)
        tab.selectedIDs = Set(files[lo...hi].map { $0.id })
    }

    private func openItem(_ item: FileItem) {
        if item.isDirectory {
            appState.navigate(tab: tab, to: item.url)
        } else if !tab.isSFTP {
            NSWorkspace.shared.open(item.url)
        }
        // SFTP 파일 열기: 향후 다운로드 후 열기 지원 예정
    }

    private func goUp() {
        guard tab.url.path != "/" else { return }
        let parent = tab.url.deletingLastPathComponent()
        guard parent != tab.url else { return }
        appState.navigate(tab: tab, to: parent)
    }

    // 우클릭 대상 아이템 목록 — 우클릭한 항목이 선택에 포함돼 있으면 전체 선택, 아니면 해당 항목만
    private func targets(for item: FileItem) -> [FileItem] {
        if tab.selectedIDs.contains(item.id) {
            return tab.files.filter { tab.selectedIDs.contains($0.id) }
        }
        return [item]
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func rowContextMenu(for item: FileItem) -> some View {
        let items = targets(for: item)
        let isSingle = items.count == 1
        let first = items[0]

        // 열기
        Button {
            if isSingle { openItem(first) }
            else { items.forEach { openItem($0) } }
        } label: {
            Label("열기", systemImage: "return")
        }

        if isSingle && !first.isDirectory && !tab.isSFTP {
            Button {
                NSWorkspace.shared.open(first.url)
            } label: {
                Label("다른 앱으로 열기...", systemImage: "square.and.arrow.up")
            }
        }

        Divider()

        // 보기 / 편집 (로컬 전용)
        if !tab.isSFTP {
            if isSingle && !first.isDirectory && first.isViewable {
                Button {
                    appState.viewerURL = first.url
                    appState.showViewer = true
                } label: {
                    Label("보기 (F3)", systemImage: "eye")
                }
            }

            if isSingle {
                Button {
                    NSWorkspace.shared.open(first.url)
                } label: {
                    Label("편집 (F4)", systemImage: "pencil")
                }
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting(items.map { $0.url })
            } label: {
                Label("Finder에서 보기", systemImage: "folder")
            }

            Divider()

            // 클립보드 (로컬 전용)
            Button {
                appState.clipboard    = items.map { $0.url }
                appState.clipboardOp  = .copy
            } label: {
                Label("복사", systemImage: "doc.on.doc")
            }

            Button {
                appState.clipboard    = items.map { $0.url }
                appState.clipboardOp  = .move
            } label: {
                Label("잘라내기", systemImage: "scissors")
            }

            Button {
                Task { await appState.performPaste() }
            } label: {
                Label("붙여넣기", systemImage: "doc.on.clipboard")
            }
            .disabled(appState.clipboard.isEmpty)
        }

        Divider()

        // 반대 패널로
        Button {
            // 우클릭 항목을 커서로 설정 후 복사
            tab.cursorID = first.id
            if !tab.selectedIDs.contains(first.id) { tab.selectedIDs = [] }
            appState.copySelectionToOpposite()
        } label: {
            Label("반대 패널로 복사 (F5)", systemImage: "arrow.right.doc.on.clipboard")
        }

        Button {
            tab.cursorID = first.id
            if !tab.selectedIDs.contains(first.id) { tab.selectedIDs = [] }
            appState.moveSelectionToOpposite()
        } label: {
            Label("반대 패널로 이동 (F6)", systemImage: "arrow.right.arrow.left")
        }

        Divider()

        // 파일 조작
        Button {
            appState.newFolderName = ""
            appState.showNewFolder = true
        } label: {
            Label("새 폴더 (F7)", systemImage: "folder.badge.plus")
        }

        if isSingle {
            Button {
                tab.cursorID = first.id
                appState.renameText = first.name
                appState.showRename = true
            } label: {
                Label("이름 변경 (F2)", systemImage: "pencil.line")
            }
        }

        Button(role: .destructive) {
            tab.cursorID = first.id
            if !tab.selectedIDs.contains(first.id) { tab.selectedIDs = [] }
            appState.deleteSelection()
        } label: {
            Label("삭제 (F8)", systemImage: "trash")
        }

        Divider()

        // 전체 선택
        Button {
            tab.selectedIDs = Set(files.map { $0.id })
        } label: {
            Label("전체 선택", systemImage: "checkmark.circle")
        }

        if isSingle && !tab.isSFTP {
            Divider()

            Button {
                appState.propertiesTarget = first.url
                appState.showProperties   = true
            } label: {
                Label("속성 보기", systemImage: "info.circle")
            }
        }
    }
}

// MARK: - Column Header

struct ColumnHeaderView: View {
    var tab: TabInfo

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 24) // icon
            colBtn(.name, "이름",   width: nil)
            colBtn(.ext,  "확장자", width: 52)
            colBtn(.size, "크기",   width: 80)
            colBtn(.date, "날짜",   width: 116)
            Spacer().frame(width: 24) // attr
        }
        .frame(height: 20)
        .background(NX.headerBg)
        .overlay(alignment: .bottom) { Rectangle().frame(height: 1).foregroundStyle(NX.separator) }
    }

    @ViewBuilder
    private func colBtn(_ field: SortField, _ label: String, width: CGFloat?) -> some View {
        Button {
            if tab.sortField == field { tab.sortAscending.toggle() }
            else { tab.sortField = field; tab.sortAscending = true }
        } label: {
            HStack(spacing: 2) {
                Text(label).font(.system(size: 10, weight: .semibold))
                if tab.sortField == field {
                    Image(systemName: tab.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .foregroundStyle(NX.headerText)
            .frame(maxWidth: width ?? .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .frame(height: 20)
        }
        .buttonStyle(.borderless)
        .if(width != nil) { $0.frame(width: width!) }
    }
}

// MARK: - Finder Icon View

// NSWorkspace에서 실제 Finder 아이콘을 가져와 표시 (로컬·SFTP 공용)
struct FinderIconView: View {
    let url: URL
    var isDirectory: Bool = false
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: 16, height: 16)
        .onAppear {
            guard icon == nil else { return }
            icon = FinderIconCache.shared.icon(for: url, isDirectory: isDirectory)
        }
    }
}

// 확장자/UTType 기준으로 캐싱 (같은 타입 파일은 같은 아이콘)
@MainActor
final class FinderIconCache {
    static let shared = FinderIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for url: URL, isDirectory: Bool = false) -> NSImage {
        // SFTP 항목: 로컬 파일 없음 → UTType 기반 Finder 아이콘 사용
        if url.scheme == "sftp" {
            return sftpIcon(ext: url.pathExtension.lowercased(), isDirectory: isDirectory)
        }

        // 로컬 항목: 폴더/패키지는 경로 기준(커스텀 아이콘 지원), 파일은 확장자 기준
        var key: String
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            key = url.path
        } else {
            let ext = url.pathExtension.lowercased()
            key = ext.isEmpty ? url.lastPathComponent : ".\(ext)"
        }
        if let cached = cache[key] { return cached }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        cache[key] = img
        return img
    }

    private func sftpIcon(ext: String, isDirectory: Bool) -> NSImage {
        let key = isDirectory ? "__dir__" : (ext.isEmpty ? "__file__" : "__\(ext)__")
        if let cached = cache[key] { return cached }
        let img: NSImage
        if isDirectory {
            img = NSWorkspace.shared.icon(for: .folder)
        } else if !ext.isEmpty, let utType = UTType(filenameExtension: ext) {
            img = NSWorkspace.shared.icon(for: utType)
        } else {
            img = NSWorkspace.shared.icon(for: .data)
        }
        cache[key] = img
        return img
    }
}

// MARK: - File Row

struct FileRowView: View {
    var item: FileItem
    var rowIndex: Int
    var isSelected: Bool
    var isCursor: Bool
    var isActive: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Finder 아이콘 (로컬·SFTP 공용 — UTType 기반)
            FinderIconView(url: item.url, isDirectory: item.isDirectory)
                .frame(width: 24, alignment: .center)
                .opacity(isSelected ? 0.85 : 1.0)

            // 이름
            Text(item.name)
                .font(.system(size: 11))
                .foregroundStyle(nameTint)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)

            // 확장자
            Text(item.isDirectory ? "" : item.ext)
                .font(.system(size: 10))
                .foregroundStyle(NX.extText)
                .frame(width: 52, alignment: .leading)
                .padding(.horizontal, 2)

            // 크기
            Text(item.sizeString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(NX.sizeText)
                .frame(width: 80, alignment: .trailing)
                .padding(.trailing, 4)

            // 날짜
            Text(item.dateString)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(NX.dateText)
                .frame(width: 116, alignment: .trailing)
                .padding(.trailing, 4)

            // 속성
            Text(item.attrString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(NX.attrText)
                .frame(width: 24, alignment: .center)
        }
        .frame(height: 20)
        .background(rowBg)
        .opacity(item.isHidden ? 0.50 : 1.0)
    }

    private var nameTint: Color {
        if isSelected { return NX.selectedText }
        if isCursor && isActive { return NX.cursorText }
        // Finder처럼 폴더/파일 모두 동일한 텍스트 색상 (흰색 계열)
        return NX.fileText
    }

    private var rowBg: some ShapeStyle {
        if isSelected && isActive {
            return AnyShapeStyle(NX.selected)
        } else if isSelected {
            return AnyShapeStyle(NX.selected.opacity(0.50))
        } else if isCursor && isActive {
            return AnyShapeStyle(NX.cursor)
        } else if isCursor {
            return AnyShapeStyle(NX.cursor.opacity(0.40))
        }
        return AnyShapeStyle(rowIndex % 2 == 0 ? NX.rowEven : NX.rowOdd)
    }
}

// MARK: - View Extension

extension View {
    @ViewBuilder func `if`<T: View>(_ cond: Bool, transform: (Self) -> T) -> some View {
        if cond { transform(self) } else { self }
    }
}
