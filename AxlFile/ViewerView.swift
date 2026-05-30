import SwiftUI
import AVKit

struct ViewerView: View {
    var url: URL
    @State private var content: ViewerContent = .loading
    @Environment(\.dismiss) private var dismiss

    enum ViewerContent {
        case loading
        case text(String)
        case image(NSImage)
        case video(URL)
        case unsupported(String)
        case error(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: iconFor(url))
                    .foregroundStyle(.secondary)
                Text(url.lastPathComponent)
                    .font(.headline)
                Spacer()
                Text(url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.escape)
                    .keyboardShortcut("w", modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Content
            Group {
                switch content {
                case .loading:
                    ProgressView("로딩 중...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .text(let str):
                    TextViewerContent(text: str, url: url)

                case .image(let img):
                    ImageViewerContent(image: img)

                case .video(let videoURL):
                    VideoPlayer(player: AVPlayer(url: videoURL))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .unsupported(let ext):
                    VStack(spacing: 12) {
                        Image(systemName: "doc.questionmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(".\(ext) 파일은 미리볼 수 없습니다")
                            .foregroundStyle(.secondary)
                        Button("기본 앱으로 열기") {
                            NSWorkspace.shared.open(url)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .error(let msg):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.red)
                        Text(msg).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 500)
        .task { await loadContent() }
    }

    private func loadContent() async {
        let ext = url.pathExtension.lowercased()
        let item = FileItem(url: url, name: url.lastPathComponent, size: 0,
                            modificationDate: Date(), isDirectory: false,
                            isHidden: false, isSymlink: false)
        if item.isImageFile {
            if let img = NSImage(contentsOf: url) {
                content = .image(img)
            } else {
                content = .error("이미지를 불러올 수 없습니다")
            }
        } else if item.isVideoFile {
            content = .video(url)
        } else if item.isTextFile {
            do {
                // 최대 4MB만 읽기
                let data = try Data(contentsOf: url)
                let limited = data.count > 4_000_000 ? data.prefix(4_000_000) : data
                let str = String(data: limited, encoding: .utf8)
                    ?? String(data: limited, encoding: .isoLatin1)
                    ?? "인코딩을 감지할 수 없습니다"
                let suffix = data.count > 4_000_000 ? "\n\n... (파일이 너무 커서 일부만 표시됩니다)" : ""
                content = .text(str + suffix)
            } catch {
                content = .error(error.localizedDescription)
            }
        } else {
            content = .unsupported(ext)
        }
    }

    private func iconFor(_ url: URL) -> String {
        let item = FileItem(url: url, name: url.lastPathComponent, size: 0,
                            modificationDate: Date(), isDirectory: false,
                            isHidden: false, isSymlink: false)
        return item.sfSymbol
    }
}

// MARK: - Text Viewer

struct TextViewerContent: View {
    var text: String
    var url: URL
    @State private var searchText = ""
    @State private var fontSize: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("검색...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 200)
                Divider().frame(height: 16)
                Stepper("글자 크기: \(Int(fontSize))", value: $fontSize, in: 8...24)
                    .labelsHidden()
                Text("크기: \(Int(fontSize))pt").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    let content = text
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.plainText]
                    if panel.runModal() == .OK, let url = panel.url {
                        try? content.write(to: url, atomically: true, encoding: .utf8)
                    }
                } label: {
                    Image(systemName: "arrow.down.doc")
                }
                .buttonStyle(.borderless)
                .help("저장")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content
            ScrollView([.horizontal, .vertical]) {
                Text(displayText)
                    .font(.system(size: fontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var displayText: String {
        guard !searchText.isEmpty else { return text }
        return text  // 검색 하이라이팅은 TextKit 없이는 복잡하므로 단순 표시
    }
}

// MARK: - Image Viewer

struct ImageViewerContent: View {
    var image: NSImage
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var magnification: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack {
                Text("\(image.size.width.formatted())×\(image.size.height.formatted()) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { scale = max(0.1, scale / 1.25) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Text("\(Int(scale * 100))%").font(.caption).frame(width: 44)
                Button { scale = min(8, scale * 1.25) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Button { scale = 1; offset = .zero } label: {
                    Image(systemName: "1.magnifyingglass")
                }
                .buttonStyle(.borderless)
                Button {
                    // fit to window
                    scale = 1
                    offset = .zero
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Image
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: image.size.width * scale,
                            height: image.size.height * scale
                        )
                        .offset(offset)
                        .gesture(
                            MagnifyGesture()
                                .updating($magnification) { val, state, _ in state = val.magnification }
                                .onEnded { val in scale = max(0.1, min(8, scale * val.magnification)) }
                        )
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }
}
