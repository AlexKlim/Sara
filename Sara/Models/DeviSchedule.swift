import Foundation

/// The weekly schedule a DEVI thermostat keeps itself, as the ha-devi-mqtt bridge reports it: comfort periods
/// per day. Outside them the thermostat holds the economy temperature.
struct DeviSchedule: Equatable {
    /// Comfort periods in minutes from midnight, Monday first.
    let days: [[Range<Int>]]

    /// `{"MON": ["8688", "90d6"], ...}`: each period is two DEVI time bytes in hex, start and end.
    init?(json: String) {
        guard let map = try? JSONDecoder().decode([String: [String]].self, from: Data(json.utf8)) else { return nil }
        days = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"].map { day in
            (map[day] ?? []).compactMap { code in
                guard code.count == 4, let value = UInt16(code, radix: 16) else { return nil }
                let start = Self.minutes(UInt8(value >> 8)), end = Self.minutes(UInt8(value & 0xff))
                return start < end ? start..<end : nil
            }
        }
    }

    /// A DEVI time byte: 0x80, the quarter of the hour in bits 5-6, the hour (24 is the end of the day) in the low 5 bits.
    static func minutes(_ byte: UInt8) -> Int { Int(byte & 0x1f) * 60 + Int(byte >> 5 & 3) * 15 }

    /// The serial number in the bridge's climate entity id, climate.devireg_<serial>_devireg_smart_thermostat.
    static func serial(of climate: String) -> String? {
        let parts = climate.split(separator: "_")
        guard climate.hasPrefix("climate.devireg_"), parts.count > 1, Int(parts[1]) != nil else { return nil }
        return String(parts[1])
    }

    static func sensor(serial: String) -> String { "sensor.devireg_\(serial)_week_schedule_json" }
}
