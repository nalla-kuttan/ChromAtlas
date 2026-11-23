import SwiftUI

enum Theme {
    static let background = Color(red: 0.047, green: 0.055, blue: 0.071)
    // White tints that strengthen when Increase Contrast is on (Settings › Accessibility › Display & Text Size).
    static let surface = white(0.055, high: 0.13)
    static let surfaceRaised = white(0.09, high: 0.2)
    static let stroke = white(0.09, high: 0.38)
    static let textPrimary = white(0.94, high: 1)
    static let textSecondary = white(0.56, high: 0.8)
    /// 0.48 keeps ≥ 4.5:1 against `background` while staying a step below secondary.
    static let textTertiary = white(0.48, high: 0.7)
    /// Backing behind floating glass panels; nearly opaque under Increase Contrast so text over the globe stays legible.
    static let panelScrim = adaptive(UIColor(white: 0, alpha: 0.35), high: UIColor(white: 0, alpha: 0.75))
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.38)
    static let cyan = Color(red: 0.45, green: 0.85, blue: 1.0)

    private static func white(_ normal: CGFloat, high: CGFloat) -> Color {
        adaptive(UIColor(white: 1, alpha: normal), high: UIColor(white: 1, alpha: high))
    }

    private static func adaptive(_ normal: UIColor, high: UIColor) -> Color {
        Color(UIColor { $0.accessibilityContrast == .high ? high : normal })
    }

    /// Minimum hit area for every tappable control (HIG: 44 × 44 pt).
    static let minTap: CGFloat = 44

    /// Rounded UI text that follows Dynamic Type.
    static func rounded(_ style: Font.TextStyle, _ weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    /// Tabular figures for counts and measurements; follows Dynamic Type.
    static func mono(_ style: Font.TextStyle, _ weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }

    /// Small uppercase caption used under HUD figures.
    static func caps(_ weight: Font.Weight = .semibold) -> Font {
        .system(.caption2, design: .default, weight: weight)
    }
}

struct GlassPanel: ViewModifier {
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(Theme.panelScrim, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.stroke))
    }
}

extension View {
    func glassPanel(radius: CGFloat = 14) -> some View { modifier(GlassPanel(radius: radius)) }

    /// Grows the hit area to at least 44 × 44 pt around a visually smaller control.
    func tapTarget(width: Bool = true) -> some View {
        frame(minWidth: width ? Theme.minTap : nil, minHeight: Theme.minTap)
            .contentShape(Rectangle())
    }

    /// Marks a toggle-like control as selected for VoiceOver.
    func accessibilitySelected(_ on: Bool) -> some View {
        accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }
}

struct PillToggle: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = Theme.amber
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(Theme.rounded(.caption2)).accessibilityHidden(true) }
                Text(title).font(Theme.rounded(.footnote))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(isOn ? Color.black.opacity(0.85) : Theme.textSecondary)
            .background(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.surface), in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Color.clear : Theme.stroke))
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilitySelected(isOn)
        .sensoryFeedback(.selection, trigger: isOn)
    }
}
