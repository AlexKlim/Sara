import UIKit

/// Sends the wall panel's battery to Home Assistant, so an automation can switch its charger plug.
@MainActor enum BatteryReporter {
    private static var started = false
    private static var registered = false
    private static var sending: Task<Void, Never>?
    private static var sent: [String: Any]?

    static func start() {
        guard !started else { return }
        started = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in queueSend() }
            }
        }
        queueSend()
    }

    private static func queueSend() {
        let previous = sending
        sending = Task {
            await previous?.value
            await send()
        }
    }

    private static func send() async {
        let level = UIDevice.current.batteryLevel
        guard let api = HomeAssistant.saved, level >= 0 else { return }
        let state: [String: Any] = [
            "state": Int((level * 100).rounded()),
            "attributes": ["charging": [.charging, .full].contains(UIDevice.current.batteryState)],
        ]
        guard !registered || !NSDictionary(dictionary: state).isEqual(to: sent ?? [:]) else { return }
        let sensor = state.merging(["unique_id": "battery_level", "type": "sensor"]) { $1 }
        do {
            let webhook = try await webhookID(api)
            if registered {
                try await api.webhook(webhook, ["type": "update_sensor_states", "data": [sensor]])
            } else {
                let registration = sensor.merging([
                    "name": "Battery", "device_class": "battery", "unit_of_measurement": "%",
                    "state_class": "measurement", "entity_category": "diagnostic",
                ]) { $1 }
                try await api.webhook(webhook, ["type": "register_sensor", "data": registration])
                registered = true
            }
            sent = state
        } catch {
            #if DEBUG
            print("[battery] not sent:", error)
            #endif
        }
    }

    private static func webhookID(_ api: HomeAssistant) async throws -> String {
        let saved = Keychain.get("batteryWebhookID")
        if !saved.isEmpty, UserDefaults.standard.string(forKey: "batteryWebhookURL") == api.baseURL { return saved }
        let device = UIDevice.current
        let id = try await api.registerMobileApp([
            "device_id": device.identifierForVendor?.uuidString ?? UUID().uuidString,
            "app_id": Bundle.main.bundleIdentifier ?? "org.sara-home.Sara",
            "app_name": "Sara",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "device_name": "Sara \(device.model)",
            "manufacturer": "Apple",
            "model": device.model,
            "os_name": device.systemName,
            "os_version": device.systemVersion,
            "supports_encryption": false,
        ])
        // The webhook id lets anyone call Home Assistant actions, so it is a secret of this device.
        Keychain.set("batteryWebhookID", id, synced: false)
        UserDefaults.standard.set(api.baseURL, forKey: "batteryWebhookURL")
        registered = false
        return id
    }
}
