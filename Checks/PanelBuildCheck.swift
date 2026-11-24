import Foundation

@main
enum PanelBuildCheck {
    static func main() {
        let panel = Panel.build(HARegistry(
            areas: [HAArea(id: "zal", name: "Living room"), HAArea(id: "bath", name: "Bathroom"), HAArea(id: "empty", name: "Empty")],
            devices: [HADevice(id: "d1", areaID: "bath"), HADevice(id: "d2")],
            entities: [
                HAEntityEntry(id: "light.main", area: "zal"),
                HAEntityEntry(id: "switch.sync", area: "zal"),
                HAEntityEntry(id: "light.hidden", area: "zal", hidden: true),
                HAEntityEntry(id: "switch.child_lock", area: "zal", category: 0),
                HAEntityEntry(id: "climate.floor", device: "d1"),
                HAEntityEntry(id: "light.nowhere", device: "d2"),
                HAEntityEntry(id: "todo.shopping"),
            ]))
        assert(panel.blocks.map(\.title) == ["Living room", "Thermostats", ""], "\(panel.blocks.map(\.title))")
        assert(panel.blocks[2].kind == .list && panel.blocks[2].items.first?.entity == "todo.shopping")
        assert(panel.blocks[0].items.map(\.entity) == ["light.main", "switch.sync"])
        assert(panel.blocks[1].column == 1 && panel.blocks[1].items.first?.name == "Bathroom")
        print("Panel.build OK")

        // Running devices: found by their remaining-time sensor, with the device's other sensors filled in.
        let withRunning = Panel.build(HARegistry(
            devices: [HADevice(id: "p", name: "Printer"), HADevice(id: "w", name: "Washer", nameByUser: "My washer"), HADevice(id: "l", name: "Lamp")],
            entities: [
                HAEntityEntry(id: "sensor.kabinet_printer_remaining_time", device: "p"),
                HAEntityEntry(id: "sensor.kabinet_printer_print_progress", device: "p"),
                HAEntityEntry(id: "sensor.kabinet_printer_end_time", device: "p"),
                HAEntityEntry(id: "sensor.kabinet_printer_task_name", device: "p"),
                HAEntityEntry(id: "sensor.kabinet_printer_print_status", device: "p"),
                HAEntityEntry(id: "sensor.kabinet_printer_sd_card_status", device: "p"),
                HAEntityEntry(id: "sensor.tualet_stiralka_remaining_time", device: "w"),
                HAEntityEntry(id: "sensor.tualet_stiralka_program_phase", device: "w"),
                HAEntityEntry(id: "binary_sensor.tualet_stiralka_status", device: "w"),
                HAEntityEntry(id: "light.lamp", device: "l"),
            ]))
        assert(withRunning.blocks.first?.kind == .running && withRunning.blocks.first?.column == 1)
        let printer = withRunning.blocks[0].items[1], washer = withRunning.blocks[0].items[0]
        assert(washer.name == "My washer" && washer.icon == "washer" && washer.active == "binary_sensor.tualet_stiralka_status")
        assert(washer.detail == nil && washer.progress == nil)
        assert(printer.icon == "cube" && printer.active == "sensor.kabinet_printer_print_status")
        assert(printer.progress == "sensor.kabinet_printer_print_progress" && printer.end == "sensor.kabinet_printer_end_time")
        assert(printer.detail == "sensor.kabinet_printer_task_name")
        assert(Panel.runningItem(device: "Lamp", entities: ["light.lamp"]) == nil)
        let dishwasher = Panel.runningItem(device: "Dishwasher", entities: [
            "sensor.electrolux_dishwasher_timetoend", "sensor.electrolux_dishwasher_appliancestate",
            "select.electrolux_dishwasher_userselections_programuid", "sensor.electrolux_dishwasher_cyclephase",
        ])
        assert(dishwasher?.entity == "sensor.electrolux_dishwasher_timetoend" && dishwasher?.icon == "dishwasher")
        assert(dishwasher?.active == "sensor.electrolux_dishwasher_appliancestate")
        assert(dishwasher?.detail == "select.electrolux_dishwasher_userselections_programuid")
        var placed = Panel(blocks: [PanelBlock(kind: .room, title: "Kitchen")])
        placed.addRunning([dishwasher!])
        placed.addRunning([dishwasher!, washer])
        assert(placed.blocks.map(\.kind) == [.running, .room] && placed.blocks[0].column == 1)
        assert(placed.blocks[0].items.map(\.entity) == ["sensor.electrolux_dishwasher_timetoend", "sensor.tualet_stiralka_remaining_time"])
        print("Running devices OK")

        // Yandex: user/info in the shape of the docs.
        let info: [String: Any] = [
            "rooms": [["id": "r1", "name": "Kitchen"], ["id": "r2", "name": "Bathroom"]],
            "devices": [
                ["id": "lamp", "name": "Lamp", "room": "r1", "type": "devices.types.light", "capabilities": [
                    ["type": "devices.capabilities.on_off", "state": ["instance": "on", "value": true]],
                    ["type": "devices.capabilities.range", "state": ["instance": "brightness", "value": 50]],
                ]],
                ["id": "floor", "name": "Floor", "room": "r2", "type": "devices.types.thermostat", "capabilities": [
                    ["type": "devices.capabilities.on_off", "state": ["instance": "on", "value": false]],
                    ["type": "devices.capabilities.range", "state": ["instance": "temperature", "value": 28]],
                ], "properties": [["type": "devices.properties.float", "state": ["instance": "temperature", "value": 26.5]]]],
            ],
        ]
        let states = YandexHome.states(from: info)
        assert(states["yandex.lamp"]?.state == "on")
        assert(abs((states["yandex.lamp"]?.attributes["brightness"]?.double ?? 0) - 127.5) < 0.01)
        assert(states["yandex.floor"]?.attributes["current_temperature"]?.double == 26.5)
        let yandexPanel = Panel.build(fromYandex: info)
        assert(yandexPanel.blocks.map(\.title) == ["Kitchen", "Thermostats"], "\(yandexPanel.blocks.map(\.title))")
        assert(yandexPanel.blocks[0].items.map(\.entity) == ["yandex.lamp"])
        assert(yandexPanel.blocks[1].items.first?.name == "Bathroom")
        print("Yandex panel OK")
    }
}
