import SwiftUI

/// Care for an iPad that hangs on the wall: dims the backlight at night and after a while with nobody around,
/// brings it back on touch, voice or an alert, and keeps an eye on how hot the device gets.
@MainActor @Observable final class PowerSaver {
    static let shared = PowerSaver()
    static let isWallPanel = UIDevice.current.userInterfaceIdiom == .pad

    /// Nobody touched the screen or talked to Sara for a while.
    private(set) var idle = false
    private(set) var thermal = ProcessInfo.processInfo.thermalState
    /// The hottest state since launch: shows whether always-on listening heats the iPad.
    private(set) var hottest = ProcessInfo.processInfo.thermalState

    /// The night clock is on screen.
    var night = false { didSet { if night != oldValue { apply() } } }

    private var userBrightness: CGFloat?
    private var idleTimer: Task<Void, Never>?
    private static let idleAfter: Duration = .seconds(15 * 60)

    func start() {
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PowerSaver.shared.updateThermal() }
        }
        activity()
    }

    /// Someone is here: a touch, a phrase, an alert. Brightens the screen and restarts the idle countdown.
    func activity() {
        idle = false
        apply()
        idleTimer?.cancel()
        guard Self.isWallPanel else { return }
        idleTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.idleAfter)
            guard !Task.isCancelled, UIApplication.shared.applicationState == .active else { return }
            self?.idle = true
            self?.apply()
        }
    }

    /// The app goes to the background: give the user their brightness back.
    func restoreBrightness() {
        if let userBrightness, let screen { screen.brightness = userBrightness }
        userBrightness = nil
    }

    private var screen: UIScreen? {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
    }

    private func apply() {
        guard Self.isWallPanel, let screen else { return }
        guard night || idle else { return restoreBrightness() }
        if userBrightness == nil { userBrightness = screen.brightness }
        screen.brightness = night ? 0.03 : 0.15
    }

    private func updateThermal() {
        thermal = ProcessInfo.processInfo.thermalState
        if thermal.rawValue > hottest.rawValue { hottest = thermal }
        #if DEBUG
        print("[power] thermal state:", thermal.rawValue)
        #endif
    }

    static func name(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: String(localized: "normal")
        case .fair: String(localized: "warm")
        case .serious: String(localized: "hot")
        case .critical: String(localized: "critical")
        @unknown default: "?"
        }
    }
}
