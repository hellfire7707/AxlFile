import Foundation
import SwiftUI
import AppKit

enum ClipboardOp { case copy, move }

@MainActor
@Observable
class AppState {
    var leftPane: PaneState
    var rightPane: PaneState
    var activePaneID: PaneID = .left

    var showIconView = false

    // 뷰어
    var showViewer = false
    var viewerURL: URL?

    // SFTP 연결 다이얼로그
    var showFTP = false

    // 다이얼로그
    var showNewFolder = false
    var newFolderName = ""
    var showNewFile   = false
    var newFileName   = ""
    var showRename    = false
    var renameText    = ""
    var showProperties  = false
    var propertiesTarget: URL?

    // 삭제 확인
    var showDeleteConfirm = false
    var deleteTargets: [FileItem] = []

    // 클립보드
    var clipboard: [URL] = []
    var clipboardOp: ClipboardOp = .copy
    private var lastPasteboardChangeCount: Int = -1

    // 작업 진행
    var isWorking       = false
    var workProgress:   Double = 0
    var workMessage     = ""
    var workCurrentFile = ""
    var workSourcePath  = ""
    var workDestPath    = ""
    var workBytes:      Int64 = 0
    var workFileCount   = 0
    var workTotalCount  = 0
    var workCancelled   = false
    private(set) var currentOperationMgr: FileOperationManager?

    // 상태 표시줄
    var statusMessage = ""

    // MARK: - 즐겨찾기
    var bookmarks: [Bookmark] = []
    var showBookmarks = false

    // MARK: - 커맨드 바
    var showCommandBar = false
    var commandText = ""
    var commandOutput = ""
    var commandHistory: [String] = []
    var commandIsRunning = false

    // MARK: - Diff
    var showDiff = false
    var diffLeftURL: URL?
    var diffRightURL: URL?

    // MARK: - 권한 편집
    var showPermissions = false
    var permissionsTarget: URL?

    // MARK: - 압축 (ZIP 이름 입력)
    var showZipName = false
    var zipNameText = ""

    // MARK: - 덮어쓰기 충돌 다이얼로그
    var overwriteConflict: OverwriteConflict?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let ud   = UserDefaults.standard

