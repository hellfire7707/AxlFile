import SwiftUI
import AppKit

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
                    appState.showHidden.toggle()
                    Task {
                        await appState.reload(pane: appState.leftPane)
                        await appState.reload(pane: appState.rightPane)
                    }
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

        Settings {
            SettingsView()
        }
    }
}
