import SwiftUI

/// A settings row that shows the chosen entity and opens EntityPicker.
struct EntityRow: View {
    let title: LocalizedStringKey
    let home: Home
    let domains: [String]
    @Binding var selection: String?

    var body: some View {
        NavigationLink {
            EntityPicker(title: title, home: home, domains: domains, selection: $selection)
        } label: {
            LabeledContent(title) {
                Text(verbatim: selection.map { home.attribute($0, "friendly_name") as? String ?? $0 } ?? "-")
            }
        }
    }
}
