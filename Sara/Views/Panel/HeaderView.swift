import SwiftUI

/// Top of the panel: clock, date, weather, the talk button and settings.
struct HeaderView: View {
    let home: Home
    let weather: String?
    /// Wake word listening is on.
    let listening: Bool
    let onTalk: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            TimelineView(.everyMinute) { context in
                HStack(spacing: 24) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 84, weight: .semibold)).tracking(-3).monospacedDigit()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NightView.capitalizedFirst(context.date.formatted(.dateTime.weekday(.wide)))).font(.system(size: 22, weight: .medium))
                        Text(context.date, format: .dateTime.day().month(.wide)).font(.system(size: 18)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            Spacer()
            if let weather, let condition = home.state(weather) {
                HStack(spacing: 12) {
                    Image(systemName: Self.symbol(condition)).font(.system(size: 30)).foregroundStyle(Theme.secondary)
                    VStack(alignment: .leading) {
                        if let temperature = home.attribute(weather, "temperature") as? Double {
                            Text(verbatim: "\(Int(temperature.rounded()))°").font(.system(size: 28, weight: .semibold))
                        }
                        Text(LocalizedStringKey("weather." + condition)) // a ready key: interpolation would make it "weather.%@".font(.system(size: 16)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            Button(action: onTalk) {
                HStack(spacing: 12) {
                    Circle().fill(Theme.teal).frame(width: 10, height: 10)
                    Text(listening ? "Sara is listening" : "Talk to Sara")
                }
                .font(.system(size: 18, weight: .medium))
                .padding(.horizontal, 22).padding(.vertical, 14)
                .background(Theme.tealBackground, in: .capsule)
                .overlay(Capsule().stroke(Color(hex: 0x24413E)))
            }
            .buttonStyle(.plain)
            Button("Settings", systemImage: "gearshape", action: onSettings)
                .labelStyle(.iconOnly).font(.title2).foregroundStyle(Theme.secondary)
        }
        .foregroundStyle(Theme.text)
    }

    /// SF Symbol for a Home Assistant weather condition.
    private static func symbol(_ condition: String) -> String {
        [
            "clear-night": "moon.stars", "cloudy": "cloud", "fog": "cloud.fog", "hail": "cloud.hail",
            "lightning": "cloud.bolt", "lightning-rainy": "cloud.bolt.rain", "partlycloudy": "cloud.sun",
            "pouring": "cloud.heavyrain", "rainy": "cloud.rain", "snowy": "cloud.snow", "snowy-rainy": "cloud.sleet",
            "sunny": "sun.max", "windy": "wind", "windy-variant": "wind", "exceptional": "exclamationmark.triangle",
        ][condition] ?? "cloud"
    }
}
