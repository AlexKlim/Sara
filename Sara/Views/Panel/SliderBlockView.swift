import SwiftUI

/// A 0-100 slider, e.g. TV volume. Sends the value when the finger lifts.
struct SliderBlockView: View {
    let title: String
    let item: PanelItem
    let home: Home
    @State private var value = 0.0
    @State private var dragging = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(verbatim: "\(Int(value.rounded()))").font(.system(size: 28, weight: .semibold)).monospacedDigit()
            }
            Slider(value: $value, in: 0...100) { editing in
                dragging = editing
                if !editing { Task { await home.setValue(item, value) } }
            }
            .tint(Theme.amber)
            .accessibilityLabel(title)
        }
        .foregroundStyle(Theme.text)
        .card(padding: 22)
        .onAppear { value = home.value(item) ?? value }
        .onChange(of: home.value(item)) { if !dragging, let new = $1 { value = new } }
    }
}
