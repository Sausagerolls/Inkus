import SwiftUI

/// Centralised typography roles per design-system Section 8.
/// Existing views can keep their `.font(.system(.body, design: .serif))` usage,
/// but new code should prefer these named roles for clarity.
enum Typography {
    /// Day headers, prompt card, large hero text.
    static let display = Font.system(.largeTitle, design: .serif)

    /// Screen titles. Semibold.
    static let title = Font.title2.weight(.semibold)

    /// Entry text — the most important typographic decision in the app.
    static let body = Font.system(.body, design: .serif)

    /// Body emphasis for tag chips, dates.
    static let bodyEmphasis = Font.body.weight(.medium)

    /// Timestamps, metadata, secondary copy.
    static let caption = Font.caption

    /// Even smaller meta (footer notes, unit labels).
    static let micro = Font.caption2
}
