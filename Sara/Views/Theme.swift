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
    /// Accents for running devices, in turn.
    static let accents = [amber, blue, teal]
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    func card(padding: CGFloat = 22) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border))
    }

    func blockTitle() -> some View {
        self.font(.system(size: 15, weight: .semibold)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.secondary)
    }
}
