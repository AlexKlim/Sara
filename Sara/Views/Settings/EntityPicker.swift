import SwiftUI

/// Pick a Home Assistant entity from a searchable list, limited to some domains.
struct EntityPicker: View {
    let title: LocalizedStringKey
    let home: Home
    let domains: [String]
    @Binding var selection: String?
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var entities: [String] {
        home.states.keys
            .filter { id in domains.contains { id.hasPrefix($0 + ".") } }
            .filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) || name($0).localizedCaseInsensitiveContains(search) }
            .sorted()
    }

    var body: some View {
        List {
            if selection != nil {
                Button("None", role: .destructive) { selection = nil; dismiss() }
            }
            ForEach(entities, id: \.self) { id in
                Button { selection = id; dismiss() } label: {
                    VStack(alignment: .leading) {
                        Text(verbatim: name(id))
                        Text(verbatim: id).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .searchable(text: $search)
        .navigationTitle(title)
    }

    private func name(_ id: String) -> String { home.attribute(id, "friendly_name") as? String ?? id }
}
