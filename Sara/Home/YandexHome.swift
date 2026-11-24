import Foundation

/// Yandex Smart Home (Alice) through its user API, for homes without Home Assistant.
/// Docs: https://yandex.ru/dev/dialogs/smart-home/doc/ru/concepts/platform-protocol
struct YandexHome {
    let token: String

    static let tools = try! JSONSerialization.jsonObject(
        with: Data(contentsOf: Bundle.main.url(forResource: "YandexTools", withExtension: "json")!)) as! [[String: Any]]

    /// OAuth client id of the app registered at oauth.yandex.ru (iot:view, iot:control). Empty: token by hand only.
    static var clientID: String { Bundle.main.object(forInfoDictionaryKey: "YandexClientID") as? String ?? "" }

    /// Rooms, devices with capabilities and state, sensors, groups and scenarios.
    func info() async throws -> [String: Any] {
        try await request("GET", "/v1.0/user/info")
    }

    /// The whole home as compact text for Claude.
    func stateText() async throws -> String {
        let info = try await info()
        let rooms = Dictionary((info["rooms"] as? [[String: Any]] ?? []).compactMap { room in
            (room["id"] as? String).map { ($0, room["name"] as? String ?? "") }
        }) { first, _ in first }
        var lines = ["Devices (id | name | room | type | capabilities | sensors):"]
        for device in info["devices"] as? [[String: Any]] ?? [] {
            let capabilities = (device["capabilities"] as? [[String: Any]] ?? []).map(Self.describe).joined(separator: ", ")
            let sensors = (device["properties"] as? [[String: Any]] ?? []).map(Self.describe).joined(separator: ", ")
            let room = rooms[device["room"] as? String ?? ""] ?? "-"
            let type = (device["type"] as? String ?? "").replacingOccurrences(of: "devices.types.", with: "")
            lines.append("\(device["id"] ?? "") | \(device["name"] ?? "") | \(room) | \(type) | \(capabilities) | \(sensors)")
        }
        let scenarios = (info["scenarios"] as? [[String: Any]] ?? []).filter { $0["is_active"] as? Bool != false }
        if !scenarios.isEmpty {
            lines.append("Scenarios (id | name):")
            lines += scenarios.map { "\($0["id"] ?? "") | \($0["name"] ?? "")" }
        }
        return lines.joined(separator: "\n")
    }

    /// Runs yandex_device_action or yandex_scenario. Returns nil for any other tool.
    func run(_ tool: String, _ args: [String: Any]) async -> String? {
        do {
            switch tool {
            case "yandex_device_action":
                let actions = (args["actions"] as? [[String: Any]] ?? []).map { action -> [String: Any] in
                    ["type": "devices.capabilities." + (action["capability"] as? String ?? ""),
                     "state": ["instance": action["instance"] ?? "", "value": action["value"] ?? NSNull()]]
                }
                let reply = try await request("POST", "/v1.0/devices/actions", body: [
                    "devices": [["id": args["device_id"] as? String ?? "", "actions": actions]],
                ])
                // Each capability reports DONE or ERROR with a message.
                let results = (reply["devices"] as? [[String: Any]] ?? []).flatMap { $0["capabilities"] as? [[String: Any]] ?? [] }
                    .compactMap { (($0["state"] as? [String: Any])?["action_result"] as? [String: Any]) }
                    .map { "\($0["status"] ?? "?")\(($0["error_message"] as? String).map { ": \($0)" } ?? "")" }
                return results.isEmpty ? "done" : results.joined(separator: ", ")
            case "yandex_scenario":
                _ = try await request("POST", "/v1.0/scenarios/\(args["scenario_id"] as? String ?? "")/actions", body: [:])
                return "done"
            default:
                return nil
            }
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    /// Yandex devices as Home Assistant-like states, so the panel shows them like any entity:
    /// id "yandex.<device id>", state "on"/"off", friendly_name, brightness 0-255, temperature (target), current_temperature.
    static func states(from info: [String: Any]) -> [String: HAState] {
        var states: [String: HAState] = [:]
        for device in info["devices"] as? [[String: Any]] ?? [] {
            guard let id = device["id"] as? String else { continue }
            var attributes: [String: HAValue] = [
                "friendly_name": .string(device["name"] as? String ?? id), "yandex_type": .string(device["type"] as? String ?? ""),
            ]
            var state = "unknown"
            for capability in device["capabilities"] as? [[String: Any]] ?? [] {
                guard let current = capability["state"] as? [String: Any] else { continue }
                switch (capability["type"] as? String, current["instance"] as? String) {
                case ("devices.capabilities.on_off", "on"?): state = current["value"] as? Bool == true ? "on" : "off"
                case ("devices.capabilities.range", "brightness"?): attributes["brightness"] = .number(((current["value"] as? NSNumber)?.doubleValue ?? 0) * 2.55)
                case ("devices.capabilities.range", "temperature"?): attributes["temperature"] = (current["value"] as? NSNumber).map { .number($0.doubleValue) }
                default: break
                }
            }
            for property in device["properties"] as? [[String: Any]] ?? [] {
                if let current = property["state"] as? [String: Any], current["instance"] as? String == "temperature" {
                    attributes["current_temperature"] = (current["value"] as? NSNumber).map { .number($0.doubleValue) }
                }
            }
            states["yandex." + id] = HAState(state: state, attributes: attributes)
        }
        return states
    }

    /// "devices.capabilities.range" with state brightness 100 and range 1...100 -> "range/brightness=100 (1...100 percent)"
    private static func describe(_ item: [String: Any]) -> String {
        let type = (item["type"] as? String ?? "").components(separatedBy: ".").last ?? ""
        let state = item["state"] as? [String: Any]
        let parameters = item["parameters"] as? [String: Any] ?? [:]
        let instance = state?["instance"] as? String ?? parameters["instance"] as? String ?? ""
        var text = "\(type)/\(instance)=\(state?["value"].map { "\($0)" } ?? "?")"
        if let range = parameters["range"] as? [String: Any] { text += " (\(range["min"] ?? "")...\(range["max"] ?? ""))" }
        if let unit = parameters["unit"] as? String { text += " " + unit.replacingOccurrences(of: "unit.", with: "") }
        if let modes = parameters["modes"] as? [[String: Any]] { text += " [" + modes.compactMap { $0["value"] as? String }.joined(separator: "/") + "]" }
        return text
    }

    private func request(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.iot.yandex.net" + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200, json["status"] as? String == "ok" else {
            throw SaraError("Yandex: \(json["message"] as? String ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")")
        }
        return json
    }
}
