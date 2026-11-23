import SwiftUI

/// A room tile: tap to toggle a light or switch, or to run a scene or script.
struct TileView: View {
    let item: PanelItem
    let home: Home
    /// On the phone all rooms share one grid, so the tile names its room.
    var room: String?
    @Environment(\.compactPanel) private var compact

    var body: some View {
        let on = home.isOn(item.entity)
        Button {
            Task { await home.toggle(item.entity) }
        } label: {
            Group {
                if compact {
                    HStack(spacing: 10) {
                        Image(systemName: icon(on)).font(.system(size: 20)).foregroundStyle(on ? Theme.amber : Theme.muted).frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            // Long names wrap instead of being cut off; the tile is tall enough for two lines.
                            Text(home.name(item)).font(.system(size: 14, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.9)
                            let detail = [room ?? "", subtitle(on)].filter { !$0.isEmpty }.joined(separator: " · ")
                            if !detail.isEmpty {
                                Text(verbatim: detail).font(.system(size: 13)).foregroundStyle(on ? Theme.amber : Theme.secondary).lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60, alignment: .leading)
                    .background(on ? Theme.amberBackground : Theme.card, in: .rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(on ? Theme.amberBorder : Theme.border))
                } else {
                    VStack(alignment: .leading) {
                        Image(systemName: icon(on)).font(.system(size: 24)).foregroundStyle(on ? Theme.amber : Theme.muted)
                        Spacer()
                        Text(home.name(item)).font(.system(size: 18, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
                        Text(subtitle(on)).font(.system(size: 15)).foregroundStyle(on ? Theme.amber : Theme.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .leading)
                    .background(on ? Theme.amberBackground : Theme.card, in: .rect(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(on ? Theme.amberBorder : Theme.border))
                }
            }
            .foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func icon(_ on: Bool) -> String {
        switch item.entity.components(separatedBy: ".").first {
        case "light": on ? "lightbulb.fill" : "lightbulb"
        case "yandex" where (home.attribute(item.entity, "yandex_type") as? String ?? "").contains("light"): on ? "lightbulb.fill" : "lightbulb"
        case "scene": "sparkles"
        case "script": "play"
        default: "power"
        }
    }

    private func subtitle(_ on: Bool) -> String {
        let domain = item.entity.components(separatedBy: ".").first
        if domain == "scene" || domain == "script" { return "" }
        guard on else { return String(localized: "Off") }
        if let brightness = home.attribute(item.entity, "brightness") as? Double {
            return (brightness / 255).formatted(.percent.precision(.fractionLength(0)))
        }
        return String(localized: "On")
    }
}
