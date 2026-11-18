import SwiftUI

/// Thermostats: target temperature with − and + buttons, and the current one. The icon glows while heating.
struct ClimateBlockView: View {
    let block: PanelBlock
    let home: Home
    @State private var pending: [String: Double] = [:]
    @State private var failed: Set<String> = []
    @State private var sending: [String: Task<Void, Never>] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(block.title).blockTitle()
            VStack(spacing: 0) {
                ForEach(block.items) { item in
                    row(item).padding(.vertical, 14)
                    if item.id != block.items.last?.id { Divider().overlay(Theme.border) }
                }
            }
            .foregroundStyle(Theme.text)
            .padding(.leading, 24)
            .padding(.trailing, 20)
            .padding(.vertical, 4)
            .card(padding: 0)
        }
    }

    private func row(_ item: PanelItem) -> some View {
        let id = item.entity
        let name = home.name(item)
        let target = pending[id] ?? home.attribute(id, "temperature") as? Double
        let heating = home.isHeating(id, target: target)
        let status = status(id, heating: heating, target: target)
        return HStack(spacing: 14) {
            Image(systemName: "thermometer.medium").font(.system(size: 22))
                .foregroundStyle(heating ? Theme.amber : Theme.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).font(.system(size: 18, weight: .medium))
                if let status {
                    Text(status).font(.system(size: 15)).foregroundStyle(heating || failed.contains(id) ? Theme.amber : Theme.secondary)
                }
            }
            Spacer()
            if let target, id.hasPrefix("climate.") {
                HStack(spacing: 8) {
                    stepButton(id, name: name, target: target, up: false)
                    Text(verbatim: target.degreesTenths)
                        .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                        .frame(width: 76)
                        .contentTransition(.numericText())
                    stepButton(id, name: name, target: target, up: true)
                }
            } else if let target {
                Text(verbatim: target.degreesTenths).font(.system(size: 28, weight: .semibold)).monospacedDigit()
            }
        }
    }

    private func stepButton(_ id: String, name: String, target: Double, up: Bool) -> some View {
        let next = home.stepped(id, target, up: up)
        return Button { set(id, next) } label: {
            Image(systemName: up ? "plus" : "minus")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
                .background(Theme.border, in: .circle)
                .overlay(Circle().stroke(Theme.ring))
        }
        .buttonStyle(.plain)
        .disabled(next == target)
        .opacity(next == target ? 0.4 : 1)
        .accessibilityLabel(up ? "Raise temperature: \(name)" : "Lower temperature: \(name)")
    }

    private func set(_ id: String, _ target: Double) {
        pending[id] = target
        failed.remove(id)
        sending[id]?.cancel()
        sending[id] = Task {
            do {
                try await Task.sleep(for: .seconds(1))
                try await home.setTemperature(id, target)

                let deadline = Date.now + 30
                var heldSince: Date?

                while Date.now < deadline {
                    if abs((home.attribute(id, "temperature") as? Double ?? .nan) - target) >= 0.01 {
                        heldSince = nil
                    } else if let since = heldSince, Date.now.timeIntervalSince(since) >= 3 {
                        pending[id] = nil
                        return
                    } else if heldSince == nil {
                        heldSince = .now
                    }
                    try await Task.sleep(for: .milliseconds(500))
                }
                throw SaraError("Not confirmed")
            } catch {
                guard pending[id] == target, !Task.isCancelled else { return }
                pending[id] = nil
                failed.insert(id)
                try? await Task.sleep(for: .seconds(5))
                failed.remove(id)
            }
        }
    }

    private func status(_ id: String, heating: Bool, target: Double?) -> LocalizedStringKey? {
        if failed.contains(id) { return "Couldn't change the temperature" }
        guard let current = home.attribute(id, "current_temperature") as? Double else { return nil }
        let now = current.degrees
        if home.state(id) == "off" { return "Now \(now), off" }
        if heating { return "Now \(now), heating" }
        if let target, current > target + 0.5 { return "Now \(now), cooling" }
        return "Now \(now), holding"
    }
}
