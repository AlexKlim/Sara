import SwiftUI

/// Settings of one panel item. Which fields show depends on the block kind.
struct ItemEditorView: View {
    @Binding var item: PanelItem
    let kind: PanelBlock.Kind
    let home: Home

    var body: some View {
        Form {
            Section {
                TextField("Name", text: text(\.name), prompt: Text(verbatim: home.attribute(item.entity, "friendly_name") as? String ?? ""))
                EntityRow(title: "Entity", home: home, domains: kind.domains, selection: Binding(get: { item.entity }, set: { item.entity = $0 ?? item.entity }))
            }
            if kind == .slider {
                Section {
                    EntityRow(title: "Script", home: home, domains: ["script"], selection: $item.script)
                    TextField("Script field", text: text(\.field), prompt: Text(verbatim: "value"))
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
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .navigationTitle(home.name(item))
    }

    /// An optional text field as a plain one: empty means nil.
    private func text(_ field: WritableKeyPath<PanelItem, String?>) -> Binding<String> {
        Binding(get: { item[keyPath: field] ?? "" }, set: { item[keyPath: field] = $0.isEmpty ? nil : $0 })
    }
}
