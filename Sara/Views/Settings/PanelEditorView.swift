import SwiftUI

/// Settings > Panel: the blocks of the main screen. Add, remove, reorder, edit. Saves on every change.
struct PanelEditorView: View {
    @State private var home = Home()
    @State private var panel = Panel.load()
    @State private var confirmBuild = false
    @State private var building = false
    @AppStorage("haURL") private var haURL = ""

    var body: some View {
        Form {
            Section("Blocks") {
                ForEach($panel.blocks) { $block in
                    NavigationLink {
                        BlockEditorView(block: $block, home: home)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(verbatim: block.title)
                            Text(block.kind.name).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onMove { panel.blocks.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { panel.blocks.remove(atOffsets: $0) }
                Button("Build from Home Assistant") { confirmBuild = true }
                    .disabled(building)
                if let bundled = Panel.bundled {
                    Button("Restore the layout from Panel.local.json") { panel = bundled }
                }
                Menu("Add block") {
                    ForEach(PanelBlock.Kind.allCases, id: \.self) { kind in
                        Button { panel.blocks.append(PanelBlock(kind: kind, title: String(localized: kind.name))) } label: { Text(kind.name) }
                    }
                }
            }
        }
        .navigationTitle("Panel")
        .confirmationDialog("Replace the panel with one built from Home Assistant rooms?", isPresented: $confirmBuild, titleVisibility: .visible) {
            Button("Replace", role: .destructive) {
                building = true
                Task {
                    if let built = try? await Panel.build(from: HomeAssistantSocket(baseURL: haURL, token: Keychain.get("haToken"))) {
                        panel = built
                    }
                    building = false
                }
            }
        }
        .toolbar { EditButton() }
        .task { await home.refresh() }
        .onChange(of: panel) { panel.save() }
    }
}
