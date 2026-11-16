import SwiftUI

/// A room tile: tap to toggle a light or switch, or to run a scene or script.
struct TileView: View {
    let item: PanelItem
    let home: Home

    var body: some View {
        let on = home.isOn(item.entity)
        Button {
            Task { await home.toggle(item.entity) }
        } label: {
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
