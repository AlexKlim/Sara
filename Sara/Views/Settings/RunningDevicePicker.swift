import SwiftUI

struct RunningDevicePicker: View {
    @Binding var block: PanelBlock
    let home: Home
    @AppStorage("haURL") private var haURL = ""
    @State private var devices: [PanelItem]?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if let devices {
                    let shown = Set(block.items.map(\.entity))
                    let new = devices.filter { !shown.contains($0.entity) }
                    if new.isEmpty { Text("No other devices that report time left").foregroundStyle(.secondary) }
                    ForEach(new) { item in
                        Button { block.items.append(item); dismiss() } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(verbatim: home.name(item))
                                    Text(verbatim: item.entity).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: item.icon ?? "timer")
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } else {
                    ProgressView()
                }
            }
            Section {
                NavigationLink("Another sensor") {
                    EntityPicker(title: "Add device", home: home, domains: block.kind.domains,
                                 selection: Binding(get: { nil }, set: { if let id = $0 { block.items.append(PanelItem(entity: id)) } }))
                }
            }
        }
        .navigationTitle("Add device")
        .task {
            let built = try? await Panel.build(from: HomeAssistantSocket(baseURL: haURL, token: Keychain.get("haToken")))
            devices = built?.blocks.first { $0.kind == .running }?.items ?? []
        }
    }
}
