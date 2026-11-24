import Foundation

/// What the main screen shows: a list of blocks. Stored as JSON in the app settings.
struct Panel: Codable, Equatable {
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
    /// thermostats and to-do lists on the right. The user edits it from there.
    static func build(from socket: HomeAssistantSocket) async throws -> Panel {
        let results = try await socket.call([
            "config/area_registry/list", "config/device_registry/list", "config/entity_registry/list_for_display",
        ])
        return build(
            areas: results[0] as? [[String: Any]] ?? [],
            devices: results[1] as? [[String: Any]] ?? [],
            entities: (results[2] as? [String: Any])?["entities"] as? [[String: Any]] ?? [])
    }

    /// A block for one device: setpoints first, then sensors, doors and switches. A sensor named like a setpoint
    /// (number.fridge_temperature and sensor.fridge_temperature) is shown as that setpoint's current value.
    static func block(device name: String, entities: [String]) -> PanelBlock {
        let order = PanelBlock.Kind.device.domains
        let setpoints = Set(entities.filter { $0.hasPrefix("number.") || $0.hasPrefix("input_number.") }.map(PanelItem.objectID))
        let items = entities
            .filter { !($0.hasPrefix("sensor.") && setpoints.contains(PanelItem.objectID($0))) }
            .sorted { (order.firstIndex(of: PanelItem.domain($0)) ?? 0, $0) < (order.firstIndex(of: PanelItem.domain($1)) ?? 0, $1) }
        return PanelBlock(kind: .device, title: name, column: 1, items: items.map { PanelItem(entity: $0) })
    }

    /// A device that reports how long it has left (a printer, a washer) is a running device. Its other sensors,
    /// when it has them, give the progress, the finish time, a detail line and whether it works now.
    static func runningItem(device name: String, entities: [String]) -> PanelItem? {
        let sorted = entities.sorted()
        func find(_ domain: String, _ endings: [String]) -> String? {
            for ending in endings {
                if let id = sorted.first(where: { PanelItem.domain($0) == domain && PanelItem.objectID($0).hasSuffix(ending) }) { return id }
            }
            return nil
        }
        guard let remaining = find("sensor", ["remaining_time", "time_remaining", "time_left", "timetoend"]) else { return nil }
        // Entity ids are Latin (transliterated from other languages), so they tell what kind of device it is.
        let kinds = [("print", "cube"), ("dish", "dishwasher"), ("posud", "dishwasher"), ("wash", "washer"), ("stiral", "washer"),
                     ("dry", "dryer"), ("sushil", "dryer")]
        return PanelItem(
            entity: remaining, name: name.isEmpty ? nil : name,
            icon: kinds.first { remaining.contains($0.0) }?.1,
            active: find("binary_sensor", ["_running", "_status"]) ?? find("sensor", ["print_status", "machine_state", "run_state", "operation_state", "appliancestate"]),
            progress: find("sensor", ["print_progress", "_progress"]),
            end: find("sensor", ["end_time", "finish_time", "completion_time"]),
            detail: find("sensor", ["task_name", "current_program"]) ?? find("select", ["programuid"]))
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
        for entity in entities {
            guard let id = entity["ei"] as? String, entity["hb"] as? Bool != true, entity["ec"] == nil else { continue }
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

        // Printers, washers and the like, at the top of the right column. They show only while they work.
        let deviceNames = Dictionary(devices.compactMap { d in
            (d["id"] as? String).map { ($0, d["name_by_user"] as? String ?? d["name"] as? String ?? "") }
        }) { a, _ in a }
        var byDevice: [String: [String]] = [:]
        for entity in entities {
            if let id = entity["ei"] as? String, let device = entity["di"] as? String { byDevice[device, default: []].append(id) }
        }
        let running = byDevice
            .map { (name: deviceNames[$0.key] ?? "", entities: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .compactMap { runningItem(device: $0.name, entities: $0.entities) }
        if !running.isEmpty {
            blocks.insert(PanelBlock(kind: .running, title: String(localized: "Running now"), column: 1, items: running), at: 0)
        }
        return Panel(blocks: blocks)
    }
}
