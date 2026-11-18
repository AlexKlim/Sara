import Foundation

/// Open-Meteo forecast for the home: now, by hour and by day. Times come as unix seconds.
struct Forecast: Decodable {
    let current: Current
    let hourly: Hourly
    let daily: Daily

    struct Current: Decodable {
        let temperature, feelsLike, humidity, dewPoint, pressure, windSpeed, windDirection, windGusts: Double
        let uvIndex: Double?
        let code, isDay: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m", feelsLike = "apparent_temperature", humidity = "relative_humidity_2m"
            case dewPoint = "dew_point_2m", pressure = "pressure_msl", windSpeed = "wind_speed_10m"
            case windDirection = "wind_direction_10m", windGusts = "wind_gusts_10m", uvIndex = "uv_index"
            case code = "weather_code", isDay = "is_day"
        }
    }

    struct Hourly: Decodable {
        let time: [Date]
        let temperature, pressure: [Double]
        let code, isDay: [Int]
        let rainChance: [Int?]

        enum CodingKeys: String, CodingKey {
            case time, temperature = "temperature_2m", pressure = "pressure_msl", code = "weather_code", isDay = "is_day"
            case rainChance = "precipitation_probability"
        }
    }

    struct Daily: Decodable {
        let time, sunrise, sunset: [Date]
        let code: [Int]
        let high, low: [Double]
        let rainSum: [Double?]
        let rainChance: [Int?]

        enum CodingKeys: String, CodingKey {
            case time, sunrise, sunset, code = "weather_code", high = "temperature_2m_max", low = "temperature_2m_min"
            case rainSum = "precipitation_sum", rainChance = "precipitation_probability_max"
        }
    }

    /// Hours with rain or snow likely, to say "rain tomorrow from 8 to 14".
    struct WetHours: Equatable {
        let start, end: Date
        let snow: Bool

        var text: String {
            let from = start.formatted(.dateTime.hour())
            let to = end.formatted(.dateTime.hour())
            return switch (snow, Calendar.current.isDateInToday(start)) {
            case (false, true): String(localized: "Rain today from \(from) to \(to)")
            case (false, false): String(localized: "Rain tomorrow from \(from) to \(to)")
            case (true, true): String(localized: "Snow today from \(from) to \(to)")
            case (true, false): String(localized: "Snow tomorrow from \(from) to \(to)")
            }
        }
    }

    static func url(latitude: Double, longitude: Double) -> URL? {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        parts?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,dew_point_2m,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,pressure_msl,weather_code,is_day,precipitation_probability"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "10"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        return parts?.url
    }

    static func decode(_ data: Data) throws -> Forecast {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let forecast = try decoder.decode(Forecast.self, from: data)
        let hourly = forecast.hourly, daily = forecast.daily
        let hourlyCounts = [hourly.temperature.count, hourly.pressure.count, hourly.code.count, hourly.isDay.count, hourly.rainChance.count]
        let dailyCounts = [daily.sunrise.count, daily.sunset.count, daily.code.count, daily.high.count, daily.low.count,
                           daily.rainSum.count, daily.rainChance.count]
        guard hourlyCounts.allSatisfy({ $0 == hourly.time.count }), dailyCounts.allSatisfy({ $0 == daily.time.count }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Forecast series of different lengths"))
        }
        return forecast
    }

    static func condition(_ code: Int, day: Bool = true) -> String {
        switch code {
        case 0: day ? "sunny" : "clear-night"
        case 1, 2: "partlycloudy"
        case 3: "cloudy"
        case 45, 48: "fog"
        case 51...57, 61, 63, 80, 81: "rainy"
        case 65, 82: "pouring"
        case 66, 67: "snowy-rainy"
        case 71...77, 85, 86: "snowy"
        case 95, 97: "lightning-rainy"
        case 96, 99: "hail"
        default: "exceptional"
        }
    }

    var condition: String { Self.condition(current.code, day: current.isDay == 1) }

    func hourCondition(_ index: Int) -> String { Self.condition(hourly.code[index], day: hourly.isDay[index] == 1) }

    func hours(_ count: Int, from now: Date = .now) -> [Int] {
        guard let first = hourly.time.firstIndex(where: { $0 > now.addingTimeInterval(-3600) }) else { return [] }
        return Array(first..<min(first + count, hourly.time.count))
    }

    func pressureChange(from now: Date = .now) -> Double {
        let next = hours(4, from: now)
        guard let first = next.first, let last = next.last else { return 0 }
        return hourly.pressure[last] - hourly.pressure[first]
    }

    /// The first stretch of hours today or tomorrow with a 50% chance of rain or snow or more.
    func wetHours(from now: Date = .now, calendar: Calendar = .current) -> WetHours? {
        guard let dayAfter = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) else { return nil }
        let wet = hours(48, from: now).filter { hourly.time[$0] < dayAfter && (hourly.rainChance[$0] ?? 0) >= 50 }
        guard let first = wet.first else { return nil }
        var last = first
        for index in wet.dropFirst() {
            guard index == last + 1 else { break }
            last = index
        }
        return WetHours(start: hourly.time[first], end: hourly.time[last].addingTimeInterval(3600), snow: hourCondition(first).hasPrefix("snowy"))
    }

    static func compass(_ degrees: Double) -> String {
        ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Int((degrees / 45).rounded()) % 8]
    }

    func summary(from now: Date = .now) -> String {
        func celsius(_ value: Double) -> String { "\(Int(value.rounded()))°C" }
        let hour = Date.FormatStyle(date: .omitted, time: .shortened)
        var lines = [
            "Now: \(celsius(current.temperature)), feels like \(celsius(current.feelsLike)), \(condition), "
                + "wind \(Int(current.windSpeed.rounded())) km/h from \(Self.compass(current.windDirection)), "
                + "gusts \(Int(current.windGusts.rounded())) km/h, humidity \(Int(current.humidity.rounded()))%, UV \(current.uvIndex.map { "\(Int($0.rounded()))" } ?? "unknown")",
            "Next hours: " + hours(6, from: now).map { index in
                "\(hourly.time[index].formatted(hour)) \(celsius(hourly.temperature[index])) \(hourCondition(index)) precipitation \(hourly.rainChance[index] ?? 0)%"
            }.joined(separator: ", "),
        ]
        for index in daily.time.indices.prefix(7) {
            lines.append("\(daily.time[index].formatted(.dateTime.weekday(.wide).day().month(.wide))): "
                + "\(celsius(daily.low[index]))..\(celsius(daily.high[index])), \(Self.condition(daily.code[index])), "
                + "precipitation \(daily.rainChance[index] ?? 0)%, \((daily.rainSum[index] ?? 0).formatted(.number.precision(.fractionLength(0...1)))) mm, "
                + "sunrise \(daily.sunrise[index].formatted(hour)), sunset \(daily.sunset[index].formatted(hour))")
        }
        return "<weather>\n\(lines.joined(separator: "\n"))\n</weather>"
    }
}
