import Foundation

/// The pages of Settings, shown in the sidebar.
enum SettingsSection: String, CaseIterable, Identifiable {
    case assistant, home, yandex, voice, panel, night, memory

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .assistant: "Sara"
        case .home: "Home Assistant"
        case .yandex: "Yandex Smart Home"
        case .voice: "Voice"
        case .panel: "Panel"
        case .night: "Night mode"
        case .memory: "Memory"
        }
    }

    var icon: String {
        switch self {
        case .assistant: "sparkles"
        case .home: "house"
        case .yandex: "house.lodge"
        case .voice: "waveform"
        case .panel: "square.grid.2x2"
        case .night: "moon.stars"
        case .memory: "brain"
        }
    }
}
