import Foundation

extension DateComponents {
    /// A 24-hour local time "HH:mm". Anything else, like "9:x:30" or "25:00", is refused.
    init?(clockTime: String) {
        let parts = clockTime.split(separator: ":", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 2, let hour = parts[0], let minute = parts[1],
              (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        self.init(hour: hour, minute: minute)
    }
}
