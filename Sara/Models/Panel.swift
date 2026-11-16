import Foundation

/// What the main screen shows: the weather entity and a list of blocks. Stored as JSON in the app settings.
struct Panel: Codable, Equatable {
    var weather: String?
    var blocks: [PanelBlock] = []

    static func load() -> Panel {
        decoded(UserDefaults.standard.data(forKey: "panel"))
    }

    /// The saved panel, else the bundled personal layout, else empty.
    static func decoded(_ data: Data?) -> Panel {
        data.flatMap { try? JSONDecoder().decode(Panel.self, from: $0) } ?? bundled ?? Panel()
    }

    var listNames: [String] { blocks.filter { $0.kind == .list }.map(\.title) }

    /// A list Sara created shows up on the panel, in the right column.
    static func addList(_ name: String) {
        var panel = load()
        guard !panel.listNames.contains(name) else { return }
        panel.blocks.append(PanelBlock(kind: .list, title: name, column: 1))
        panel.save()
    }

    static func removeList(_ name: String) {
        var panel = load()
        panel.blocks.removeAll { $0.kind == .list && $0.title == name }
        panel.save()
    }

    /// A personal layout can ship as Resources/Panel.local.json. It is git-ignored.
    static var bundled: Panel? {
        guard let url = Bundle.main.url(forResource: "Panel.local", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Panel.self, from: data)
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "panel")
    }

    /// A first layout from Home Assistant: a room block per area with its lights, switches and fans,
    /// thermostats on the right, and the weather. The user edits it from there.
    static func build(from socket: HomeAssistantSocket) async throws -> Panel {
        let results = try await socket.call([
            "config/area_registry/list", "config/device_registry/list", "config/entity_registry/list_for_display",
        ])
        return build(
            areas: results[0] as? [[String: Any]] ?? [],
            devices: results[1] as? [[String: Any]] ?? [],
            entities: (results[2] as? [String: Any])?["entities"] as? [[String: Any]] ?? [])
    }

    /// A first layout from Yandex Smart Home: a room block per room with its switchable devices, thermostats on the right.
    static func build(fromYandex info: [String: Any]) -> Panel {
        let devices = info["devices"] as? [[String: Any]] ?? []
        var blocks: [PanelBlock] = []
        var thermostats: [PanelItem] = []
        let rooms = (info["rooms"] as? [[String: Any]] ?? [])
            .sorted { ($0["name"] as? String ?? "").localizedStandardCompare($1["name"] as? String ?? "") == .orderedAscending }
        for room in rooms {
            let inRoom = devices.filter { $0["room"] as? String == room["id"] as? String }
            let switchable = inRoom.filter { device in
                (device["capabilities"] as? [[String: Any]] ?? []).contains { $0["type"] as? String == "devices.capabilities.on_off" }
                    && device["type"] as? String != "devices.types.thermostat"
            }
            if !switchable.isEmpty {
                blocks.append(PanelBlock(kind: .room, title: room["name"] as? String ?? "",
                                         items: switchable.compactMap { ($0["id"] as? String).map { PanelItem(entity: "yandex." + $0) } }))
            }
            thermostats += inRoom.filter { ($0["type"] as? String ?? "").hasPrefix("devices.types.thermostat") }
                .compactMap { ($0["id"] as? String).map { PanelItem(entity: "yandex." + $0, name: room["name"] as? String) } }
        }
        if !thermostats.isEmpty {
            blocks.append(PanelBlock(kind: .climate, title: String(localized: "Thermostats"), column: 1, items: thermostats))
        }
        return Panel(blocks: blocks)
    }

    /// `entities` use the compact keys of list_for_display: ei entity id, ai area, di device, hb hidden, ec category.
    static func build(areas: [[String: Any]], devices: [[String: Any]], entities: [[String: Any]]) -> Panel {
        let deviceArea = Dictionary(devices.compactMap { d in (d["id"] as? String).map { ($0, d["area_id"] as? String) } }) { a, _ in a }
        var byArea: [String: [String]] = [:]
        var weather: String?
        for entity in entities {
            guard let id = entity["ei"] as? String, entity["hb"] as? Bool != true, entity["ec"] == nil else { continue }
            if weather == nil, id.hasPrefix("weather.") { weather = id }
            let area = entity["ai"] as? String ?? (entity["di"] as? String).flatMap { deviceArea[$0] ?? nil }
            if let area { byArea[area, default: []].append(id) }
        }

        let named = areas.compactMap { a in (a["area_id"] as? String).map { ($0, a["name"] as? String ?? $0) } }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
        var blocks: [PanelBlock] = []
        var thermostats: [PanelItem] = []
        // To-do lists usually have no area: take them all.
        var lists = entities.compactMap { $0["ei"] as? String }.filter { id in id.hasPrefix("todo.") && !byArea.values.contains { $0.contains(id) } }
        for (area, name) in named {
            let ids = (byArea[area] ?? []).sorted()
            let tiles = ids.filter { $0.hasPrefix("light.") || $0.hasPrefix("switch.") || $0.hasPrefix("fan.") }
            lists += ids.filter { $0.hasPrefix("todo.") }
            if !tiles.isEmpty {
                blocks.append(PanelBlock(kind: .room, title: name, items: tiles.map { PanelItem(entity: $0) }))
            }
            thermostats += ids.filter { $0.hasPrefix("climate.") }.map { PanelItem(entity: $0, name: name) }
        }
        if !thermostats.isEmpty {
            blocks.append(PanelBlock(kind: .climate, title: String(localized: "Thermostats"), column: 1, items: thermostats))
        }
        blocks += lists.map { PanelBlock(kind: .list, title: "", column: 1, items: [PanelItem(entity: $0)]) }
        return Panel(weather: weather, blocks: blocks)
    }
}
