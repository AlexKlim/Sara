import Foundation
import UserNotifications

/// Timers, alarms and scheduled commands as local notifications: iOS keeps them across app restarts and rings
/// in the background. While the app is on screen, `onFire` gets the label so Sara can say it and show a card,
/// and `onCommand` gets a scheduled command to carry out. In the background a command can't run:
/// its notification then tells the user it was not done.
@MainActor @Observable final class Alarms: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Alarms()
    /// What is set now, soonest first. Shown on the panel.
    private(set) var pending: [PendingAlarm] = []
    /// Called with the label when a timer or alarm rings while the app is in the foreground.
    var onFire: ((String) -> Void)?
    /// Called with a scheduled command when it is due while the app is in the foreground.
    var onCommand: ((String) -> Void)?
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
            return PendingAlarm(id: request.identifier, label: request.content.body, fireDate: date, isTimer: timer != nil,
                                isCommand: request.content.userInfo[Self.commandKey] != nil)
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
            guard let when = DateComponents(clockTime: args["time"] as? String ?? "") else { return "error: time must be HH:mm" }
            return await schedule(label, UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
        case "schedule_command":
            let command = args["command"] as? String ?? ""
            guard !command.isEmpty else { return "error: command is empty" }
            let time = args["time"] as? String ?? ""
            let weekdays = args["weekdays"] as? [String] ?? []
            if !weekdays.isEmpty {
                guard var when = DateComponents(clockTime: time) else { return "error: a weekly command needs time HH:mm" }
                let id = String(UUID().uuidString.prefix(8))
                var results: [String] = []
                for day in weekdays {
                    // Calendar weekdays count from Sunday = 1.
                    guard let index = Self.weekdays.firstIndex(of: day) else { return "error: unknown weekday \(day)" }
                    when.weekday = index + 1
                    results.append(await schedule(command, UNCalendarNotificationTrigger(dateMatching: when, repeats: true), command: true, id: "\(id)-\(day)"))
                }
                return results.joined(separator: "\n")
            }
            if !time.isEmpty {
                guard let when = DateComponents(clockTime: time) else { return "error: time must be HH:mm" }
                return await schedule(command, UNCalendarNotificationTrigger(dateMatching: when, repeats: false), command: true)
            }
            let minutes = args["minutes"] as? Double ?? 0
            guard minutes > 0 else { return "error: give minutes or time" }
            return await schedule(command, UNTimeIntervalNotificationTrigger(timeInterval: minutes * 60, repeats: false), command: true)
        case "list_timers":
            let pending = await center.pendingNotificationRequests()
            guard !pending.isEmpty else { return "none" }
            return pending.map { request in
                let when = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                    ?? (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                let kind = request.content.userInfo[Self.commandKey] == nil ? "timer" : request.trigger?.repeats == true ? "weekly command" : "command"
                return "\(request.identifier) (\(kind)): \(request.content.body) at \(when?.formatted(date: .abbreviated, time: .shortened) ?? "?")"
            }.joined(separator: "\n")
        case "cancel_timer":
            let id = args["id"] as? String ?? ""
            if id == "all" {
                center.removeAllPendingNotificationRequests()
            } else {
                let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0 == id || $0.hasPrefix(id + "-") }
                center.removePendingNotificationRequests(withIdentifiers: ids)
            }
            await refresh()
            return "cancelled"
        default:
            return nil
        }
    }

    private static let commandKey = "command"
    private static let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    private func schedule(_ label: String, _ trigger: UNNotificationTrigger, command: Bool = false,
                          id: String = String(UUID().uuidString.prefix(8))) async -> String {
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
            return "error: notifications are not allowed for Sara in iOS Settings"
        }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Sara")
        content.body = label.isEmpty ? String(localized: "Time is up") : label
        if command {
            // Shown only when the app was not on screen to run it.
            content.title = String(localized: "Sara was closed and didn't do this")
            content.userInfo = [Self.commandKey: true]
        } else {
            content.sound = .default
            content.interruptionLevel = .timeSensitive
        }
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
        let command = notification.request.content.userInfo[Self.commandKey] != nil
        await MainActor.run { command ? onCommand?(body) : onFire?(body) }
        await refresh()
        return command ? [] : [.banner, .sound]
    }
}
