import SwiftUI
import AppKit

// MARK: - Settings Window Controller

@MainActor
private final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func open(appState: AppState) {
        if let w = window, w.isVisible { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "환경설정"
        w.contentView = NSHostingView(rootView: SettingsView().environment(appState))
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in self.window = nil }
    }
}

// MARK: - App

@main
struct AxlFileApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .defaultSize(width: 1100, height: 660)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("환경설정...") { SettingsWindowController.shared.open(appState: appState) }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("AxlFile 정보...") {
                    let credits = NSMutableAttributedString(
                        string: "axlrator.co.kr",
                        attributes: [
                            .link: URL(string: "https://axlrator.co.kr")!,
                            .font: NSFont.systemFont(ofSize: 13)
                        ]
                    )
                    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu("파일") {
                Button("새 파일") { appState.newFileName = ""; appState.showNewFile = true }
                    .keyboardShortcut("n", modifiers: .command)
                Button("새 폴더") { appState.showNewFolder = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("파일 복사 (반대 패널)") { appState.copySelectionToOpposite() }
                Button("파일 이동 (반대 패널)") { appState.moveSelectionToOpposite() }
                Button("삭제") { appState.deleteSelection() }
                Divider()
                Button("SFTP 연결...") { appState.showFTP = true }
            }
            CommandMenu("보기") {
                Button("숨김 파일 표시/숨기기") {
                    appState.activePane.showHidden.toggle()
                    Task { await appState.reload(pane: appState.activePane) }
                }
                .keyboardShortcut(".", modifiers: .command)
                Button("새로고침") {
                    Task {
                        await appState.reload(pane: appState.leftPane)
                        await appState.reload(pane: appState.rightPane)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

    }
}
