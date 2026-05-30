import SwiftUI

// MARK: - FTP Connect Dialog

struct FTPConnectView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var host = ""
    @State private var port = "21"
    @State private var username = "anonymous"
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var ftpClient: FTPClient?
    @State private var showBrowser = false

    // Saved connections
    @State private var savedConnections = FTPConnectView.loadSavedConnections()

    var body: some View {
        if showBrowser, let client = ftpClient {
            FTPBrowserView(client: client, appState: appState)
                .frame(minWidth: 800, minHeight: 520)
        } else {
            connectForm
        }
    }

    private var connectForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            HStack {
                Image(systemName: "network")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("FTP 연결")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("닫기") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            HStack(alignment: .top, spacing: 0) {
                // Saved connections sidebar
                VStack(alignment: .leading, spacing: 6) {
                    Text("저장된 연결")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)

                    if savedConnections.isEmpty {
                        Text("없음")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                    } else {
                        ForEach(savedConnections) { conn in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conn.label).font(.system(size: 12))
                                    Text("\(conn.host):\(conn.port)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    var updated = savedConnections
                                    updated.removeAll { $0.id == conn.id }
                                    savedConnections = updated
                                    FTPConnectView.savConnections(updated)
                                } label: {
                                    Image(systemName: "xmark").font(.caption)
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                host = conn.host
                                port = String(conn.port)
                                username = conn.username
                            }
                        }
                    }
                    Spacer()
                }
                .frame(width: 180)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Connection form
                VStack(alignment: .leading, spacing: 14) {
                    Group {
                        LabeledField("호스트") {
                            TextField("ftp.example.com", text: $host)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("포트") {
                            TextField("21", text: $port)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        LabeledField("사용자명") {
                            TextField("anonymous", text: $username)
                                .textFieldStyle(.roundedBorder)
                        }
                        LabeledField("비밀번호") {
                            SecureField("비밀번호", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    if let err = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                            Text(err)
                        }
                        .foregroundStyle(.red)
                        .font(.callout)
                    }

                    HStack {
                        Button("저장") { saveCurrentConnection() }
                            .buttonStyle(.bordered)
                            .disabled(host.isEmpty)

                        Spacer()

                        Button("연결") {
                            Task { await connect() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(host.isEmpty || isConnecting)
                        .keyboardShortcut(.return)

                        if isConnecting {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 480)
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil
        let client = FTPClient()
        let portNum = Int(port) ?? 21
        let h = host; let u = username; let p = password
        do {
            try await Task.detached {
                try client.connect(host: h, port: portNum, username: u, password: p)
            }.value
            ftpClient = client
            showBrowser = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isConnecting = false
    }

    private func saveCurrentConnection() {
        let conn = SavedFTPConnection(
            label: host,
            host: host,
            port: Int(port) ?? 21,
            username: username
        )
        var conns = savedConnections
        conns.append(conn)
        savedConnections = conns
        FTPConnectView.savConnections(conns)
    }

    static func loadSavedConnections() -> [SavedFTPConnection] {
        guard let data = UserDefaults.standard.data(forKey: "ftpConnections"),
              let decoded = try? JSONDecoder().decode([SavedFTPConnection].self, from: data)
        else { return [] }
        return decoded
    }

    static func savConnections(_ conns: [SavedFTPConnection]) {
        if let data = try? JSONEncoder().encode(conns) {
            UserDefaults.standard.set(data, forKey: "ftpConnections")
        }
    }
}

struct SavedFTPConnection: Identifiable, Codable {
    var id = UUID()
    var label: String
    var host: String
    var port: Int
    var username: String
}

struct LabeledField<Content: View>: View {
    let label: String
    let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label; self.content = content()
    }
    var body: some View {
        HStack {
            Text(label).frame(width: 72, alignment: .trailing)
                .foregroundStyle(.secondary)
            content
        }
    }
}

// MARK: - FTP Browser

struct FTPBrowserView: View {
    var client: FTPClient
    var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [FTPEntry] = []
    @State private var currentPath = "/"
    @State private var isLoading = false
    @State private var selectedID: UUID?
    @State private var errorMessage: String?
    @State private var showNewFolder = false
    @State private var newFolderName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "network").foregroundStyle(.blue)
                Text(client.host).bold()
                Text(currentPath)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button("닫기") { client.disconnect(); dismiss() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            // Toolbar
            HStack(spacing: 6) {
                Button { goUp() } label: {
                    Label("위로", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(currentPath == "/")

                Button { Task { await reload() } } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Divider().frame(height: 16)

                Button {
                    guard let sel = selectedEntry else { return }
                    downloadSelected(sel)
                } label: {
                    Label("다운로드", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .disabled(selectedEntry == nil || selectedEntry?.isDirectory == true)

                Button {
                    uploadToRemote()
                } label: {
                    Label("업로드", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.borderless)

                Divider().frame(height: 16)

                Button {
                    newFolderName = ""
                    showNewFolder = true
                } label: {
                    Label("새 폴더", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)

                Button {
                    guard let sel = selectedEntry else { return }
                    Task { try? await Task.detached { try self.client.delete(path: sel.name, isDirectory: sel.isDirectory) }.value
                        await reload() }
                } label: {
                    Label("삭제", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(selectedEntry == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            Divider()

            if let err = errorMessage {
                Text(err).foregroundStyle(.red).padding(8)
            }

            // File List
            List(entries, selection: $selectedID) { entry in
                HStack(spacing: 8) {
                    Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                        .foregroundStyle(entry.isDirectory ? .blue : .secondary)
                        .frame(width: 20)
                    Text(entry.name)
                        .font(.system(size: 12))
                    Spacer()
                    if !entry.isDirectory {
                        Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.modified)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 100)
                }
                .onTapGesture(count: 2) {
                    if entry.isDirectory {
                        Task { await navigateTo(entry.name) }
                    }
                }
            }
            .listStyle(.plain)
        }
        .sheet(isPresented: $showNewFolder) {
            VStack(spacing: 16) {
                Text("새 폴더").font(.headline)
                TextField("폴더 이름", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                HStack {
                    Button("취소") { showNewFolder = false }.keyboardShortcut(.escape)
                    Button("만들기") {
                        let name = newFolderName
                        Task {
                            try? await Task.detached {
                                try self.client.mkdir(path: "\(self.currentPath)/\(name)")
                            }.value
                            await reload()
                        }
                        showNewFolder = false
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .task { await reload() }
    }

    private var selectedEntry: FTPEntry? {
        entries.first { $0.id == selectedID }
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            let path = currentPath
            let result = try await Task.detached {
                try self.client.list(path: path)
            }.value
            entries = result.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func navigateTo(_ name: String) async {
        let newPath = currentPath == "/" ? "/\(name)" : "\(currentPath)/\(name)"
        do {
            try await Task.detached { try self.client.cd(path: newPath) }.value
            currentPath = client.currentPath
            await reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func goUp() {
        guard currentPath != "/" else { return }
        let parent = (currentPath as NSString).deletingLastPathComponent
        Task {
            do {
                try await Task.detached { try self.client.cd(path: parent.isEmpty ? "/" : parent) }.value
                currentPath = client.currentPath
                await reload()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func downloadSelected(_ entry: FTPEntry) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "여기에 다운로드"
        panel.message = "\(entry.name) 을 다운로드할 폴더를 선택하세요"
        guard panel.runModal() == .OK, let dst = panel.url else { return }
        let localURL = dst.appendingPathComponent(entry.name)
        let remotePath = currentPath == "/" ? "/\(entry.name)" : "\(currentPath)/\(entry.name)"
        Task {
            isLoading = true
            do {
                try await Task.detached {
                    try self.client.download(remotePath: remotePath, localURL: localURL) { _ in }
                }.value
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func uploadToRemote() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let files = panel.urls
        Task {
            isLoading = true
            for file in files {
                let remotePath = currentPath == "/" ? "/\(file.lastPathComponent)"
                                                    : "\(currentPath)/\(file.lastPathComponent)"
                do {
                    try await Task.detached {
                        try self.client.upload(localURL: file, remotePath: remotePath) { _ in }
                    }.value
                } catch {
                    errorMessage = error.localizedDescription
                    break
                }
            }
            await reload()
            isLoading = false
        }
    }
}
