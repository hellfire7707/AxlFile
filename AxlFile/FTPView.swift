import SwiftUI

// MARK: - SFTP 연결 다이얼로그

struct SFTPConnectView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var host         = ""
    @State private var port         = "22"
    @State private var username     = NSUserName()
    @State private var password     = ""
    @State private var useKeyAuth   = true
    @State private var isConnecting = false
    @State private var errorMsg:    String?
    @State private var saved        = SFTPConnectView.loadSaved()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 타이틀
            HStack {
                Image(systemName: "lock.shield.fill").font(.title2).foregroundStyle(.blue)
                Text("SFTP 연결").font(.title2).bold()
                Spacer()
                Button("닫기") { dismiss() }.keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            HStack(alignment: .top, spacing: 0) {
                // 저장된 연결 사이드바
                VStack(alignment: .leading, spacing: 6) {
                    Text("저장된 연결")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 8)

                    if saved.isEmpty {
                        Text("없음").font(.caption).foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                    } else {
                        ForEach(saved) { conn in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conn.label).font(.system(size: 12))
                                    Text("\(conn.host):\(conn.port)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    var updated = saved
                                    updated.removeAll { $0.id == conn.id }
                                    saved = updated
                                    SFTPConnectView.saveSaved(updated)
                                } label: { Image(systemName: "xmark").font(.caption) }
                                .buttonStyle(.borderless).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
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

                // 연결 폼
                VStack(alignment: .leading, spacing: 14) {
                    LabeledField("호스트") {
                        TextField("example.com", text: $host).textFieldStyle(.roundedBorder)
                    }
                    LabeledField("포트") {
                        TextField("22", text: $port).textFieldStyle(.roundedBorder).frame(width: 80)
                    }
                    LabeledField("사용자명") {
                        TextField("username", text: $username).textFieldStyle(.roundedBorder)
                    }

                    Toggle("SSH 키 인증 (비밀번호 불필요)", isOn: $useKeyAuth)
                        .font(.system(size: 12))

                    if !useKeyAuth {
                        LabeledField("비밀번호") {
                            SecureField("비밀번호", text: $password).textFieldStyle(.roundedBorder)
                        }
                    }

                    if let err = errorMsg {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                            Text(err)
                        }
                        .foregroundStyle(.red).font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        Button("저장") { saveConnection() }.buttonStyle(.bordered).disabled(host.isEmpty)
                        Spacer()
                        if isConnecting { ProgressView().controlSize(.small) }
                        Button("연결") { Task { await connect() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(host.isEmpty || isConnecting)
                            .keyboardShortcut(.return)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 500)
    }

    private func connect() async {
        isConnecting = true
        errorMsg = nil
        let client = SFTPClient(
            host:       host,
            port:       Int(port) ?? 22,
            username:   username,
            password:   password,
            useKeyAuth: useKeyAuth
        )
        do {
            try await Task.detached { try client.connect() }.value
            appState.openSFTPTab(client: client)
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
        isConnecting = false
    }

    private func saveConnection() {
        let conn = SavedSFTPConnection(label: host, host: host,
                                       port: Int(port) ?? 22, username: username)
        var conns = saved
        conns.append(conn)
        saved = conns
        SFTPConnectView.saveSaved(conns)
    }

    static func loadSaved() -> [SavedSFTPConnection] {
        guard let data = UserDefaults.standard.data(forKey: "sftpConnections"),
              let decoded = try? JSONDecoder().decode([SavedSFTPConnection].self, from: data)
        else { return [] }
        return decoded
    }

    static func saveSaved(_ conns: [SavedSFTPConnection]) {
        if let data = try? JSONEncoder().encode(conns) {
            UserDefaults.standard.set(data, forKey: "sftpConnections")
        }
    }
}

struct SavedSFTPConnection: Identifiable, Codable {
    var id       = UUID()
    var label:    String
    var host:     String
    var port:     Int
    var username: String
}

struct LabeledField<Content: View>: View {
    let label:   String
    let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label; self.content = content()
    }
    var body: some View {
        HStack {
            Text(label).frame(width: 72, alignment: .trailing).foregroundStyle(.secondary)
            content
        }
    }
}
