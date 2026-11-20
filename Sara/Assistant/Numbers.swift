import Foundation

/// Numeric settings of devices (number, input_number), such as a fridge temperature.
/// Home Assistant's tools for Claude can read them but have no command to set them.
enum Numbers {
    static let tools = try! JSONSerialization.jsonObject(
        with: Data(contentsOf: Bundle.main.url(forResource: "NumberTools", withExtension: "json")!)) as! [[String: Any]]

    /// nil: not this tool. Only a setting in `exposed`, the home state Home Assistant gives Claude, can be set.
    static func run(_ name: String, _ args: [String: Any], exposed: String) async -> String? {
        guard name == "set_number" else { return nil }
        guard let api = HomeAssistant.saved else { return "error: Home Assistant is not set up" }
        let wanted = args["name"] as? String ?? ""
        guard let value = args["value"] as? Double else { return "error: no value" }
        guard let states = try? await api.states() else { return "error: Home Assistant is unreachable" }
        let match = states.first { id, state in
            let title = (state["attributes"] as? [String: Any])?["friendly_name"] as? String ?? id
            return ["number", "input_number"].contains(PanelItem.domain(id))
                && (title.caseInsensitiveCompare(wanted) == .orderedSame || id == wanted)
                && exposed.contains(title)
        }
        guard let (id, state) = match else { return "error: no such number or input_number in home_state: \(wanted)" }
        let attributes = state["attributes"] as? [String: Any] ?? [:]
        if let low = attributes["min"] as? Double, let high = attributes["max"] as? Double, !(low...high).contains(value) {
            return "error: \(wanted) takes values from \(low) to \(high)"
        }
        do {
            try await api.call(PanelItem.domain(id), "set_value", ["entity_id": id, "value": value])
            return "ok"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }
}
