import SwiftUI

struct DualPaneView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var focusedPane: PaneID?
    @State private var splitRatio: CGFloat = 0.5

    private let dividerW: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                PaneView(pane: appState.leftPane, paneID: .left, focusedPane: $focusedPane)
                    .environment(appState)
                    .frame(width: max(160, (geo.size.width - dividerW) * splitRatio))

                MiddleDivider(splitRatio: $splitRatio, totalWidth: geo.size.width, dividerW: dividerW)
                    .environment(appState)

                PaneView(pane: appState.rightPane, paneID: .right, focusedPane: $focusedPane)
                    .environment(appState)
                    .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: focusedPane) { _, newVal in
            if let val = newVal { appState.activePaneID = val }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            focusedPane = .left
        }
    }
}

// MARK: - Middle Divider

struct MiddleDivider: View {
    @Environment(AppState.self) private var appState
    @Binding var splitRatio: CGFloat
    var totalWidth: CGFloat
    var dividerW: CGFloat

    @State private var baseRatio: CGFloat = 0.5
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 2) {
            Spacer()
            divBtn("arrow.right",           help: "→ 복사") { appState.copySelectionToOpposite() }
            divBtn("arrow.left.arrow.right", help: "↔ 이동") { appState.moveSelectionToOpposite() }
            Spacer()
        }
        .frame(width: dividerW)
        .background(isHovered ? NX.cursor.opacity(0.4) : NX.dividerBg)
        .overlay(alignment: .leading)  { Rectangle().frame(width: 1).foregroundStyle(NX.separator) }
        .overlay(alignment: .trailing) { Rectangle().frame(width: 1).foregroundStyle(NX.separator) }
        .onHover { h in
            isHovered = h
            if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { v in
                    let usable = totalWidth - dividerW
                    splitRatio = min(0.80, max(0.20, baseRatio + v.translation.width / usable))
                }
                .onEnded { v in
                    let usable = totalWidth - dividerW
                    baseRatio  = min(0.80, max(0.20, baseRatio + v.translation.width / usable))
                    splitRatio = baseRatio
                }
        )
        .onAppear { baseRatio = splitRatio }
    }

    @ViewBuilder
    private func divBtn(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: dividerW, height: 20)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
