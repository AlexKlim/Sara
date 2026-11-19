import SwiftUI

/// A 0-100 slider, e.g. TV volume. Shows where it was set until Home Assistant reports the same.
struct SliderBlockView: View {
    let title: String
    let item: PanelItem
    let home: Home
    @State private var value = 0.0
    @State private var dragging = false
    /// The level sent last: a TV reports its volume seconds late, so the slider must not jump back meanwhile.
    @State private var pending: Double?
    @State private var sending: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(verbatim: "\(Int(value.rounded()))").font(.system(size: 28, weight: .semibold)).monospacedDigit()
            }
            Slider(value: $value, in: 0...100) { editing in
                dragging = editing
                if !editing { send(value.rounded()) }
            }
            .tint(Theme.amber)
            .accessibilityLabel(title)
        }
        .foregroundStyle(Theme.text)
        .card(padding: 22)
        .onAppear { value = home.value(item) ?? value }
        .onChange(of: home.value(item)) { if !dragging, pending == nil, let new = $1 { value = new } }
    }

    private func send(_ level: Double) {
        pending = level
        sending?.cancel()
        sending = Task {
            // Moves in a row send one level.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let before = home.value(item)
            await home.setValue(item, level)
            // The old value close to the new one is no confirmation: wait for a report that changed.
            let unchanged = before.map { abs($0 - level) < 1.5 } ?? false
            let deadline = Date.now + 30
            while !Task.isCancelled, Date.now < deadline {
                if let reported = home.value(item), abs(reported - level) < 1.5, unchanged || reported != before { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard !Task.isCancelled else { return }
            pending = nil
            if !dragging, let reported = home.value(item) { value = reported }
        }
    }
}
