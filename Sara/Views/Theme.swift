import SwiftUI

/// Colors of the panel design. The panel is always dark.
enum Theme {
    static let background = Color(hex: 0x0E1013)
    static let card = Color(hex: 0x171A1F)
    static let border = Color(hex: 0x22262D)
    static let text = Color(hex: 0xECEEF1)
    static let secondary = Color(hex: 0x9AA3AE)
    static let muted = Color(hex: 0x7D8591)
    static let amber = Color(hex: 0xF2B266)
    static let amberBackground = Color(hex: 0x2B2217)
    static let amberBorder = Color(hex: 0x5A4325)
    static let teal = Color(hex: 0x6ED3CB)
    static let tealBackground = Color(hex: 0x12201F)
    static let blue = Color(hex: 0x8DB9FF)
    static let tealFill = Color(hex: 0x12302D)
    static let blueFill = Color(hex: 0x172230)
    static let soft = Color(hex: 0xC9CED6)
    static let deepBackground = Color(hex: 0x07080A)
    static let sheet = Color(hex: 0x12151A)
    static let highlight = Color(hex: 0x1D2128)
    static let track = Color(hex: 0x262B33)
    static let ring = Color(hex: 0x2E333B)
    static let tealBorder = Color(hex: 0x24413E)
    static let snow = Color(hex: 0xDCE6F5)
    /// Accents for running devices, in turn.
    static let accents = [amber, blue, teal]
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    func card(padding: CGFloat = 22, cornerRadius: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Theme.border))
    }

    func blockTitle(_ color: Color = Theme.secondary, size: CGFloat = 15) -> some View {
        self.font(.system(size: size, weight: .semibold)).tracking(size / 10).textCase(.uppercase).foregroundStyle(color)
    }

    /// Without Home Assistant its states are unknown, not off: such blocks fade and take no taps.
    func unreachable(_ unreachable: Bool) -> some View {
        self.saturation(unreachable ? 0 : 1)
            .opacity(unreachable ? 0.4 : 1)
            .allowsHitTesting(!unreachable)
    }

    func pill() -> some View {
        self.font(.system(size: 17, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(Theme.card, in: .capsule)
            .overlay(Capsule().stroke(Theme.border))
    }
}
