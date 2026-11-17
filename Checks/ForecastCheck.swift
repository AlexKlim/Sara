import Foundation

@main
enum ForecastCheck {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let midnight = 1_800_000_000 - 1_800_000_000 % 86_400
        let hours = (0..<48).map { midnight + $0 * 3600 }
        let chance = hours.indices.map { $0 >= 32 && $0 < 38 || $0 == 40 ? 70 : 10 }
        let json = """
        {"current":{"temperature_2m":6.2,"apparent_temperature":3.1,"relative_humidity_2m":84,"dew_point_2m":3.4,
         "pressure_msl":1014.2,"wind_speed_10m":14,"wind_direction_10m":225,"wind_gusts_10m":25,"uv_index":null,
         "weather_code":3,"is_day":1},
         "hourly":{"time":\(hours),"temperature_2m":\(hours.map { _ in 5.0 }),"pressure_msl":\(hours.map { _ in 1014.0 }),
          "weather_code":\(hours.map { _ in 61 }),"is_day":\(hours.map { _ in 1 }),"precipitation_probability":\(chance)},
         "daily":{"time":[\(midnight)],"sunrise":[\(midnight + 25_000)],"sunset":[\(midnight + 56_000)],"weather_code":[3],
          "temperature_2m_max":[8],"temperature_2m_min":[2],"precipitation_sum":[null],"precipitation_probability_max":[null]}}
        """
        let forecast = try Forecast.decode(Data(json.utf8))
        assert(forecast.condition == "cloudy" && forecast.current.uvIndex == nil)
        assert(Forecast.condition(0, day: false) == "clear-night" && Forecast.condition(82) == "pouring")

        let morning = Date(timeIntervalSince1970: TimeInterval(midnight + 6 * 3600))
        assert(forecast.hours(6, from: morning).first == 6)
        let wet = forecast.wetHours(from: morning, calendar: calendar)
        assert(wet?.start == Date(timeIntervalSince1970: TimeInterval(hours[32])), "\(String(describing: wet))")
        assert(wet?.end == Date(timeIntervalSince1970: TimeInterval(hours[38])) && wet?.snow == false)
        print("Forecast OK")
    }
}
