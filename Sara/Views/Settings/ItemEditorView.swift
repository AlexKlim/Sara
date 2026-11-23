import SwiftUI

/// Settings of one panel item. Which fields show depends on the block kind.
struct ItemEditorView: View {
    @Binding var item: PanelItem
    let kind: PanelBlock.Kind
    let home: Home
    @AppStorage("haURL") private var haURL = ""
    /// The fields the chosen script takes, from Home Assistant. Empty when unknown: then the field is typed in.
    @State private var scriptFields: [String] = []

    var body: some View {
        Form {
            Section {
                TextField("Name", text: text(\.name), prompt: Text(verbatim: home.attribute(item.entity, "friendly_name") as? String ?? ""))
                EntityRow(title: "Entity", home: home, domains: kind.domains, selection: Binding(get: { item.entity }, set: { item.entity = $0 ?? item.entity }))
            }
            if kind == .slider {
                Section {
                    EntityRow(title: "Script", home: home, domains: ["script"], selection: $item.script)
                    if scriptFields.count > 1 {
                        Picker("Script field", selection: text(\.field)) {
                            ForEach(scriptFields, id: \.self) { Text(verbatim: $0).tag($0) }
                        }
                    } else if item.script != nil {
                        TextField("Script field", text: text(\.field), prompt: Text(verbatim: "value"))
                    }
                } footer: {
                    Text("The value comes from the entity. To change it, set a script, e.g. a TV volume script. Without one, media players and lights are set directly.")
                }
            }
            if kind == .running {
                Section {
                    TextField("Icon (SF Symbol)", text: text(\.icon), prompt: Text(verbatim: "timer"))
                    EntityRow(title: "Working status", home: home, domains: ["sensor", "binary_sensor"], selection: $item.active)
                    EntityRow(title: "Progress", home: home, domains: ["sensor"], selection: $item.progress)
                    EntityRow(title: "Finish time", home: home, domains: ["sensor"], selection: $item.end)
                    EntityRow(title: "Detail", home: home, domains: ["sensor"], selection: $item.detail)
                } footer: {
                    Text("The entity is the remaining-time sensor. Set a working status if that sensor keeps a value while the device is idle.")
                }
            }
        }
        .task(id: item.script) { await loadScriptFields() }
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .navigationTitle(home.name(item))
    }

    /// Reads the chosen script's fields from Home Assistant. A script with one field gets it filled in,
    /// so nobody has to know its name; with several, they are offered to pick from.
    private func loadScriptFields() async {
        guard kind == .slider, let script = item.script,
              let services = try? await HomeAssistantSocket(baseURL: haURL, token: Keychain.get("haToken")).call(["get_services"]).first as? [String: Any],
              let fields = ((services["script"] as? [String: Any])?[PanelItem.objectID(script)] as? [String: Any])?["fields"] as? [String: Any]
        else { scriptFields = []; return }
        // The user may have picked another script while this one loaded.
        guard script == item.script else { return }
        scriptFields = fields.keys.sorted()
        // A field typed by hand stays: a script can use a variable it does not declare.
        if item.field?.isEmpty ?? true { item.field = scriptFields.first }
    }

    /// An optional text field as a plain one: empty means nil.
    private func text(_ field: WritableKeyPath<PanelItem, String?>) -> Binding<String> {
        Binding(get: { item[keyPath: field] ?? "" }, set: { item[keyPath: field] = $0.isEmpty ? nil : $0 })
    }
}
