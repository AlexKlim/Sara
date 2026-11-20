import Foundation

/// A Home Assistant device that is not on the panel yet.
struct NewDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let area: String?
    /// What a device block can show of it: setpoints, sensors, switches.
    let entities: [String]
    let created: Date
}
