import SwiftUI

/// Top of the panel: clock, date, weather, the talk button and settings.
struct HeaderView: View {
    let home: Home
    /// Wake word listening is on.
    let listening: Bool
    let onTalk: () -> Void
    let onSettings: () -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showWeather = false

    var body: some View {
        HStack(spacing: 24) {
            TimelineView(.everyMinute) { context in
                HStack(spacing: 24) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 84, weight: .semibold)).tracking(-3).monospacedDigit()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.date.formatted(.dateTime.weekday(.wide)).capitalizedFirst).font(.system(size: 22, weight: .medium))
                        Text(context.date, format: .dateTime.day().month(.wide)).font(.system(size: 18)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            Spacer()
            if let forecast = Weather.shared.forecast {
                Button { showWeather = true } label: {
                    HStack(spacing: 12) {
                        WeatherIcon(condition: forecast.condition, size: 30, color: Theme.secondary)
                        VStack(alignment: .leading) {
                            Text(verbatim: forecast.current.temperature.rounded().degrees).font(.system(size: 28, weight: .semibold))
                            Text(LocalizedStringKey("weather." + forecast.condition)).font(.system(size: 16)).foregroundStyle(Theme.secondary)
                        }
                        Image(systemName: "chevron.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the forecast")
                .sheet(isPresented: $showWeather) {
                    WeatherView(forecast: forecast, updated: Weather.shared.updated, wide: sizeClass == .regular)
                        .presentationSizing(.fitted)
                        .presentationCornerRadius(28)
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
                .overlay(Capsule().stroke(Theme.tealBorder))
            }
            .buttonStyle(.plain)
            Button("Settings", systemImage: "gearshape", action: onSettings)
                .labelStyle(.iconOnly).font(.title2).foregroundStyle(Theme.secondary)
        }
        .foregroundStyle(Theme.text)
    }
}
