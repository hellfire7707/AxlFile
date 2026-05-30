import SwiftUI

// MARK: - FileListView

struct FileListView: View {
    @Environment(AppState.self) private var appState
    var tab: TabInfo
    var paneID: PaneID
    var isActive: Bool
    var focusedPane: FocusState<PaneID?>.Binding

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
        .focusable()
        .focused(focusedPane, equals: paneID)
        .onKeyPress { handleKey($0) }
        .overlay {
            if tab.isLoading {
                ZStack {
                    Color(nsColor: .controlBackgroundColor).opacity(0.6)
                    ProgressView()
                }
            }
        }
    }

    // MARK: - Key Handling

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow:   moveCursor(by: -1);  return .handled
        case .downArrow: moveCursor(by:  1);  return .handled
        case .pageUp:    moveCursor(by: -20); return .handled
        case .pageDown:  moveCursor(by:  20); return .handled
        case .home:      setCursor(files.first);  return .handled
        case .end:       setCursor(files.last);   return .handled
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
        case _ where press.modifiers.contains(.command) && press.characters == "t":
            currentPane.addTab(url: tab.url)
            Task { if let t = currentPane.activeTab {
                await appState.loadTab(t, showHidden: appState.showHidden) }}
            return .handled
        case _ where press.modifiers.contains(.command) && press.characters == "w":
            if let idx = currentPane.tabs.firstIndex(where: { $0.id == tab.id }) {
                currentPane.closeTab(at: idx)
            }
            return .handled

        // Backspace — 상위 폴더
        case "\u{7F}", "\u{8}": goUp(); return .handled

        // F2 이름 변경
        case "\u{F702}":
            if let item = tab.cursorFile { appState.renameText = item.name; appState.showRename = true }
            return .handled
        // F3 보기
        case "\u{F703}":
            if let item = tab.cursorFile, !item.isDirectory {
                appState.viewerURL = item.url; appState.showViewer = true
            }
            return .handled
        // F5 복사
        case "\u{F705}": appState.copySelectionToOpposite(); return .handled
        // F6 이동
        case "\u{F706}": appState.moveSelectionToOpposite(); return .handled
        // F7 새 폴더
        case "\u{F707}": appState.newFolderName = ""; appState.showNewFolder = true; return .handled
        // F8 삭제
        case "\u{F708}", "\u{F728}": appState.deleteSelection(); return .handled

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

    private func openItem(_ item: FileItem) {
        if item.isDirectory {
            appState.navigate(tab: tab, to: item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func goUp() {
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

        if isSingle && !first.isDirectory {
            Button {
                NSWorkspace.shared.open(first.url)
            } label: {
                Label("다른 앱으로 열기...", systemImage: "square.and.arrow.up")
            }
        }

        Divider()

        // 보기 / 편집
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

        // 클립보드
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

        if isSingle {
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

// NSWorkspace에서 실제 Finder 아이콘을 가져와 표시
struct FinderIconView: View {
    let url: URL
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
            // NSWorkspace.icon(forFile:)는 Launch Services 캐시를 사용하므로 빠름
            icon = FinderIconCache.shared.icon(for: url)
        }
    }
}

// 확장자 기준으로 캐싱 (같은 타입 파일은 같은 아이콘)
@MainActor
final class FinderIconCache {
    static let shared = FinderIconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for url: URL) -> NSImage {
        // 폴더/패키지는 경로 기준, 파일은 확장자 기준으로 캐싱
        var key: String
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            // 커스텀 아이콘이 있을 수 있으니 경로 기준
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
            // Finder 아이콘
            FinderIconView(url: item.url)
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
