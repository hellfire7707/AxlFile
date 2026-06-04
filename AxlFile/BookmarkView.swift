import SwiftUI

struct BookmarkView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: UUID? = nil
    @State private var editingName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "bookmark.fill").foregroundStyle(NX.folderText)
                Text("즐겨찾기").font(.headline).foregroundStyle(NX.fileText)
                Spacer()
                Button {
                    if let tab = appState.activePane.activeTab {
                        appState.addBookmark(url: tab.url)
                    }
                } label: {
                    Label("현재 폴더 추가", systemImage: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(NX.infoText)
                .help("현재 폴더를 즐겨찾기에 추가")
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(NX.infoText)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(NX.headerBg)
            .overlay(alignment: .bottom) { Rectangle().frame(height: 1).foregroundStyle(NX.separator) }

            if appState.bookmarks.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bookmark").font(.system(size: 32)).foregroundStyle(NX.attrText)
                    Text("즐겨찾기가 없습니다").font(.system(size: 12)).foregroundStyle(NX.infoText)
                    Text("상단 + 버튼으로 현재 폴더를 추가하세요")
                        .font(.system(size: 11)).foregroundStyle(NX.attrText)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(appState.bookmarks.enumerated()), id: \.element.id) { i, bm in
                            BookmarkRow(
                                bookmark: bm,
                                index: i,
                                isEditing: editingID == bm.id,
                                editingName: $editingName,
                                onNavigate: {
                                    appState.navigate(tab: appState.activePane.activeTab!, to: bm.url)
                                    dismiss()
                                },
                                onEditStart: {
                                    editingID = bm.id
                                    editingName = bm.name
                                },
                                onEditCommit: {
                                    let n = editingName.trimmingCharacters(in: .whitespaces)
                                    if !n.isEmpty {
                                        appState.renameBookmark(id: bm.id, name: n)
                                    }
                                    editingID = nil
                                },
                                onEditCancel: { editingID = nil },
                                onDelete: { appState.removeBookmark(id: bm.id) }
                            )
                        }
                    }
                }
                .background(Color.black)
            }

            // Footer hint
            Rectangle().frame(height: 1).foregroundStyle(NX.separator)
            Text("Cmd+1~9로 빠른 이동  ·  더블클릭으로 이동")
                .font(.system(size: 10))
                .foregroundStyle(NX.attrText)
                .padding(.vertical, 6)
        }
        .frame(width: 380, height: 340)
        .background(NX.bg)
        .preferredColorScheme(.dark)
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark
    let index: Int
    let isEditing: Bool
    @Binding var editingName: String
    let onNavigate: () -> Void
    let onEditStart: () -> Void
    let onEditCommit: () -> Void
    let onEditCancel: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Shortcut number
            Text(index < 9 ? "⌘\(index + 1)" : "   ")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(NX.folderText)
                .frame(width: 28, alignment: .center)
            // Icon
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "#4A9EFF"))
            // Name / Edit
            if isEditing {
                TextField("", text: $editingName)
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                    .foregroundStyle(Color.white)
                    .onSubmit { onEditCommit() }
                    .onKeyPress(.escape) { onEditCancel(); return .handled }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(bookmark.name)
                        .font(.system(size: 11))
                        .foregroundStyle(NX.fileText)
                        .lineLimit(1)
                    Text(bookmark.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(NX.infoText)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer()
            if hovered && !isEditing {
                Button(action: onEditStart) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .foregroundStyle(NX.infoText)
                }
                .buttonStyle(.borderless)
                Button(action: onDelete) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(hovered ? NX.cursor.opacity(0.4) : Color.clear)
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) { onNavigate() }
        .onTapGesture(count: 1) {}
    }
}
