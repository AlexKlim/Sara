import Foundation

/// One block of the panel: a room with tiles, a slider, running devices, thermostats, a list or one device.
struct PanelBlock: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case room, slider, running, climate, list, device

        var name: LocalizedStringResource {
            switch self {
            case .room: "Room"
            case .slider: "Slider"
            case .running: "Running devices"
            case .climate: "Thermostats"
            case .list: "List"
            case .device: "Device"
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
            case .device: ["number", "input_number", "sensor", "binary_sensor", "switch", "input_boolean"]
            }
        }
    }

    let id = UUID()
    var kind: Kind
    var title: String
    /// 0 is the left column, 1 the right one. Narrow screens show one column.
    var column = 0
    var items: [PanelItem] = []

    /// All its states come from Home Assistant, so they are unknown while it is offline.
    /// Yandex devices and the app's own lists keep working, and so does a room with any of them.
    var usesHomeAssistant: Bool {
        !items.isEmpty && items.allSatisfy { kind == .list ? $0.entity.hasPrefix("todo.") : !$0.entity.hasPrefix("yandex.") }
    }

    enum CodingKeys: String, CodingKey {
        case kind, title, column, items
    }
}
