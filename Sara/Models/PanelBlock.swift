import Foundation

/// One block of the panel: a room with tiles, a slider, running devices or thermostats.
struct PanelBlock: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case room, slider, running, climate, list

        var name: LocalizedStringResource {
            switch self {
            case .room: "Room"
            case .slider: "Slider"
            case .running: "Running devices"
            case .climate: "Thermostats"
            case .list: "List"
            }
        }

        /// Entity domains that make sense as the main entity of an item in this block.
        var domains: [String] {
            switch self {
            case .room: ["light", "switch", "fan", "input_boolean", "scene", "script", "yandex"]
            case .slider: ["media_player", "light", "sensor", "number", "input_number", "yandex"]
            case .running: ["sensor"]
            case .climate: ["climate", "yandex"]
            case .list: ["todo"]
            }
        }
    }

    let id = UUID()
    var kind: Kind
    var title: String
    /// 0 is the left column, 1 the right one. Narrow screens show one column.
    var column = 0
    var items: [PanelItem] = []

    enum CodingKeys: String, CodingKey {
        case kind, title, column, items
    }
}