        // 환경설정 - 시작 폴더
        let startURL: URL
        if ud.string(forKey: "startupFolder") == "last",
           let lastPath = ud.string(forKey: "lastOpenedPath") {
            let candidate = URL(fileURLWithPath: lastPath)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: lastPath, isDirectory: &isDir), isDir.boolValue {
                startURL = candidate
            } else {
                startURL = home
            }
        } else {
            startURL = home
        }

        leftPane  = PaneState(url: startURL)
        rightPane = PaneState(url: startURL)

        loadBookmarks()
    }

    var activePane:   PaneState { activePaneID == .left ? leftPane : rightPane }
    var oppositePane: PaneState { activePaneID == .left ? rightPane : leftPane }

    func switchActivePane() { activePaneID = activePaneID == .left ? .right : .left }

    func pane(containing tab: TabInfo) -> PaneState {
        leftPane.tabs.contains(where: { $0.id == tab.id }) ? leftPane : rightPane
    }

    // MARK: - SFTP 탭 열기

    func openSFTPTab(client: SFTPClient) {
        let url = sftpURL(client: client, path: client.currentPath)
        activePane.addTab(url: url, sftpClient: client)
        Task {
            if let tab = activePane.activeTab { await loadTab(tab) }
        }
    }

    // MARK: - Tab 추가 (로컬 또는 SFTP 승계)

    func addNewTab(in pane: PaneState) {
        guard let cur = pane.activeTab else { return }
        if let client = cur.sftpClient {
            pane.addTab(url: cur.url, sftpClient: client)
        } else {
            pane.addTab(url: cur.url)
        }
        Task {
            if let t = pane.activeTab { await loadTab(t) }
        }
    }

    // MARK: - 디렉토리 로드

    func loadTab(_ tab: TabInfo, selectingName: String? = nil) async {
        let showHidden = pane(containing: tab).showHidden
        if let client = tab.sftpClient {
            await loadSFTPTab(tab, client: client)
            return
        }
        tab.isLoading = true
        let url = tab.url
        let result: Result<[FileItem], Error> = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let r = Result { try loadDirectory(url: url, showHidden: showHidden) }
                cont.resume(returning: r)
            }
        }
        tab.isLoading = false
        switch result {
        case .success(let items):
            tab.files = items
            let sorted = tab.displayFiles(showHidden: showHidden)
            if let name = selectingName, let target = sorted.first(where: { $0.name == name }) {
                tab.cursorID = target.id
            } else if tab.cursorID == nil || !items.contains(where: { $0.id == tab.cursorID }) {
                tab.cursorID = sorted.first?.id
            }
        case .failure(let error):
            tab.files = []
            statusMessage = "로드 실패: \(error.localizedDescription)"
        }
    }

    func loadSFTPTab(_ tab: TabInfo, client: SFTPClient) async {
        tab.isLoading = true
        let path = tab.url.path
        let result: Result<[SFTPEntry], Error> = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let r = Result { try client.list(path: path.isEmpty ? "/" : path) }
                cont.resume(returning: r)
            }
        }
        tab.isLoading = false
        switch result {
        case .success(let entries):
            tab.files = entries.map { entry in
                let entryURL = sftpItemURL(client: client, path: entry.path)
                return FileItem(
                    url:              entryURL,
                    name:             entry.name,
                    size:             entry.size,
                    modificationDate: entry.modifiedDate ?? Date(),
                    isDirectory:      entry.isDirectory,
                    isHidden:         entry.name.hasPrefix("."),
                    isSymlink:        entry.isSymlink
                )
            }
            if tab.cursorID == nil || !tab.files.contains(where: { $0.id == tab.cursorID }) {
                tab.cursorID = tab.displayFiles(showHidden: pane(containing: tab).showHidden).first?.id
            }
        case .failure(let error):
            tab.files = []
            statusMessage = "SFTP 오류: \(error.localizedDescription)"
        }
    }

    func reload(pane: PaneState) async {
        guard let tab = pane.activeTab else { return }
        await loadTab(tab)
    }

    func navigate(tab: TabInfo, to url: URL, selectingName: String? = nil) {
        if url != tab.url {
            tab.historyBack.append(tab.url)
            tab.historyForward.removeAll()
        }
        tab.url = url
        tab.selectedIDs = []
        if url.scheme != "sftp" {
            UserDefaults.standard.set(url.path, forKey: "lastOpenedPath")
        }
        Task { await loadTab(tab, selectingName: selectingName) }
    }

    func navigateBack(tab: TabInfo) {
        guard let prev = tab.historyBack.popLast() else { return }
        tab.historyForward.append(tab.url)
        tab.url = prev
        tab.selectedIDs = []
        Task { await loadTab(tab) }
    }

    func navigateForward(tab: TabInfo) {
        guard let next = tab.historyForward.popLast() else { return }
        tab.historyBack.append(tab.url)
        tab.url = next
        tab.selectedIDs = []
        Task { await loadTab(tab) }
    }

    // MARK: - 파일 작업 (로컬/SFTP 분기)

    func copySelectionToOpposite(from srcPane: PaneState? = nil) {
        let src = srcPane ?? activePane
        let dst = src === leftPane ? rightPane : leftPane
        guard let srcTab = src.activeTab,
              let dstTab = dst.activeTab else { return }
        let items = srcTab.effectiveSelections
        guard !items.isEmpty else { return }
        performTransfer(items: items, srcTab: srcTab, dstTab: dstTab, move: false)
    }

    func moveSelectionToOpposite(from srcPane: PaneState? = nil) {
        let src = srcPane ?? activePane
        let dst = src === leftPane ? rightPane : leftPane
        guard let srcTab = src.activeTab,
              let dstTab = dst.activeTab else { return }
        let items = srcTab.effectiveSelections
        guard !items.isEmpty else { return }
        performTransfer(items: items, srcTab: srcTab, dstTab: dstTab, move: true)
    }

    // MARK: - 충돌 resolver 생성

    // 연속 작업 중 "모두 XXX" 선택을 기억하는 값을 공유하기 위한 참조 타입
    private final class ConflictState: @unchecked Sendable {
        var remembered: OverwriteAction? = nil
    }

    private func makeConflictResolver(state: ConflictState) -> FileOperationManager.ConflictResolver {
        { [weak self] srcURL, dstURL in
            guard let self else { return .skip }

            // 이미 기억된 "모두" 선택 적용
            if let remembered = state.remembered {
                switch remembered {
                case .skipAll:      return .skip
                case .renameAll:    return .rename
                case .overwriteAll: return .overwrite
                default: break
                }
            }

            // 환경설정: rename이면 자동 이름 변경
            let policy = UserDefaults.standard.string(forKey: "overwritePolicy") ?? "rename"
            if policy == "rename" { return .rename }

            // confirm: 다이얼로그 표시 후 대기
            let action = await withCheckedContinuation { (cont: CheckedContinuation<OverwriteAction, Never>) in
                Task { @MainActor [weak self] in
                    guard let self else { cont.resume(returning: .skip); return }
                    self.overwriteConflict = OverwriteConflict(srcURL: srcURL, dstURL: dstURL, continuation: cont)
                }
            }

            // "모두" 액션 기억
            switch action {
            case .skipAll, .renameAll, .overwriteAll: state.remembered = action
            default: break
            }
            return action
        }
    }

    private func resetWorkState(message: String) {
        isWorking = true; workCancelled = false
        workProgress = 0; workMessage = message
        workCurrentFile = ""; workSourcePath = ""; workDestPath = ""
        workBytes = 0; workFileCount = 0; workTotalCount = 0
    }

    private func updateWorkItem(_ item: FileItem, index: Int, total: Int,
                                srcPath: String, dstPath: String) {
        workCurrentFile = item.name
        workSourcePath  = srcPath
        workDestPath    = dstPath
        workFileCount   = index + 1
        workBytes      += item.size
        workProgress    = Double(index + 1) / Double(total)
    }

    // 로컬 파일을 재귀적으로 수집 (업로드용)
    // 결과: [(localURL, remotePath, isDir, size)]
    private func collectLocalForUpload(url: URL, remote: String,
                                       into list: inout [(URL, String, Bool, Int64)]) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            list.append((url, remote, true, 0))
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            for child in children {
                collectLocalForUpload(url: child,
                                      remote: remote + "/" + child.lastPathComponent,
                                      into: &list)
            }
        } else {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                .map { Int64($0) } ?? 0
            list.append((url, remote, false, size))
        }
    }

    // SFTP 경로를 재귀적으로 수집 (다운로드용)
    // 결과: [(remotePath, localURL, isDir, size)]
    nonisolated private func collectSFTPForDownload(client: SFTPClient, remotePath: String,
                                        localURL: URL, isDir: Bool, size: Int64,
                                        into list: inout [(String, URL, Bool, Int64)]) throws {
        list.append((remotePath, localURL, isDir, size))
        if isDir {
            let children = try client.list(path: remotePath)
            for child in children {
                try collectSFTPForDownload(client: client,
                                           remotePath: child.path,
                                           localURL: localURL.appendingPathComponent(child.name),
                                           isDir: child.isDirectory,
                                           size: child.size,
                                           into: &list)
            }
        }
    }

    private func updateSFTPProgress(name: String, src: String, dst: String,
                                    size: Int64, fileCount: inout Int, total: Int) {
        workCurrentFile = name
        workSourcePath  = src
        workDestPath    = dst
        workBytes      += size
        fileCount      += 1
        workFileCount   = fileCount
        workProgress    = total > 0 ? Double(fileCount) / Double(total) : 0
    }

    func cancelWork() {
        workCancelled = true
        Task { await currentOperationMgr?.cancel() }
    }

    private func performTransfer(items: [FileItem], srcTab: TabInfo, dstTab: TabInfo, move: Bool) {
        Task {
            resetWorkState(message: move ? "이동 중..." : "복사 중...")
            defer {
                isWorking = false; workProgress = 0; workMessage = ""
                workCurrentFile = ""; workSourcePath = ""; workDestPath = ""
                currentOperationMgr = nil
            }

            do {
                let srcIsSFTP = srcTab.sftpClient != nil
                let dstIsSFTP = dstTab.sftpClient != nil

                if !srcIsSFTP && !dstIsSFTP {
                    // 로컬 → 로컬
                    let mgr = FileOperationManager()
                    currentOperationMgr = mgr
                    let resolver = makeConflictResolver(state: ConflictState())
                    try await mgr.perform(
                        op: move ? .move : .copy,
                        items: items.map { $0.url },
                        destination: dstTab.url,
                        conflictResolver: resolver,
                        onTotal: { [weak self] t in self?.workTotalCount = t },
                        onFile: { [weak self] name, src, dst, size in
                            self?.workCurrentFile = name
                            self?.workSourcePath  = src
                            self?.workDestPath    = dst
                            self?.workBytes      += size
                            self?.workFileCount  += 1
                        },
                        progress: { [weak self] p in self?.workProgress = p }
                    )
                } else if !srcIsSFTP, let dstClient = dstTab.sftpClient {
                    // 로컬 → SFTP (업로드): 파일 단위 재귀 전송
                    let dstPath = dstTab.url.path
                    var uploadTasks: [(URL, String, Bool, Int64)] = []
                    for item in items {
                        collectLocalForUpload(url: item.url,
                                              remote: remotePath(dstPath, name: item.name),
                                              into: &uploadTasks)
                    }
                    let fileTotal = uploadTasks.filter { !$0.2 }.count
                    workTotalCount = fileTotal
                    var fileCount = 0
                    for (localURL, remPath, isDir, size) in uploadTasks {
                        guard !workCancelled else { break }
                        if isDir {
                            let rp = remPath
                            await Task.detached { dstClient.mkdir(remotePath: rp) }.value
                        } else {
                            updateSFTPProgress(name: localURL.lastPathComponent,
                                               src: localURL.path, dst: remPath,
                                               size: size, fileCount: &fileCount, total: fileTotal)
                            let local = localURL, remote = remPath
                            try await Task.detached { try dstClient.upload(localURL: local, remotePath: remote) }.value
                            if move { try? FileManager.default.removeItem(at: localURL) }
                        }
                    }
                    if move { for item in items { try? FileManager.default.removeItem(at: item.url) } }

                } else if let srcClient = srcTab.sftpClient, !dstIsSFTP {
                    // SFTP → 로컬 (다운로드): 파일 단위 재귀 전송
                    let dstBase = dstTab.url
                    workSourcePath = srcTab.url.path
                    workDestPath   = dstBase.path
                    var downloadTasks: [(String, URL, Bool, Int64)] = []
                    for item in items {
                        let localDst = dstBase.appendingPathComponent(item.name)
                        let c = srcClient
                        try await Task.detached {
                            try self.collectSFTPForDownload(client: c,
                                                            remotePath: item.url.path,
                                                            localURL: localDst,
                                                            isDir: item.isDirectory,
                                                            size: item.size,
                                                            into: &downloadTasks)
                        }.value
                    }
                    let fileTotal = downloadTasks.filter { !$0.2 }.count
                    workTotalCount = fileTotal
                    var fileCount = 0
                    for (remPath, localURL, isDir, size) in downloadTasks {
                        guard !workCancelled else { break }
                        if isDir {
                            try? FileManager.default.createDirectory(at: localURL,
                                                                     withIntermediateDirectories: true)
                        } else {
                            updateSFTPProgress(name: localURL.lastPathComponent,
                                               src: remPath, dst: localURL.path,
                                               size: size, fileCount: &fileCount, total: fileTotal)
                            let rp = remPath, local = localURL
                            try await Task.detached { try srcClient.download(remotePath: rp, localURL: local) }.value
                            if move {
                                try await Task.detached { try srcClient.deleteItem(path: rp, isDirectory: false) }.value
                            }
                        }
                    }
                } else if let srcClient = srcTab.sftpClient,
                          let dstClient = dstTab.sftpClient {
                    let dstPath = dstTab.url.path
                    workSourcePath = srcTab.url.path
                    workDestPath   = dstPath
                    if srcClient === dstClient {
                        // SFTP → SFTP (같은 서버)
                        workTotalCount = items.count
                        for (i, item) in items.enumerated() {
                            guard !workCancelled else { break }
                            let from = item.url.path
                            let to   = remotePath(dstPath, name: item.name)
                            updateWorkItem(item, index: i, total: items.count,
                                           srcPath: from, dstPath: to)
                            if move {
                                try await Task.detached { try srcClient.rename(from: from, to: to) }.value
                            } else {
                                try await Task.detached { try srcClient.copyRemote(from: from, to: to) }.value
                            }
                        }
                    } else {
                        // SFTP → SFTP (다른 서버: 로컬 임시 경유)
                        workTotalCount = items.count
                        let tmp = FileManager.default.temporaryDirectory
                        for (i, item) in items.enumerated() {
                            guard !workCancelled else { break }
                            let rp = item.url.path
                            let localTmp = tmp.appendingPathComponent(item.name)
                            updateWorkItem(item, index: i, total: items.count,
                                           srcPath: rp, dstPath: remotePath(dstPath, name: item.name))
                            try await Task.detached {
                                try srcClient.download(remotePath: rp, localURL: localTmp)
                            }.value
                            let remDst = remotePath(dstPath, name: item.name)
                            try await Task.detached {
                                try dstClient.upload(localURL: localTmp, remotePath: remDst)
                            }.value
                            try? FileManager.default.removeItem(at: localTmp)
                            if move {
                                let isDir = item.isDirectory
                                try await Task.detached {
                                    try srcClient.deleteItem(path: rp, isDirectory: isDir)
                                }.value
                            }
                        }
                    }
                }

                await reload(pane: oppositePane)
                if move { await reload(pane: activePane) }
                srcTab.selectedIDs = []
                statusMessage = move ? "이동 완료" : "복사 완료"
            } catch {
                // 취소 또는 오류 시에도 대상 위치 새로고침
                await reload(pane: oppositePane)
                if move { await reload(pane: activePane) }
                srcTab.selectedIDs = []
                if workCancelled {
                    statusMessage = "취소됨"
                } else {
                    statusMessage = "오류: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - 클립보드 (Cmd+C/X/V)

    func setClipboard(urls: [URL], op: ClipboardOp) {
        clipboard = urls
        clipboardOp = op
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        lastPasteboardChangeCount = pb.changeCount
    }

    // Finder에서 복사한 파일도 붙여넣기 가능 (시스템 클립보드 변경 감지)
    func pasteFromClipboard() async {
        let pb = NSPasteboard.general
        if pb.changeCount != lastPasteboardChangeCount,
           let objs = pb.readObjects(forClasses: [NSURL.self]) as? [URL] {
            let fileURLs = objs.filter { $0.isFileURL }
            if !fileURLs.isEmpty {
                clipboard = fileURLs
                clipboardOp = .copy
                lastPasteboardChangeCount = pb.changeCount
            }
        }
        await performPaste()
    }

    func performPaste(destinationURL: URL? = nil, targetPane: PaneState? = nil) async {
        guard !clipboard.isEmpty else { return }
        let destPane = targetPane ?? activePane
        guard let dstTab = destPane.activeTab else { return }
        let dst = destinationURL ?? dstTab.url
        let op = clipboardOp
        resetWorkState(message: op == .copy ? "복사 중..." : "이동 중...")
        defer {
            isWorking = false; workProgress = 0; workMessage = ""
            workCurrentFile = ""; workSourcePath = ""; workDestPath = ""
            currentOperationMgr = nil
        }
        let items = clipboard
        do {
            let mgr = FileOperationManager()
            currentOperationMgr = mgr
            let resolver = makeConflictResolver(state: ConflictState())
            try await mgr.perform(
                op: op, items: items, destination: dst,
                conflictResolver: resolver,
                onTotal: { [weak self] t in self?.workTotalCount = t },
                onFile: { [weak self] name, src, dstPath, size in
                    self?.workCurrentFile = name
                    self?.workSourcePath  = src
                    self?.workDestPath    = dstPath
                    self?.workBytes      += size
                    self?.workFileCount  += 1
                },
                progress: { [weak self] p in self?.workProgress = p }
            )
            await reload(pane: destPane)
            if op == .move { clipboard = []; await reload(pane: activePane) }
            dstTab.selectedIDs = []
            activePane.activeTab?.selectedIDs = []
            statusMessage = op == .copy ? "복사 완료" : "이동 완료"
        } catch {
            // 취소 또는 오류 시에도 대상 위치 새로고침
            await reload(pane: destPane)
            if op == .move { await reload(pane: activePane) }
            dstTab.selectedIDs = []
            activePane.activeTab?.selectedIDs = []
            statusMessage = workCancelled ? "취소됨" : "오류: \(error.localizedDescription)"
        }
    }

    // 삭제 요청 — 환경설정에 따라 확인 다이얼로그 또는 즉시 삭제
    func deleteSelection(in srcPane: PaneState? = nil) {
        let pane = srcPane ?? activePane
        guard let tab = pane.activeTab else { return }
        let items = tab.effectiveSelections
        guard !items.isEmpty else { return }
        deleteTargets = items
        if UserDefaults.standard.object(forKey: "confirmBeforeDelete") == nil
            || UserDefaults.standard.bool(forKey: "confirmBeforeDelete") {
            showDeleteConfirm = true
        } else {
            confirmDelete()
        }
    }

    // 확인 후 실제 삭제 실행
    func confirmDelete() {
        let items = deleteTargets
        deleteTargets = []
        guard !items.isEmpty,
              let tab = activePane.activeTab else { return }

        if let client = tab.sftpClient {
            Task {
                resetWorkState(message: "삭제 중...")
                workTotalCount = items.count
                defer {
                    isWorking = false; workProgress = 0; workMessage = ""
                    workCurrentFile = ""; workSourcePath = ""
                }
                do {
                    workSourcePath = tab.url.path
                    for (i, item) in items.enumerated() {
                        guard !workCancelled else { break }
                        workCurrentFile = item.name
                        workFileCount   = i + 1
                        workBytes      += item.size
                        workProgress    = Double(i + 1) / Double(items.count)
                        let rp = item.url.path; let isDir = item.isDirectory
                        try await Task.detached {
                            try client.deleteItem(path: rp, isDirectory: isDir)
                        }.value
                    }
                    await reload(pane: activePane)
                    tab.selectedIDs = []
                    statusMessage = workCancelled ? "취소됨" : "삭제 완료"
                } catch {
                    await reload(pane: activePane)
                    tab.selectedIDs = []
                    statusMessage = "오류: \(error.localizedDescription)"
                }
            }
            return
        }

        Task {
            resetWorkState(message: "삭제 중...")
            workTotalCount = items.count
            defer {
                isWorking = false; workProgress = 0; workMessage = ""
                workCurrentFile = ""; workSourcePath = ""
                currentOperationMgr = nil
            }
            do {
                let mgr = FileOperationManager()
                currentOperationMgr = mgr
                workSourcePath = activePane.activeTab?.url.path ?? ""
                try await mgr.deleteItems(
                    items: items,
                    onFile: { [weak self] name, src, size in
                        self?.workCurrentFile = name
                        self?.workSourcePath  = src
                        self?.workBytes      += size
                        self?.workFileCount  += 1
                    },
                    progress: { [weak self] p in self?.workProgress = p }
                )
                await reload(pane: activePane)
                activePane.activeTab?.selectedIDs = []
                statusMessage = workCancelled ? "취소됨" : "삭제 완료"
            } catch {
                await reload(pane: activePane)
                activePane.activeTab?.selectedIDs = []
                statusMessage = "오류: \(error.localizedDescription)"
            }
        }
    }

    func createFile() {
        guard let tab = activePane.activeTab else { return }
        let name = newFileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        if let client = tab.sftpClient {
            let path = remotePath(tab.url.path, name: name)
            Task {
                do {
                    try await Task.detached { try client.createFile(path: path) }.value
                    await reload(pane: activePane)
                    if let created = tab.files.first(where: { $0.name == name }) {
                        tab.cursorID = created.id
                    }
                    statusMessage = "파일 생성: \(name)"
                } catch { statusMessage = "오류: \(error.localizedDescription)" }
            }
            newFileName = ""
            return
        }

        Task {
            do {
                let dst = tab.url.appendingPathComponent(name)
                guard !FileManager.default.fileExists(atPath: dst.path) else {
                    statusMessage = "이미 존재하는 파일: \(name)"; return
                }
                FileManager.default.createFile(atPath: dst.path, contents: nil)
                await reload(pane: activePane)
                if let created = tab.files.first(where: { $0.name == name }) {
                    tab.cursorID = created.id
                }
                statusMessage = "파일 생성: \(name)"
            } catch { statusMessage = "오류: \(error.localizedDescription)" }
        }
        newFileName = ""
    }

    func createFolder() {
        guard let tab = activePane.activeTab else { return }
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        if let client = tab.sftpClient {
            let path = remotePath(tab.url.path, name: name)
            Task {
                do {
                    try await Task.detached { try client.mkdir(path: path) }.value
                    await reload(pane: activePane)
                    statusMessage = "폴더 생성: \(name)"
                } catch { statusMessage = "오류: \(error.localizedDescription)" }
            }
            newFolderName = ""
            return
        }

        Task {
            do {
                let dst = tab.url.appendingPathComponent(name)
                try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
                await reload(pane: activePane)
                statusMessage = "폴더 생성: \(name)"
            } catch { statusMessage = "오류: \(error.localizedDescription)" }
        }
        newFolderName = ""
    }

    func renameActive() {
        guard let tab = activePane.activeTab,
              let item = tab.cursorFile else { return }
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != item.name else { return }

        if let client = tab.sftpClient {
            let from = item.url.path
            let to   = remotePath(
                (item.url.path as NSString).deletingLastPathComponent,
                name: newName
            )
            Task {
                do {
                    try await Task.detached { try client.rename(from: from, to: to) }.value
                    await reload(pane: activePane)
                    statusMessage = "이름 변경: \(newName)"
                } catch { statusMessage = "오류: \(error.localizedDescription)" }
            }
            return
        }

        Task {
            do {
                let dst = item.url.deletingLastPathComponent().appendingPathComponent(newName)
                try FileManager.default.moveItem(at: item.url, to: dst)
                await reload(pane: activePane)
                statusMessage = "이름 변경: \(newName)"
            } catch { statusMessage = "오류: \(error.localizedDescription)" }
        }
    }

    // MARK: - 즐겨찾기

    func addBookmark(url: URL, name: String? = nil) {
        guard !bookmarks.contains(where: { $0.path == url.path }) else { return }
        let bm = Bookmark(name: name ?? url.lastPathComponent, path: url.path)
        bookmarks.append(bm)
        saveBookmarks()
    }

    func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        saveBookmarks()
    }

    func renameBookmark(id: UUID, name: String) {
        if let i = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks[i].name = name
            saveBookmarks()
        }
    }

    private func loadBookmarks() {
        if let data = UserDefaults.standard.data(forKey: "axlfile.bookmarks"),
           let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = decoded
        }
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: "axlfile.bookmarks")
        }
    }

    // MARK: - 커맨드 바

    func executeCommand() {
        let cmd = commandText.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }
        commandHistory.append(cmd)
        commandText = ""
        commandIsRunning = true
        let cwd = activePane.activeTab?.url.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        Task {
            let output = await runShellCommand(cmd, cwd: cwd)
            commandOutput = output
            commandIsRunning = false
            if let tab = activePane.activeTab { await loadTab(tab) }
        }
    }

    private func runShellCommand(_ command: String, cwd: String) async -> String {
        await withCheckedContinuation { cont in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
            let outPipe = Pipe(), errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError  = errPipe
            do {
                try process.run()
                process.terminationHandler = { _ in
                    let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    let combined = (out + err).trimmingCharacters(in: CharacterSet.newlines)
                    cont.resume(returning: combined.isEmpty ? "(출력 없음)" : combined)
                }
            } catch {
                cont.resume(returning: "오류: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Diff

    func openDiff() {
        guard activePane.activeTab?.isSFTP == false,
              oppositePane.activeTab?.isSFTP == false,
              let src = activePane.activeTab?.cursorFile,
              !src.isDirectory, !src.isParentDir,
              let dst = oppositePane.activeTab?.files.first(where: { $0.name == src.name }) else {
            statusMessage = "반대 패널에 동일한 이름의 파일이 없습니다"
            return
        }
        diffLeftURL  = activePaneID == .left ? src.url : dst.url
        diffRightURL = activePaneID == .left ? dst.url : src.url
        showDiff = true
    }

    // MARK: - 압축

    func extractCursorFile() {
        guard let tab = activePane.activeTab, !tab.isSFTP,
              let item = tab.cursorFile,
              !item.isParentDir, !item.isDirectory,
              isArchiveFile(item.url) else {
            statusMessage = "압축 파일을 선택하세요"
            return
        }
        let dstName = item.url.deletingPathExtension().lastPathComponent
        let dst = tab.url.appendingPathComponent(dstName)
        Task {
            resetWorkState(message: "압축 해제 중...")
            defer { isWorking = false; workProgress = 0; workMessage = "" }
            do {
                workCurrentFile = item.name
                workProgress = 0.1
                try await extractArchive(at: item.url, to: dst)
                await reload(pane: activePane)
                statusMessage = "압축 해제 완료: \(dstName)"
            } catch {
                await reload(pane: activePane)
                statusMessage = "압축 해제 실패: \(error.localizedDescription)"
            }
        }
    }

    func packSelection() {
        guard let tab = activePane.activeTab else { return }
        let items = tab.effectiveSelections.filter { !$0.isParentDir }
        guard !items.isEmpty, !tab.isSFTP else {
            statusMessage = "로컬 파일을 선택하세요"
            return
        }
        let defaultName = items.count == 1 ? items[0].name + ".zip" : "archive.zip"
        zipNameText = defaultName
        showZipName = true
    }

    func confirmPackSelection() {
        guard let tab = activePane.activeTab else { return }
        let items = tab.effectiveSelections.filter { !$0.isParentDir }
        guard !items.isEmpty else { return }
        let name = zipNameText.hasSuffix(".zip") ? zipNameText : zipNameText + ".zip"
        let dst = tab.url.appendingPathComponent(name)
        let urls = items.map { $0.url }
        Task {
            resetWorkState(message: "압축 중...")
            defer { isWorking = false; workProgress = 0; workMessage = "" }
            do {
                workCurrentFile = name
                workProgress = 0.1
                try await createZip(from: urls, to: dst)
                await reload(pane: activePane)
                statusMessage = "압축 완료: \(name)"
            } catch {
                await reload(pane: activePane)
                statusMessage = "압축 실패: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - SFTP URL 헬퍼

    func sftpURL(client: SFTPClient, path: String) -> URL {
        var c = URLComponents()
        c.scheme = "sftp"
        c.user   = client.username
        c.host   = client.host
        if client.port != 22 { c.port = client.port }
        c.path   = path.hasPrefix("/") ? path : "/\(path)"
        return c.url ?? URL(fileURLWithPath: path)
    }

    private func sftpItemURL(client: SFTPClient, path: String) -> URL {
        sftpURL(client: client, path: path)
    }

    private func remotePath(_ base: String, name: String) -> String {
        let b = base.isEmpty ? "/" : base
        return b == "/" ? "/\(name)" : "\(b)/\(name)"
    }
}
