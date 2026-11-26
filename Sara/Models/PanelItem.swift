import Foundation

/// One thing on the panel: a tile, a slider, a running device or a thermostat.
struct PanelItem: Codable, Identifiable, Equatable {
    let id = UUID()
    /// Tile to toggle, slider value, thermostat, or the remaining-time sensor of a running device.
    var entity: String
    /// Shown instead of the entity's name.
    var name: String?
    /// SF Symbol for a running device.
    var icon: String?
    /// Slider: a script that sets the value, and the script field that takes it.
    var script: String?
    var field: String?
    /// Running device: a sensor that is "on" or "running" while it works. Needed when the remaining-time
    /// sensor keeps a value at rest (a dryer reports its program length while idle).
    var active: String?
    /// Running device: progress in percent, finish time, and a detail line (program, file name).
    var progress: String?
    var end: String?
    var detail: String?

    enum CodingKeys: String, CodingKey {
        case entity, name, icon, script, field, active, progress, end, detail
    }

    static let remainingEndings = ["remaining_time", "time_remaining", "time_left", "timetoend", "remaining_drying_time"]

    var base: String? {
        let id = Self.objectID(entity)
        return Self.remainingEndings.first(where: id.hasSuffix).map { String(id.dropLast($0.count)) }
    }

    static func domain(_ entity: String) -> String { entity.components(separatedBy: ".").first ?? "" }
    static func objectID(_ entity: String) -> String { entity.components(separatedBy: ".").dropFirst().joined(separator: ".") }
}
