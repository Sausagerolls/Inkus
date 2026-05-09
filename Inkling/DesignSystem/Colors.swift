import SwiftUI

extension Color {
    static let inkBackground = Color(.systemBackground)
    static let inkSecondary  = Color(.secondarySystemBackground)
    static let inkAccent     = Color(hex: "#4F46E5")  // indigo
    static let inkInk        = Color(.label)
    static let inkSubtle     = Color(.secondaryLabel)
    static let inkSeparator  = Color(.separator)

    /// Build a SwiftUI Color from a hex string.
    /// Accepts "#RRGGBB", "RRGGBB", "#RRGGBBAA", or "RRGGBBAA". Falls back to .clear on parse fail.
    init(hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard let value = UInt64(trimmed, radix: 16) else {
            self = .clear
            return
        }
        let r, g, b, a: Double
        switch trimmed.count {
        case 6:
            r = Double((value & 0xFF0000) >> 16) / 255.0
            g = Double((value & 0x00FF00) >>  8) / 255.0
            b = Double( value & 0x0000FF       ) / 255.0
            a = 1.0
        case 8:
            r = Double((value & 0xFF000000) >> 24) / 255.0
            g = Double((value & 0x00FF0000) >> 16) / 255.0
            b = Double((value & 0x0000FF00) >>  8) / 255.0
            a = Double( value & 0x000000FF       ) / 255.0
        default:
            self = .clear
            return
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
