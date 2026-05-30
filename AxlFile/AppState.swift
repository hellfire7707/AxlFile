import Foundation
import SwiftUI

enum ClipboardOp { case copy, move }

@Observable
class AppState {
    var leftPane: PaneState
    var rightPane: PaneState
    var activePaneID: PaneID = .left

    var showHidden = false

    // 뷰어
    var showViewer = false
    var viewerURL: URL?

    // FTP
    var showFTP = false
    var ftpPane: PaneState?

    // 다이얼로그
    var showNewFolder = false
    var newFolderName = ""
    var showNewFile = false
    var newFileName = ""
    var showRename = false
    var renameText = ""
    var showProperties = false
    var propertiesTarget: URL?

    // 클립보드
    var clipboard: [URL] = []
    var clipboardOp: ClipboardOp = .copy

    // 작업 진행
    var isWorking = false
    var workProgress: Double = 0
    var workMessage = ""

    // 상태 표시줄
    var statusMessage = ""

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        leftPane  = PaneState(url: home)
        rightPane = PaneState(url: home)
    }

    var activePane: PaneState {
        activePaneID == .left ? leftPane : rightPane
    }

    var oppositePane: PaneState {
        activePaneID == .left ? rightPane : leftPane
    }

    func switchActivePane() {
        activePaneID = activePaneID == .left ? .right : .left
    }

    // 반대 패널로 복사 or 이동 실행
    func copySelectionToOpposite() {
        guard let src = activePane.activeTab,
              let dst = oppositePane.activeTab else { return }
        let items = src.effectiveSelections.map { $0.url }
        guard !items.isEmpty else { return }
        clipboard = items
        clipboardOp = .copy
        Task { await performPaste(destinationURL: dst.url, targetPane: oppositePane) }
    }

    func moveSelectionToOpposite() {
        guard let src = activePane.activeTab,
              let dst = oppositePane.activeTab else { return }
        let items = src.effectiveSelections.map { $0.url }
        guard !items.isEmpty else { return }
        clipboard = items
        clipboardOp = .move
        Task { await performPaste(destinationURL: dst.url, targetPane: oppositePane) }
    }

    func performPaste(destinationURL: URL? = nil, targetPane: PaneState? = nil) async {
        guard !clipboard.isEmpty else { return }
        let destPane = targetPane ?? activePane
        guard let dstTab = destPane.activeTab else { return }
        let dst = destinationURL ?? dstTab.url
        isWorking = true
        workProgress = 0
        workMessage = clipboardOp == .copy ? "복사 중..." : "이동 중..."
        defer {
            isWorking = false
            workProgress = 0
            workMessage = ""
        }
        let items = clipboard
        let op = clipboardOp
        do {
            let mgr = FileOperationManager()
            try await mgr.perform(op: op, items: items, destination: dst) { [weak self] p in
                self?.workProgress = p
            }
            await reload(pane: destPane)
            if op == .move {
                clipboard = []
                await reload(pane: activePane)
            }
            statusMessage = op == .copy ? "복사 완료" : "이동 완료"
        } catch {
            statusMessage = "오류: \(error.localizedDescription)"
        }
    }

    func deleteSelection() {
        guard let tab = activePane.activeTab else { return }
        let items = tab.effectiveSelections.map { $0.url }
        guard !items.isEmpty else { return }
        Task {
            isWorking = true
            workMessage = "삭제 중..."
            defer { isWorking = false; workMessage = "" }
            do {
                let mgr = FileOperationManager()
                try await mgr.deleteItems(items) { [weak self] p in
                    self?.workProgress = p
                }
                await reload(pane: activePane)
                statusMessage = "삭제 완료"
            } catch {
                statusMessage = "오류: \(error.localizedDescription)"
            }
        }
    }

    func createFile() {
        guard let tab = activePane.activeTab else { return }
        let name = newFileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            do {
                let dst = tab.url.appendingPathComponent(name)
                guard !FileManager.default.fileExists(atPath: dst.path) else {
                    statusMessage = "이미 존재하는 파일: \(name)"
                    return
                }
                FileManager.default.createFile(atPath: dst.path, contents: nil)
                await reload(pane: activePane)
                // 생성된 파일로 커서 이동
                if let created = tab.files.first(where: { $0.name == name }) {
                    tab.cursorID = created.id
                }
                statusMessage = "파일 생성: \(name)"
            } catch {
                statusMessage = "오류: \(error.localizedDescription)"
            }
        }
        newFileName = ""
    }

    func createFolder() {
        guard let tab = activePane.activeTab else { return }
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            do {
                let dst = tab.url.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
                await reload(pane: activePane)
                statusMessage = "폴더 생성: \(name)"
            } catch {
                statusMessage = "오류: \(error.localizedDescription)"
            }
        }
        newFolderName = ""
    }

    func renameActive() {
        guard let tab = activePane.activeTab,
              let item = tab.cursorFile else { return }
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != item.name else { return }
        Task {
            do {
                let dst = item.url.deletingLastPathComponent().appendingPathComponent(newName)
                try FileManager.default.moveItem(at: item.url, to: dst)
                await reload(pane: activePane)
                statusMessage = "이름 변경: \(newName)"
            } catch {
                statusMessage = "오류: \(error.localizedDescription)"
            }
        }
    }

    func reload(pane: PaneState) async {
        guard let tab = pane.activeTab else { return }
        await loadTab(tab, showHidden: showHidden)
    }

    func loadTab(_ tab: TabInfo, showHidden: Bool) async {
        tab.isLoading = true
        let url = tab.url
        // GCD로 파일 I/O를 백그라운드에서 실행 — Swift concurrency 스케줄러 우회
        let result: Result<[FileItem], Error> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let r = Result { try loadDirectory(url: url, showHidden: showHidden) }
                continuation.resume(returning: r)
            }
        }
        tab.isLoading = false
        switch result {
        case .success(let items):
            tab.files = items
            if tab.cursorID == nil || !items.contains(where: { $0.id == tab.cursorID }) {
                tab.cursorID = items.first?.id
            }
        case .failure(let error):
            tab.files = []
            statusMessage = "로드 실패: \(error.localizedDescription)"
        }
    }

    func navigate(tab: TabInfo, to url: URL) {
        tab.url = url
        Task { await loadTab(tab, showHidden: showHidden) }
    }
}
