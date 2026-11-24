import Foundation

@main
enum HomeHistoryCheck {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let at = { HomeHistory.date($0, calendar: calendar)! }

        let counter = [(at("2026-11-14T20:00"), "10"), (at("2026-11-15T06:00"), "12"), (at("2026-11-15T18:00"), "unavailable"),
                       (at("2026-11-15T19:00"), "13.5")]
        let days = HomeHistory.summary(counter, from: at("2026-11-14"), to: at("2026-11-16"), hourly: false, calendar: calendar)
        assert(days == [
            "2026-11-14: mean 10, min 10, max 10, start 10, end 10, change 0",
            "2026-11-15: mean 11.8, min 10, max 13.5, start 10, end 13.5, change 3.5",
        ], "\(days)")

        let heating = [(at("2026-11-15T02:00"), "on"), (at("2026-11-15T02:30"), "off")]
        let hours = HomeHistory.summary(heating, from: at("2026-11-15T01:00"), to: at("2026-11-15T04:00"), hourly: true, calendar: calendar)
        assert(hours == ["2026-11-15 02:00: off 0.5 h, on 0.5 h", "2026-11-15 03:00: off 1 h"], "\(hours)")
        print("HomeHistory OK")
    }
}
