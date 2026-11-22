// Self-check for DeviSchedule: decoding DEVI time codes and finding the thermostat serial. Run from the repo root:
// swiftc -parse-as-library -o /tmp/devischedulecheck Sara/Models/DeviSchedule.swift Checks/DeviScheduleCheck.swift && /tmp/devischedulecheck
import Foundation

@main
enum DeviScheduleCheck {
    static func main() {
        // A real schedule read from a thermostat: weekdays 06:00-08:00 and 16:00-22:30, weekend 07:00-22:45.
        let schedule = DeviSchedule(json: #"{"MON":["8688","90d6"],"SAT":["87f6"],"SUN":["898f"],"FRI":["8098"]}"#)!
        assert(schedule.days.count == 7)
        assert(schedule.days[0] == [360..<480, 960..<1350])
        assert(schedule.days[1].isEmpty)
        assert(schedule.days[4] == [0..<1440])
        assert(schedule.days[5] == [420..<1365])
        assert(schedule.days[6] == [540..<900])
        assert(DeviSchedule(json: #"{"MON":["zz"]}"#)?.days[0] == [])
        assert(DeviSchedule(json: "unknown") == nil)
        assert(DeviSchedule.serial(of: "climate.devireg_10299072_devireg_smart_thermostat") == "10299072")
        assert(DeviSchedule.serial(of: "climate.living_room") == nil)
        print("DeviSchedule: ok")
    }
}
