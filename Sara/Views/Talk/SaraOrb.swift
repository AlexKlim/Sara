import SwiftUI

/// The big circle of the conversation screen: its color, icon and motion show what Sara is doing.
struct SaraOrb: View {
    enum Stage { case idle, listening, thinking, answering }

    let stage: Stage
    var size: CGFloat = 240
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if stage == .thinking && !reduceMotion {
                orb.background { Circle().stroke(Theme.blue.opacity(0.3), lineWidth: 24).blur(radius: 24) }
                    .phaseAnimator([false, true]) { orb, inhale in
                        orb.scaleEffect(inhale ? 0.93 : 1).opacity(inhale ? 1 : 0.85)
                    } animation: { _ in .easeInOut(duration: 1.3) }
            } else {
                orb.background { if !reduceMotion { ripple } }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    private var orb: some View {
        let color = stage == .thinking ? Theme.blue : Theme.teal
        return ZStack {
            Circle().stroke(color, lineWidth: 2)
            Circle().fill(stage == .thinking ? Theme.blueFill : Theme.tealFill).padding(size * 0.1875)
            Image(systemName: icon).font(.system(size: size * 0.2, weight: .light)).foregroundStyle(color)
        }
        .frame(width: size, height: size)
    }

    /// A teal ring that spreads out and fades: quick while listening, slow while answering.
    @ViewBuilder private var ripple: some View {
        let motion: (spread: CGFloat, opacity: Double, seconds: Double)? = switch stage {
        case .listening: (1.37, 0.6, 1.1)
        case .answering: (1.27, 0.35, 2.4)
        default: nil
        }
        if let motion {
            Circle().fill(Theme.teal)
                .phaseAnimator([false, true]) { circle, out in
                    circle.scaleEffect(out ? motion.spread : 1).opacity(out ? 0 : motion.opacity)
                } animation: { out in out ? .easeOut(duration: motion.seconds) : nil }
                .id(stage)
        }
    }

    private var icon: String {
        switch stage {
        case .idle, .listening: "mic"
        case .thinking: "ellipsis"
        case .answering: "waveform"
        }
    }

    private var label: LocalizedStringKey {
        switch stage {
        case .idle: "Sara"
        case .listening: "Sara is listening"
        case .thinking: "Sara is thinking"
        case .answering: "Sara is answering"
        }
    }
}
