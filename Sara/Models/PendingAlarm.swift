import Foundation

/// A timer, alarm or scheduled command that is set and has not rung or run yet, as shown on the panel.
struct PendingAlarm: Identifiable, Equatable {
    let id: String
    let label: String
    let fireDate: Date
    let isTimer: Bool
    let isCommand: Bool
}
