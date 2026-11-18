import UIKit

/// Sends the wall panel's battery to Home Assistant, so an automation can switch its charger plug.
@MainActor enum BatteryReporter {
    private static var started = false
    private static var registered = false
    private static var sending: Task<Void, Never>?
    private static var sent: [String: Any]?
    private static var retry: Task<Void, Never>?

    static func start() {
        guard !started else { return }
        started = true
        UIDevice.current.isBatteryMonitoringEnabled = true
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in report() }
            }
        }
        report()
    }

    /// Sends the battery now, after the ones already on their way: also when Home Assistant gets set up.
    static func report() {
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
                let reply = try await api.webhook(webhook, ["type": "update_sensor_states", "data": [sensor]])
                guard !reply.isEmpty else { throw HomeAssistant.StatusError(status: 410) }
                guard (reply["battery_level"] as? [String: Any])?["success"] as? Bool == true else {
                    registered = false
                    throw SaraError("Sensor not registered")
                }
            } else {
                let registration = sensor.merging([
                    "name": "Battery", "device_class": "battery", "unit_of_measurement": "%",
                    "state_class": "measurement", "entity_category": "diagnostic",
                ]) { $1 }
                let reply = try await api.webhook(webhook, ["type": "register_sensor", "data": registration])
                guard reply["success"] as? Bool == true else { throw HomeAssistant.StatusError(status: 410) }
                registered = true
            }
            sent = state
        } catch {
            // 410: the device was deleted in Home Assistant, so the next send registers it again.
            if (error as? HomeAssistant.StatusError)?.status == 410 {
                Keychain.set("batteryWebhookID", "", synced: false)
                registered = false
            }
            #if DEBUG
            print("[battery] not sent:", (error as NSError).domain, (error as NSError).code)
            #endif
            retry?.cancel()
            retry = Task {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled { report() }
            }
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
