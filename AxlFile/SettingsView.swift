import SwiftUI

// MARK: - Settings Window

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("일반", systemImage: "gearshape.fill") }
            ViewSettingsTab()
                .tabItem { Label("보기", systemImage: "eye.fill") }
            EditorSettingsTab()
                .tabItem { Label("편집기", systemImage: "pencil.and.list.clipboard") }
        }
        .frame(width: 440, height: 300)
        .preferredColorScheme(.dark)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @AppStorage("startupFolder")       private var startupFolder      = "home"
    @AppStorage("showHiddenDefault")   private var showHiddenDefault  = false
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete = true
    @AppStorage("overwritePolicy")     private var overwritePolicy    = "rename"

    var body: some View {
        Form {
            Section {
                Picker("시작 폴더", selection: $startupFolder) {
                    Text("홈 폴더").tag("home")
                    Text("마지막으로 열었던 위치").tag("last")
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("시작")
            }

            Section {
                Toggle("숨김 파일 기본 표시", isOn: $showHiddenDefault)
            } header: {
                Text("파일 표시")
            }

            Section {
                Toggle("삭제 전 확인 표시", isOn: $confirmBeforeDelete)
                Picker("파일 충돌 시", selection: $overwritePolicy) {
                    Text("자동으로 이름 변경").tag("rename")
                    Text("매번 확인 (상세 비교)").tag("confirm")
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("확인 메시지")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 300)
    }
}

// MARK: - View Tab

struct ViewSettingsTab: View {
    @AppStorage("col1Threshold") private var col1Threshold = 50
    @AppStorage("col2Threshold") private var col2Threshold = 150
    @AppStorage("col3Threshold") private var col3Threshold = 300
    @AppStorage("relativeDates")  private var relativeDates = true

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("1→2열 전환")
                    Spacer()
                    Stepper("\(col1Threshold)개 이상", value: $col1Threshold, in: 10...500, step: 10)
                }
                HStack {
                    Text("2→3열 전환")
                    Spacer()
                    Stepper("\(col2Threshold)개 이상", value: $col2Threshold, in: 10...1000, step: 10)
                }
                HStack {
                    Text("3→4열 전환")
                    Spacer()
                    Stepper("\(col3Threshold)개 이상", value: $col3Threshold, in: 10...2000, step: 10)
                }
            } header: {
                Text("다열 전환 기준 (파일 수)")
            }

            Section {
                Toggle("오늘/어제 상대 날짜로 표시", isOn: $relativeDates)
            } header: {
                Text("날짜 형식")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 300)
    }
}

// MARK: - Editor Tab

struct EditorSettingsTab: View {
    @AppStorage("externalEditor")       private var externalEditor       = ""
    @AppStorage("openTextInEditor")     private var openTextInEditor     = false

    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("경로 (예: /usr/local/bin/code)", text: $externalEditor)
                        .textFieldStyle(.roundedBorder)
                    Button("찾기…") { browseEditor() }
                        .controlSize(.small)
                }
                Toggle("텍스트 파일 더블클릭 시 외부 편집기로 열기", isOn: $openTextInEditor)
                    .disabled(externalEditor.isEmpty)
            } header: {
                Text("외부 편집기")
            } footer: {
                Text("비워두면 기본 앱이 사용됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 300)
    }

    private func browseEditor() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        panel.title = "편집기 실행 파일 선택"
        if panel.runModal() == .OK, let url = panel.url {
            externalEditor = url.path
        }
    }
}
