import Foundation

/// A timer or alarm that is set and has not rung yet, as shown on the panel.
struct PendingAlarm: Identifiable, Equatable {
    let id: String
    let label: String
    let fireDate: Date
    let isTimer: Bool
}
