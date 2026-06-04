import SwiftUI

struct CommandBarView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var focused: Bool
    @State private var historyIndex = -1
    @State private var savedInput = ""

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().frame(height: 1).foregroundStyle(NX.separator)
            // Output panel
            if !appState.commandOutput.isEmpty {
                ScrollView {
                    Text(appState.commandOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(NX.fileText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 140)
                .background(Color.black)
                Rectangle().frame(height: 1).foregroundStyle(NX.separator)
            }
            // Input row
            HStack(spacing: 6) {
                Text("$").font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(NX.folderText)
                Text("[\(cwdLabel)]")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(hex: "#4A9EFF"))
                    .lineLimit(1)
                    .truncationMode(.head)
                TextField("명령어 입력...", text: Binding(
                    get: { appState.commandText },
                    set: { appState.commandText = $0 }
                ))
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.plain)
                .foregroundStyle(Color.white)
                .focused($focused)
                .onSubmit {
                    appState.executeCommand()
                    historyIndex = -1
                }
                .onKeyPress(.escape) {
                    appState.showCommandBar = false
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    navigateHistory(up: true)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    navigateHistory(up: false)
                    return .handled
                }
                if appState.commandIsRunning {
                    ProgressView().controlSize(.small).frame(width: 16, height: 16)
                } else {
                    Button { appState.commandOutput = "" } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(NX.infoText)
                    }
                    .buttonStyle(.borderless)
                    .help("출력 지우기")
                    .opacity(appState.commandOutput.isEmpty ? 0 : 1)
                }
                Button { appState.showCommandBar = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(NX.infoText)
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(hex: "#0E0E0E"))
        }
        .onChange(of: appState.showCommandBar) { _, show in
            if show {
                historyIndex = -1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
            }
        }
    }

    private var cwdLabel: String {
        let path = appState.activePane.activeTab?.url.path ?? ""
        return path.isEmpty ? "~" : URL(fileURLWithPath: path).lastPathComponent
    }

    private func navigateHistory(up: Bool) {
        let hist = appState.commandHistory
        guard !hist.isEmpty else { return }
        if up {
            if historyIndex == -1 {
                savedInput = appState.commandText
                historyIndex = hist.count - 1
            } else if historyIndex > 0 {
                historyIndex -= 1
            }
            appState.commandText = hist[historyIndex]
        } else {
            if historyIndex == hist.count - 1 {
                historyIndex = -1
                appState.commandText = savedInput
            } else if historyIndex >= 0 {
                historyIndex += 1
                appState.commandText = hist[historyIndex]
            }
        }
    }
}
