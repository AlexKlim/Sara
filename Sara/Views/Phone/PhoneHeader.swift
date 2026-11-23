import SwiftUI

/// Top of the phone screen: the date, "Home" and the weather, which opens the forecast.
struct PhoneHeader: View {
    /// Comes from the screen's own minute timer: a TimelineView here, inside the tab's scroll view,
    /// sent the layout round in circles.
    let date: Date
    /// Room to name the weather next to the temperature.
    var wide = false
    @State private var showWeather = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: date.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirst)
                    .font(.system(size: 15)).foregroundStyle(Theme.secondary).lineLimit(1)
                Text("Home").font(.system(size: 34, weight: .bold)).tracking(-0.5)
            }
            Spacer(minLength: 0)
            if let forecast = Weather.shared.forecast {
                Button { showWeather = true } label: {
                    HStack(spacing: 8) {
                        WeatherIcon(condition: forecast.condition, size: 20, color: Theme.secondary)
                        Text(verbatim: forecast.current.temperature.rounded().degrees).font(.system(size: 17, weight: .semibold))
                        if wide {
                            Text(LocalizedStringKey("weather." + forecast.condition)).font(.system(size: 14)).foregroundStyle(Theme.secondary)
                        }
                    }
                    .padding(.leading, 12).padding(.trailing, 16)
                    .frame(height: 44)
                    .background(Theme.card, in: .capsule)
                    .overlay(Capsule().stroke(Theme.border))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the forecast")
                .sheet(isPresented: $showWeather) {
                    WeatherView(forecast: forecast, updated: Weather.shared.updated, wide: false)
                }
            }
        }
        .foregroundStyle(Theme.text)
    }
}
