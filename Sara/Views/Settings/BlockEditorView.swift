import SwiftUI

/// Settings of one panel block: title, column, and its devices.
struct BlockEditorView: View {
    @Binding var block: PanelBlock
    let home: Home

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $block.title)
                Picker("Column", selection: $block.column) {
                    Text("Left").tag(0)
                    Text("Right").tag(1)
                }
            } footer: {
                Text(block.kind.name)
            }
            devices
        }
        .navigationTitle(block.title)
        .toolbar { EditButton() }
    }

    private var devices: some View {
        Section("Devices") {
            ForEach($block.items) { $item in
                NavigationLink {
                    ItemEditorView(item: $item, kind: block.kind, home: home)
                } label: {
                    VStack(alignment: .leading) {
                        Text(verbatim: home.name(item))
                        Text(verbatim: item.entity).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onMove { block.items.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { block.items.remove(atOffsets: $0) }
            NavigationLink("Add device") {
                EntityPicker(title: "Add device", home: home, domains: block.kind.domains,
                             selection: Binding(get: { nil }, set: { if let id = $0 { block.items.append(PanelItem(entity: id)) } }))
            }
        }
    }
}
