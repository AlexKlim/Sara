import SwiftData
import SwiftUI

/// Settings like the iPadOS Settings app: pages in a sidebar, the page on the right. On iPhone, a plain list.
struct SettingsView: View {
    @AppStorage("haURL") private var haURL = ""
    @AppStorage("model") private var model = Claude.defaultModel
    @AppStorage("window") private var window = 150.0
    @AppStorage("houseNotes") private var notes = ""
    @AppStorage("deviceRoom") private var deviceRoom = ""
    @State private var rooms: [String] = []
    @AppStorage("speakerEntity") private var speakerEntity = ""
    @AppStorage("wakeEnabled") private var wakeEnabled = true
    @AppStorage("wakeWord") private var wakeWord = ""
    @AppStorage("followUpSeconds") private var followUpSeconds = 20.0
    @AppStorage("nightEnabled") private var nightEnabled = PowerSaver.isWallPanel
    @AppStorage("nightStart") private var nightStart = 23
    @AppStorage("nightEnd") private var nightEnd = 10
    @State private var apiKey = Keychain.get("anthropicKey")
    @State private var haToken = Keychain.get("haToken")
    @State private var yandexToken = Keychain.get("yandexToken")
    @State private var yandexStatus: String?
    @State private var section: SettingsSection? = .assistant
    @State private var home = Home()
    @State private var connection: String?
    @State private var sharing = false
    @State private var scanning = false
    @Query(sort: \Fact.name) private var facts: [Fact]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { item in
                Label { Text(item.title) } icon: { Image(systemName: item.icon) }
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Done") {
                    haURL = haURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                    dismiss()
                }
            }
        } detail: {
            NavigationStack {
                page(section ?? .assistant)
                    .navigationTitle(Text((section ?? .assistant).title))
            }
        }
        .tint(Theme.teal)
        .preferredColorScheme(.dark)
        // Secrets go to the Keychain as they are typed, so "Check connection" uses what is on screen.
        .onChange(of: apiKey) { Keychain.set("anthropicKey", apiKey.trimmingCharacters(in: .whitespacesAndNewlines)) }
        .onChange(of: haToken) { Keychain.set("haToken", haToken.trimmingCharacters(in: .whitespacesAndNewlines)) }
        .onChange(of: yandexToken) { Keychain.set("yandexToken", yandexToken.trimmingCharacters(in: .whitespacesAndNewlines)) }
        // Not a tap gesture: it would swallow the sidebar's row selection.
        .onChange(of: section) { PowerSaver.shared.activity() }
        .onChange(of: haURL) { CloudSettings.push("haURL") }
        .onChange(of: model) { CloudSettings.push("model") }
        .onChange(of: notes) { CloudSettings.push("houseNotes") }
    }

    @ViewBuilder private func page(_ section: SettingsSection) -> some View {
        switch section {
        case .assistant: assistant
        case .home: homeAssistant
        case .yandex: yandexHome
        case .voice: voice
        case .panel: PanelEditorView()
        case .night: night
        case .memory: memory
        }
    }

    private var assistant: some View {
        Form {
            Section {
                SecureField("API key", text: $apiKey)
                TextField("Model", text: $model)
            } header: {
                Text(verbatim: "Claude")
            }
            Section {
                Picker("This device is in", selection: $deviceRoom) {
                    Text("Not set").tag("")
                    ForEach(Set(rooms + [deviceRoom]).filter { !$0.isEmpty }.sorted(), id: \.self) { Text(verbatim: $0).tag($0) }
                }
            } footer: {
                Text("When you don't name a room, Sara means this one. Set it on each panel.")
            }
            .task { await loadRooms() }
            Section {
                TextEditor(text: $notes).frame(minHeight: 160)
            } header: {
                Text("House notes")
            } footer: {
                Text("Sara reads them before every conversation: what things are called, what not to touch.")
            }
            Section {
                Button("Share connection") { sharing = true }
                    .sheet(isPresented: $sharing) { ShareConnectionView() }
                Button("Scan connection") { scanning = true }
                    .sheet(isPresented: $scanning) { ScanConnectionView { dismiss() } }
            } footer: {
                Text("Your devices with the same Apple ID get the keys and the address through iCloud by themselves. For someone with their own Apple ID: show the code here, and on their device tap Scan connection.")
            }
            Section("Current conversation") {
                Stepper("Continues for \(Int(window)) s after a reply", value: $window, in: 30...600, step: 30)
            }
            Section {
                LabeledContent("Heat", value: String(localized: "\(PowerSaver.name(PowerSaver.shared.thermal)), highest since launch: \(PowerSaver.name(PowerSaver.shared.hottest))"))
            } footer: {
                Text("How hot this iPad gets. If it is often hot, always-on listening may be too much for it.")
            }
        }
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }

    private var homeAssistant: some View {
        Form {
            Section {
                TextField("Address", text: $haURL)
                    .keyboardType(.URL)
                SecureField("Long-lived token", text: $haToken)
            } footer: {
                Text("For example http://192.168.1.10:8123 or http://homeassistant.local:8123")
            }
            Section {
                Button("Check connection") { checkConnection() }
                if let connection { Text(verbatim: connection).foregroundStyle(.secondary) }
            }
        }
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }

    private var yandexHome: some View {
        Form {
            Section {
                if let url = Self.yandexTokenURL {
                    Link("Get a token", destination: url)
                }
                SecureField("Yandex token", text: $yandexToken)
            } footer: {
                if Self.yandexTokenURL == nil {
                    Text("Register an app at oauth.yandex.ru with the iot:view and iot:control rights and put its id in Config/Local.xcconfig as YANDEX_CLIENT_ID. Or paste a token you already have.")
                } else {
                    Text("For a home with Alice. Sign in to Yandex, copy the token it shows and paste it here. Sara sees and controls your devices and scenarios.")
                }
            }
            Section {
                Button("Check connection") { checkYandex() }
                if let yandexStatus { Text(verbatim: yandexStatus).foregroundStyle(.secondary) }
            }
        }
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }

    /// Yandex sign-in that ends on a page showing the token (implicit flow, verification_code redirect).
    private static var yandexTokenURL: URL? {
        guard !YandexHome.clientID.isEmpty else { return nil }
        return URL(string: "https://oauth.yandex.ru/authorize?response_type=token&client_id=\(YandexHome.clientID)")
    }

    private func checkYandex() {
        yandexStatus = String(localized: "Checking...")
        Task {
            do {
                let info = try await YandexHome(token: Keychain.get("yandexToken")).info()
                yandexStatus = String(localized: "Connected: \((info["devices"] as? [Any])?.count ?? 0) devices")
            } catch {
                yandexStatus = error.localizedDescription
            }
        }
    }

    private var voice: some View {
        Form {
            Section {
                Toggle("Listen for the wake word", isOn: $wakeEnabled)
                TextField("Wake word", text: $wakeWord, prompt: Text("Sara"))
                Stepper("After a reply, listens without it for \(Int(followUpSeconds)) s", value: $followUpSeconds, in: 0...60, step: 5)
            } header: {
                Text("Wake word")
            } footer: {
                Text("The microphone listens all the time, speech is recognized on this device. Say the word and the command together, e.g. \"Sara, turn on the light\".")
            }
            Section {
                EntityRow(title: "Speaker", home: home, domains: ["media_player"],
                          selection: Binding(get: { speakerEntity.isEmpty ? nil : speakerEntity }, set: { speakerEntity = $0 ?? "" }))
            } footer: {
                Text("Choose a Home Assistant speaker that reads text aloud, e.g. a Yandex Station in local mode. Without one, Sara speaks with this device.")
            }
        }
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .task { await home.refresh() }
    }

    private var night: some View {
        Form {
            Section {
                Toggle("Night mode", isOn: $nightEnabled)
                Stepper("Starts at \(NightView.hour(nightStart))", value: $nightStart, in: 0...23).disabled(!nightEnabled)
                Stepper("Ends at \(NightView.hour(nightEnd))", value: $nightEnd, in: 0...23).disabled(!nightEnabled)
            } footer: {
                Text("A dim clock instead of the panel, and Sara answers in text only.")
            }
        }
    }

    private var memory: some View {
        Form {
            Section {
                if facts.isEmpty { Text("Nothing yet").foregroundStyle(.secondary) }
                ForEach(facts) { fact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.content)
                        Text(verbatim: "\(fact.name) · \(fact.type)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { $0.map { facts[$0] }.forEach(context.delete) }
            } footer: {
                Text("What Sara remembers about the home and you. Swipe left to delete.")
            }
        }
    }

    /// Room names from Home Assistant areas, for the "This device is in" picker.
    private func loadRooms() async {
        let socket = HomeAssistantSocket(baseURL: haURL, token: Keychain.get("haToken"))
        guard let areas = try? await socket.call(["config/area_registry/list"]).first as? [[String: Any]] else { return }
        rooms = areas.compactMap { $0["name"] as? String }
    }

    /// Asks Home Assistant's MCP Server for Sara's tools: proves the address, the token and the integration at once.
    private func checkConnection() {
        connection = String(localized: "Checking...")
        let base = haURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        Task {
            guard let url = URL(string: base + "/api/mcp"), url.host != nil else {
                connection = String(localized: "Set the Home Assistant address in Settings")
                return
            }
            do {
                let tools = try await MCPClient(url: url, token: Keychain.get("haToken")).claudeTools()
                connection = String(localized: "Connected: \(tools.count) tools")
            } catch {
                connection = error.localizedDescription
            }
        }
    }
}
