import SwiftUI

/// The forecast sheet: now, the next hours, details, likely rain and ten days.
struct WeatherView: View {
    let forecast: Forecast
    let updated: Date?
    let wide: Bool
    @Environment(\.dismiss) private var dismiss

    private typealias Detail = (label: LocalizedStringKey, value: String, note: String)

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            if wide {
                HStack(alignment: .top, spacing: 32) {
                    now.frame(width: 460)
                    days
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) { now; days }
                }
            }
        }
        .padding(wide ? 32 : 20)
        .frame(idealWidth: wide ? 1060 : nil, maxWidth: wide ? 1060 : nil)
        .foregroundStyle(Theme.text)
        .background(Theme.sheet)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("Weather").font(.system(size: 28, weight: .semibold))
            if let updated {
                Text("Updated at \(updated.formatted(date: .omitted, time: .shortened))").font(.system(size: 16)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button("Close", systemImage: "xmark") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 48, height: 48)
                .background(Theme.card, in: .circle)
                .overlay(Circle().stroke(Theme.ring))
                .buttonStyle(.plain)
        }
    }

    // MARK: Now

    private var now: some View {
        let current = forecast.current
        let rows = details
        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 20) {
                WeatherIcon(condition: forecast.condition, size: 56)
                Text(verbatim: current.temperature.rounded().degrees).font(.system(size: 72, weight: .semibold)).tracking(-2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey("weather." + forecast.condition)).font(.system(size: 22, weight: .medium))
                    Group {
                        Text("Feels like \(current.feelsLike.rounded().degrees)")
                        if let high = forecast.daily.high.first, let low = forecast.daily.low.first {
                            Text("High \(high.rounded().degrees) · low \(low.rounded().degrees)")
                        }
                    }
                    .font(.system(size: 16)).foregroundStyle(Theme.secondary)
                }
            }
            hourly
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(rows.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rows[index].label).font(.system(size: 14)).foregroundStyle(Theme.secondary)
                        Text(verbatim: rows[index].value).font(.system(size: 24, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(verbatim: rows[index].note).font(.system(size: 14)).foregroundStyle(Theme.secondary).lineLimit(2)
                    }
                    .padding(.vertical, 14).padding(.horizontal, 16)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .card(padding: 0, cornerRadius: 18)
                }
            }
            if let wet = forecast.wetHours() {
                Label {
                    Text(verbatim: wet.text).font(.system(size: 17))
                } icon: {
                    Image(systemName: "mic").foregroundStyle(Theme.teal)
                }
                .padding(.vertical, 16).padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.tealBackground, in: .rect(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.tealBorder))
            }
        }
    }

    private var hourly: some View {
        let hours = forecast.hours(6)
        return HStack(spacing: 4) {
            ForEach(hours, id: \.self) { index in
                VStack(spacing: 10) {
                    Group {
                        if index == hours.first { Text("Now") } else { Text(forecast.hourly.time[index], format: .dateTime.hour().minute()) }
                    }
                    .font(.system(size: 15)).foregroundStyle(Theme.secondary)
                    WeatherIcon(condition: forecast.hourCondition(index)).frame(height: 26)
                    Text(verbatim: forecast.hourly.temperature[index].rounded().degrees).font(.system(size: 20, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 16).padding(.horizontal, 8)
        .card(padding: 0)
    }

    private var details: [Detail] {
        let current = forecast.current
        let daily = forecast.daily
        let change = forecast.pressureChange()
        let gusts = Int(current.windGusts.rounded())
        var rows: [Detail] = [
            ("Wind", Self.measure(current.windSpeed, UnitSpeed.kilometersPerHour),
             String(localized: "\(Self.direction(current.windDirection)), gusts up to \(gusts)")),
            ("Humidity", "\(Int(current.humidity.rounded()))%", String(localized: "Dew point \(current.dewPoint.rounded().degrees)")),
            ("Pressure", Self.measure(current.pressure, UnitPressure.hectopascals),
             change > 1 ? String(localized: "Rising") : change < -1 ? String(localized: "Falling") : String(localized: "Steady")),
            ("Precipitation", "\(daily.rainChance.first.flatMap { $0 } ?? 0)%",
             String(localized: "\(Self.measure(daily.rainSum.first.flatMap { $0 } ?? 0, UnitLength.millimeters)) today")),
            ("UV index", current.uvIndex.map { "\(Int($0.rounded()))" } ?? "-", current.uvIndex.map(Self.uvLevel) ?? ""),
        ]
        if let sunrise = daily.sunrise.first, let sunset = daily.sunset.first {
            rows.append(("Sun", sunrise.formatted(date: .omitted, time: .shortened),
                         String(localized: "Sunset at \(sunset.formatted(date: .omitted, time: .shortened))")))
        }
        return rows
    }

    // MARK: Ten days

    private var days: some View {
        let daily = forecast.daily
        let low = daily.low.min() ?? 0
        let span = max((daily.high.max() ?? 1) - low, 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("10-day forecast").blockTitle()
            VStack(spacing: 4) {
                ForEach(daily.time.indices, id: \.self) { index in
                    let chance = daily.rainChance[index] ?? 0
                    HStack(spacing: wide ? 16 : 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Group {
                                if index == 0 { Text("Today") } else { Text(verbatim: daily.time[index].formatted(.dateTime.weekday(.abbreviated)).capitalizedFirst) }
                            }
                            .font(.system(size: 18, weight: index == 0 ? .semibold : .medium))
                            Text(daily.time[index], format: .dateTime.day().month(.abbreviated)).font(.system(size: 14)).foregroundStyle(Theme.secondary)
                        }
                        .frame(width: wide ? 96 : 64, alignment: .leading)
                        WeatherIcon(condition: Forecast.condition(daily.code[index])).frame(width: 28)
                        Text(verbatim: chance >= 20 ? "\(chance)%" : "").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.blue)
                            .frame(width: wide ? 44 : 36, alignment: .leading)
                        Text(verbatim: daily.low[index].rounded().degrees).font(.system(size: 18)).foregroundStyle(Theme.secondary)
                            .monospacedDigit().frame(width: 40, alignment: .trailing)
                        GeometryReader { bar in
                            Capsule().fill(Theme.track)
                                .overlay(alignment: .leading) {
                                    Capsule().fill(LinearGradient(colors: [Theme.blue, Theme.amber], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(8, bar.size.width * (daily.high[index] - daily.low[index]) / span))
                                        .offset(x: bar.size.width * (daily.low[index] - low) / span)
                                }
                        }
                        .frame(height: 8)
                        Text(verbatim: daily.high[index].rounded().degrees).font(.system(size: 18, weight: .semibold))
                            .monospacedDigit().frame(width: 40, alignment: .leading)
                    }
                    .padding(.horizontal, wide ? 14 : 8)
                    .frame(height: 60)
                    .background(index == 0 ? Theme.highlight : .clear, in: .rect(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: Formatting

    private static func measure<U: Dimension>(_ value: Double, _ unit: U) -> String {
        Measurement(value: value, unit: unit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    private static func direction(_ degrees: Double) -> String {
        String(localized: String.LocalizationValue("wind." + Forecast.compass(degrees)))
    }

    private static func uvLevel(_ index: Double) -> String {
        switch index {
        case ..<3: String(localized: "Low")
        case ..<6: String(localized: "Moderate")
        case ..<8: String(localized: "High")
        case ..<11: String(localized: "Very high")
        default: String(localized: "Extreme")
        }
    }
}
