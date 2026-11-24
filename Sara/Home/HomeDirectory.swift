import Foundation

@MainActor enum HomeDirectory {
    static let tools = try! JSONSerialization.jsonObject(
        with: Data(contentsOf: Bundle.main.url(forResource: "HomeTools", withExtension: "json")!)) as! [[String: Any]]

    private static var devices: [(id: String, name: String, area: String?)] = []
    private static var entities: [String: (device: String?, area: String?)] = [:]
    private static var loaded = Date.distantPast

    static func index() async -> String? {
        guard await load() else { return nil }
        let byArea = Dictionary(grouping: devices) { $0.area ?? "" }
        return byArea.keys.sorted { ($0.isEmpty ? 1 : 0, $0) < ($1.isEmpty ? 1 : 0, $1) }.map { area in
            (area.isEmpty ? "No area" : area) + ": " + byArea[area, default: []].map(\.name).sorted().joined(separator: "; ")
        }.joined(separator: "\n")
    }

    static func run(_ name: String, _ args: [String: Any]) async -> String? {
        guard ["home_details", "home_history"].contains(name) else { return nil }
        guard let api = HomeAssistant.saved else { return "error: Home Assistant is not set up" }
        return name == "home_details" ? await details(args["name"] as? String ?? "", api) : await history(args, api)
    }

    private static func details(_ query: String, _ api: HomeAssistant) async -> String {
        let wanted = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return "error: no name" }
        guard await load(), let states = try? await api.states() else { return "error: Home Assistant is unreachable" }
        let deviceNames = Dictionary(devices.map { ($0.id, $0.name) }) { first, _ in first }
        func fields(_ id: String) -> [String] {
            [entities[id]?.device.flatMap { deviceNames[$0] }, entities[id]?.area].compactMap { $0?.lowercased() }
        }
        var ids = states.keys.filter { fields($0).contains(wanted) }
        if ids.isEmpty {
            ids = states.keys.filter { id in
                let friendly = (states[id]?["attributes"] as? [String: Any])?["friendly_name"] as? String ?? ""
                return (fields(id) + [id, friendly.lowercased()]).contains { $0.contains(wanted) }
            }
        }
        guard !ids.isEmpty else { return "nothing matches \(query)" }
        guard ids.count <= 150 else { return "error: \(ids.count) entities match \(query), name one device" }
        let groups = Dictionary(grouping: ids) { entities[$0]?.device ?? "" }
        let order = groups.keys.sorted { (deviceNames[$0] ?? "~") < (deviceNames[$1] ?? "~") }
        return order.map { device -> String in
            var place = "Without a device"
            if let found = devices.first(where: { $0.id == device }) {
                place = found.name + (found.area.map { " (\($0))" } ?? "")
            }
            let lines = groups[device, default: []].sorted().map { line($0, states[$0] ?? [:]) }
            return place + ":\n" + lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private static func history(_ args: [String: Any], _ api: HomeAssistant) async -> String {
        let ids = (args["entity_ids"] as? [String] ?? []).filter { $0.range(of: #"^[a-z0-9_]+\.[a-z0-9_]+$"#, options: .regularExpression) != nil }
        guard (1...10).contains(ids.count) else { return "error: give 1 to 10 entity ids" }
        guard let from = HomeHistory.date(args["from"] as? String ?? "") else { return "error: bad from" }
        let end = args["to"] as? String ?? "now"
        guard let until = end == "now" ? Date.now : HomeHistory.date(end), from < until else { return "error: bad to" }
        let to = min(until, Date.now)
        let hourly = args["period"] as? String == "hour"
        guard to.timeIntervalSince(from) <= (hourly ? 3 : 31) * 86_400 else { return "error: at most 3 days by hour or 31 days by day" }
        guard let history = try? await api.history(ids, from: from, to: to) else { return "error: Home Assistant is unreachable" }
        return ids.map { id in
            let lines = HomeHistory.summary(history[id] ?? [], from: from, to: to, hourly: hourly)
            return id + ":\n" + (lines.isEmpty ? "no history" : lines.joined(separator: "\n"))
        }.joined(separator: "\n\n")
    }

    private static func line(_ id: String, _ state: [String: Any]) -> String {
        let attributes = state["attributes"] as? [String: Any] ?? [:]
        let extra = attributes.keys.sorted().compactMap { key -> String? in
            guard !hidden.contains(key), !key.contains("token") else { return nil }
            switch attributes[key] {
            case let text as String where text.count <= 60: return "\(key): \(text)"
            case let number as NSNumber: return "\(key): \(number)"
            default: return nil
            }
        }
        var text = "\(id): \(attributes["friendly_name"] as? String ?? id) = \(state["state"] as? String ?? "")"
        if let unit = attributes["unit_of_measurement"] as? String { text += " \(unit)" }
        if !extra.isEmpty { text += " (\(extra.joined(separator: ", ")))" }
        return text
    }

    private static let hidden: Set = [
        "friendly_name", "unit_of_measurement", "icon", "entity_picture", "supported_features", "device_class", "state_class",
        "attribution", "latitude", "longitude", "gps_accuracy", "altitude", "restored", "editable", "id", "user_id",
    ]

    private static func load() async -> Bool {
        if Date.now.timeIntervalSince(loaded) < 600 { return true }
        let url = UserDefaults.standard.string(forKey: "haURL") ?? ""
        guard !url.isEmpty, let results = try? await HomeAssistantSocket(baseURL: url, token: Keychain.get("haToken"))
            .call(["config/device_registry/list", "config/entity_registry/list_for_display", "config/area_registry/list"])
        else { return false }
        let areas = Dictionary((results[2] as? [[String: Any]] ?? []).compactMap { area in
            (area["area_id"] as? String).map { ($0, area["name"] as? String ?? $0) }
        }) { first, _ in first }
        devices = (results[0] as? [[String: Any]] ?? []).compactMap { device in
            guard let id = device["id"] as? String, !(device["disabled_by"] is String) else { return nil }
            let name = device["name_by_user"] as? String ?? device["name"] as? String ?? id
            return (id, name, (device["area_id"] as? String).flatMap { areas[$0] })
        }
        let deviceAreas = Dictionary(devices.map { ($0.id, $0.area) }) { first, _ in first }
        entities = Dictionary(((results[1] as? [String: Any])?["entities"] as? [[String: Any]] ?? []).compactMap { entity in
            guard let id = entity["ei"] as? String else { return nil }
            let device = entity["di"] as? String
            let area = (entity["ai"] as? String).flatMap { areas[$0] } ?? device.flatMap { deviceAreas[$0] ?? nil }
            return (id, (device, area))
        }) { first, _ in first }
        loaded = .now
        return true
    }
}
