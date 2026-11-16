import SwiftUI

/// One item of a list on the panel: a circle, or a check and strikethrough when done. Tap to toggle.
struct ChecklistRow: View {
    let text: String
    let done: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 14) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(done ? Theme.muted : Theme.teal)
                Text(verbatim: text).font(.system(size: 18))
                    .strikethrough(done)
                    .foregroundStyle(done ? Theme.muted : Theme.text)
                Spacer()
            }
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(done ? .isSelected : [])
    }
}
