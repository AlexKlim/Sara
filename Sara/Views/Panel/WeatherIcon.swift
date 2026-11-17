import SwiftUI

/// A weather condition (by its Home Assistant name) as an SF Symbol, in the condition's color unless one is given.
struct WeatherIcon: View {
    let condition: String
    var size: CGFloat = 22
    var color: Color?

    var body: some View {
        Image(systemName: symbol).font(.system(size: size)).foregroundStyle(color ?? tint)
    }

    private var symbol: String {
        [
            "clear-night": "moon.stars", "cloudy": "cloud", "fog": "cloud.fog", "hail": "cloud.hail",
            "lightning-rainy": "cloud.bolt.rain", "partlycloudy": "cloud.sun", "pouring": "cloud.heavyrain",
            "rainy": "cloud.rain", "snowy": "cloud.snow", "snowy-rainy": "cloud.sleet", "sunny": "sun.max",
            "exceptional": "exclamationmark.triangle",
        ][condition] ?? "cloud"
    }

    private var tint: Color {
        switch condition {
        case "sunny", "clear-night": Theme.amber
        case "partlycloudy": Theme.soft
        case "rainy", "pouring", "lightning-rainy": Theme.blue
        case "snowy", "snowy-rainy", "hail": Theme.snow
        default: Theme.secondary
        }
    }
}
