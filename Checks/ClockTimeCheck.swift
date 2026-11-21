// Self-check for DateComponents(clockTime:): only a valid HH:mm passes. Run from the repo root:
// swiftc -parse-as-library -o /tmp/clocktimecheck Sara/Models/ClockTime.swift Checks/ClockTimeCheck.swift && /tmp/clocktimecheck
import Foundation

@main
enum ClockTimeCheck {
    static func main() {
        assert(DateComponents(clockTime: "07:30") == DateComponents(hour: 7, minute: 30))
        assert(DateComponents(clockTime: "0:05") == DateComponents(hour: 0, minute: 5))
        assert(DateComponents(clockTime: "23:59") != nil)
        for bad in ["", "9", "09:x:30", "9:x", "24:00", "12:60", "-1:10", "12:", ":30", "12:30:00"] {
            assert(DateComponents(clockTime: bad) == nil, bad)
        }
        print("ClockTime: ok")
    }
}
