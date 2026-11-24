import Foundation

enum HomeHistory {
    static func summary(_ samples: [(date: Date, state: String)], from: Date, to: Date, hourly: Bool,
                        calendar: Calendar = .current) -> [String] {
        let unit: Calendar.Component = hourly ? .hour : .day
        let label = DateFormatter()
        label.calendar = calendar
        label.timeZone = calendar.timeZone
        label.locale = Locale(identifier: "en_US_POSIX")
        label.dateFormat = hourly ? "yyyy-MM-dd HH:00" : "yyyy-MM-dd"
        var lines: [String] = []
        var start = calendar.dateInterval(of: unit, for: from)?.start ?? from
        while start < to, let next = calendar.date(byAdding: unit, value: 1, to: start) {
            if let line = bucket(samples, max(start, from), min(next, to)) { lines.append(label.string(from: start) + ": " + line) }
            start = next
        }
        return lines
    }

    static func date(_ text: String, calendar: Calendar = .current) -> Date? {
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = Locale(identifier: "en_US_POSIX")
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
            format.dateFormat = pattern
            if let date = format.date(from: text) { return date }
        }
        return nil
    }

    private static func bucket(_ samples: [(date: Date, state: String)], _ start: Date, _ end: Date) -> String? {
        var sum = 0.0, seconds = 0.0, low = Double.infinity, high = -Double.infinity
        var first: Double?, last: Double?
        var held: [String: Double] = [:]
        for (index, sample) in samples.enumerated() {
            let next = index + 1 < samples.count ? samples[index + 1].date : .distantFuture
            let span = min(next, end).timeIntervalSince(max(sample.date, start))
            guard span > 0 else { continue }
            if let value = Double(sample.state) {
                sum += value * span
                seconds += span
                low = min(low, value)
                high = max(high, value)
                if first == nil { first = value }
                last = value
            } else if !["unavailable", "unknown", ""].contains(sample.state) {
                held[sample.state, default: 0] += span
            }
        }
        if seconds > 0, let first, let last {
            return "mean \(number(sum / seconds)), min \(number(low)), max \(number(high)), "
                + "start \(number(first)), end \(number(last)), change \(number(last - first))"
        }
        guard !held.isEmpty else { return nil }
        return held.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map { "\($0.key) \(number($0.value / 3600)) h" }.joined(separator: ", ")
    }

    private static func number(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}
