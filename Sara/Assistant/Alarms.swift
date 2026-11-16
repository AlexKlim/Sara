import Foundation
import UserNotifications

/// Timers and alarms as local notifications: iOS keeps them across app restarts and rings in the background.
/// While the app is on screen, `onFire` gets the label so Sara can say it and show a card.
@MainActor @Observable final class Alarms: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Alarms()
    /// What is set now, soonest first. Shown on the panel.
    private(set) var pending: [PendingAlarm] = []
    /// Called with the label when a timer or alarm rings while the app is in the foreground.
    var onFire: ((String) -> Void)?
    private let center = UNUserNotificationCenter.current()

    static let tools = try! JSONSerialization.jsonObject(
        with: Data(contentsOf: Bundle.main.url(forResource: "AlarmTools", withExtension: "json")!)) as! [[String: Any]]

    /// Takes over notification handling and keeps `pending` fresh (timers that rang in the background drop out).
    func start() {
        center.delegate = self
        Task { [weak self] in
            while let self {
                await self.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func refresh() async {
        pending = await center.pendingNotificationRequests().compactMap { request in
            let timer = request.trigger as? UNTimeIntervalNotificationTrigger
            guard let date = timer?.nextTriggerDate() ?? (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            else { return nil }
            return PendingAlarm(id: request.identifier, label: request.content.body, fireDate: date, isTimer: timer != nil)
        }
        .sorted { $0.fireDate < $1.fireDate }
    }

    func cancel(_ id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        Task { await refresh() }
    }

    /// Runs one of the alarm tools. Returns nil for any other tool.
    func run(_ tool: String, _ args: [String: Any]) async -> String? {
        let label = args["label"] as? String ?? ""
        switch tool {
        case "set_timer":
            let minutes = args["minutes"] as? Double ?? 0
            guard minutes > 0 else { return "error: minutes must be positive" }
            return await schedule(label, UNTimeIntervalNotificationTrigger(timeInterval: minutes * 60, repeats: false))
        case "set_alarm":
            let parts = (args["time"] as? String ?? "").split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return "error: time must be HH:mm" }
            let when = DateComponents(hour: parts[0], minute: parts[1])
            return await schedule(label, UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
        case "list_timers":
            let pending = await center.pendingNotificationRequests()
            guard !pending.isEmpty else { return "none" }
            return pending.map { request in
                let when = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                    ?? (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                return "\(request.identifier): \(request.content.body) at \(when?.formatted(date: .abbreviated, time: .shortened) ?? "?")"
            }.joined(separator: "\n")
        case "cancel_timer":
            let id = args["id"] as? String ?? ""
            if id == "all" { center.removeAllPendingNotificationRequests() } else { center.removePendingNotificationRequests(withIdentifiers: [id]) }
            await refresh()
            return "cancelled"
        default:
            return nil
        }
    }

    private func schedule(_ label: String, _ trigger: UNNotificationTrigger) async -> String {
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
            return "error: notifications are not allowed for Sara in iOS Settings"
        }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Sara")
        content.body = label.isEmpty ? String(localized: "Time is up") : label
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let id = String(UUID().uuidString.prefix(8))
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        } catch {
            return "error: \(error.localizedDescription)"
        }
        await refresh()
        let when = (trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
            ?? (trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        return "set, id \(id), rings at \(when?.formatted(date: .abbreviated, time: .shortened) ?? "?")"
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        let body = notification.request.content.body
        await MainActor.run { onFire?(body) }
        await refresh()
        return [.banner, .sound]
    }
}
