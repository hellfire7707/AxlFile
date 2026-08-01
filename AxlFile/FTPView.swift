import SwiftUI
import Security

// MARK: - SFTP 연결 다이얼로그

struct SFTPConnectView: View {
    @Environment(AppState.self) private var appState

    @State private var name         = ""
    @State private var host         = ""
    @State private var port         = "22"
    @State private var username     = NSUserName()
    @State private var password     = ""
    @State private var useKeyAuth   = true
    @State private var isConnecting = false
    @State private var errorMsg:    String?
    @State private var saved        = SFTPConnectView.loadSaved()
    /// 사이드바에서 불러온 항목 — 저장 시 새로 추가하지 않고 이 항목을 덮어쓴다
    @State private var editingID:   UUID?
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            // 뒤쪽 UI를 가리는 딤 배경 (클릭 차단)
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { }
            panel
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 타이틀
            HStack(spacing: 7) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#4A9EFF"))
                Text("SFTP 연결")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NX.fileText)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(NX.infoText)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(hex: "#404040"))
            .overlay(alignment: .bottom) { Rectangle().frame(height: 1).foregroundStyle(Color(hex: "#555555")) }

            HStack(spacing: 0) {
                sidebar
                form
            }
        }
        .frame(width: 420)
        // 세로는 내용 크기로 고정 — ZStack 안에서 화면 전체로 늘어나지 않도록
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(hex: "#323232"))
        .overlay { Rectangle().strokeBorder(Color(hex: "#555555"), lineWidth: 1) }
        .shadow(color: .black.opacity(0.8), radius: 20, x: 0, y: 8)
    }

    // MARK: - 저장된 연결 사이드바

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("저장된 연결")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NX.headerText)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            if saved.isEmpty {
                Text("없음")
                    .font(.system(size: 10))
                    .foregroundStyle(NX.attrText)
                    .padding(.horizontal, 8)
            } else {
                ForEach(saved) { conn in
                    HStack(spacing: 4) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(conn.label)
                                .font(.system(size: 11))
                                .foregroundStyle(NX.fileText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text("\(conn.host):\(conn.port)")
                                .font(.system(size: 9))
                                .foregroundStyle(NX.infoText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        Button {
                            var updated = saved
                            updated.removeAll { $0.id == conn.id }
                            saved = updated
                            SFTPConnectView.saveSaved(updated)
                            SFTPKeychain.delete(conn.id)
                            if editingID == conn.id { editingID = nil }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(NX.infoText)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(editingID == conn.id ? NX.cursor : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { load(conn) }
                }
            }
            Spacer(minLength: 8)
        }
        .frame(width: 132)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "#282828"))
        .overlay(alignment: .trailing) { Rectangle().frame(width: 1).foregroundStyle(NX.separator) }
    }

    // MARK: - 연결 폼

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledField("이름") {
                TextField(host.isEmpty ? "연결 이름" : host, text: $name)
                    .textFieldStyle(.squareBorder)
                    .focused($nameFocused)
            }
            LabeledField("호스트") {
                TextField("example.com", text: $host)
                    .textFieldStyle(.squareBorder)
            }
            LabeledField("포트") {
                TextField("22", text: $port).textFieldStyle(.squareBorder).frame(width: 64)
            }
            LabeledField("사용자명") {
                TextField("username", text: $username).textFieldStyle(.squareBorder)
            }

            Toggle("SSH 키 인증", isOn: $useKeyAuth)
                .font(.system(size: 11))
                .foregroundStyle(NX.fileText)
                .controlSize(.small)

            if !useKeyAuth {
                LabeledField("비밀번호") {
                    SecureField("비밀번호", text: $password).textFieldStyle(.squareBorder)
                }
                Text("비밀번호는 macOS 키체인에 저장됩니다")
                    .font(.system(size: 9))
                    .foregroundStyle(NX.attrText)
                    .padding(.leading, 62)
            }

            if let err = errorMsg {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(err)
                }
                .foregroundStyle(.red)
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                actionBtn("저장", prominent: false, disabled: host.isEmpty) { saveConnection() }
                Spacer()
                if isConnecting { ProgressView().controlSize(.small) }
                actionBtn("연결", prominent: true, disabled: host.isEmpty || isConnecting) {
                    Task { await connect() }
                }
                .keyboardShortcut(.return)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 시트가 아니므로 패널 뒤 파일목록으로 키가 새지 않도록 첫 필드에 포커스
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { nameFocused = true } }
    }

    @ViewBuilder
    private func actionBtn(_ label: String, prominent: Bool, disabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(disabled ? NX.attrText : (prominent ? .white : NX.fileText))
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(prominent && !disabled ? NX.cursor : NX.headerBg)
                .overlay { Rectangle().strokeBorder(NX.separator, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func dismiss() {
        appState.showFTP = false
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

    /// 사이드바 항목을 폼으로 불러오기 — 이후 저장은 이 항목을 덮어쓴다
    private func load(_ conn: SavedSFTPConnection) {
        editingID  = conn.id
        name       = conn.label
        host       = conn.host
        port       = String(conn.port)
        username   = conn.username
        useKeyAuth = conn.useKeyAuth ?? true
        password   = SFTPKeychain.load(conn.id) ?? ""
        errorMsg   = nil
    }

    private func saveConnection() {
        let label = name.trimmingCharacters(in: .whitespaces).isEmpty
            ? host : name.trimmingCharacters(in: .whitespaces)
        var conns = saved

        // 1) 불러온 항목이 있으면 그 항목을, 2) 없으면 같은 이름의 항목을 덮어쓴다
        let targetIdx = conns.firstIndex { $0.id == editingID }
            ?? conns.firstIndex { $0.label == label }

        let savedID: UUID
        if let idx = targetIdx {
            conns[idx].label      = label
            conns[idx].host       = host
            conns[idx].port       = Int(port) ?? 22
            conns[idx].username   = username
            conns[idx].useKeyAuth = useKeyAuth
            savedID = conns[idx].id
        } else {
            let conn = SavedSFTPConnection(label: label, host: host,
                                           port: Int(port) ?? 22, username: username,
                                           useKeyAuth: useKeyAuth)
            conns.append(conn)
            savedID = conn.id
        }

        // 비밀번호는 키체인에 — 키 인증이면 남아있던 비밀번호를 지운다
        if useKeyAuth {
            SFTPKeychain.delete(savedID)
        } else {
            SFTPKeychain.save(password: password, for: savedID)
        }

        editingID = savedID
        name      = label
        saved     = conns
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
    /// 기존 저장 데이터에는 없던 필드 — 디코딩 실패로 목록이 날아가지 않도록 Optional
    var useKeyAuth: Bool?
}

// MARK: - Keychain  (비밀번호는 UserDefaults가 아니라 키체인에 보관)

enum SFTPKeychain {
    private static let service = "AxlFile.SFTP"

    /// 계정 키는 연결의 UUID — 호스트/사용자명을 바꿔도 항목이 따라간다
    static func save(password: String, for id: UUID) {
        guard !password.isEmpty else { delete(id); return }
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        let attrs: [String: Any] = [kSecValueData as String: Data(password.utf8)]

        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = Data(password.utf8)
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func load(_ id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData  as String: true,
            kSecMatchLimit  as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ id: UUID) {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct LabeledField<Content: View>: View {
    let label:   String
    let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label; self.content = content()
    }
    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .frame(width: 54, alignment: .trailing)
                .foregroundStyle(NX.headerText)
            content
                .font(.system(size: 11))
        }
    }
}
