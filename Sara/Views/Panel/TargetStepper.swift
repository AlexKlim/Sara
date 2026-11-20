import SwiftUI

/// − value + for a setpoint. A new value shows at once and goes out 1 s after the last tap, so a burst of taps
/// sends only the last one. It stays shown until the device holds it for 3 s. If that doesn't happen within 30 s,
/// `failed` turns on for 5 s.
struct TargetStepper: View {
    let id: String
    let name: String
    /// What is shown: `pending`, else the reported value.
    let value: Double
    let home: Home
    @Binding var pending: Double?
    @Binding var failed: Bool
    let format: (Double) -> String
    let reported: () -> Double?
    let send: (Double) async throws -> Void
    @State private var sending: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            button(up: false)
            Text(verbatim: format(value))
                .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                .frame(width: 76)
                .contentTransition(.numericText())
            button(up: true)
        }
    }

    private func button(up: Bool) -> some View {
        let next = home.stepped(id, value, up: up)
        return Button { set(next) } label: {
            Image(systemName: up ? "plus" : "minus")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
                .background(Theme.border, in: .circle)
                .overlay(Circle().stroke(Theme.ring))
        }
        .buttonStyle(.plain)
        .disabled(next == value)
        .opacity(next == value ? 0.4 : 1)
        .accessibilityLabel(up ? "Raise temperature: \(name)" : "Lower temperature: \(name)")
    }

    private func set(_ target: Double) {
        pending = target
        failed = false
        sending?.cancel()
        sending = Task {
            do {
                try await Task.sleep(for: .seconds(1))
                try await send(target)

                let deadline = Date.now + 30
                var heldSince: Date?

                while Date.now < deadline {
                    if let now = reported(), abs(now - target) < 0.01 {
                        if let since = heldSince {
                            if Date.now.timeIntervalSince(since) >= 3 {
                                pending = nil
                                return
                            }
                        } else {
                            heldSince = .now
                        }
                    } else {
                        heldSince = nil
                    }
                    try await Task.sleep(for: .milliseconds(500))
                }
                throw SaraError("Not confirmed")
            } catch {
                guard pending == target, !Task.isCancelled else { return }
                pending = nil
                failed = true
                try? await Task.sleep(for: .seconds(5))
                failed = false
            }
        }
    }
}
