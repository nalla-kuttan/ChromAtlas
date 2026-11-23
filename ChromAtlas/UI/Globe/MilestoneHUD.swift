import SwiftUI

/// Top-left telemetry: countries and cities.
struct TelemetryHUD: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            HUDStat(value: "\(model.analysis.countriesVisited.count)", label: "Countries",
                    spoken: "\(model.analysis.countriesVisited.count) countries")
            HUDDivider()
            HUDStat(value: "\(model.analysis.citiesVisited.count)", label: "Cities",
                    spoken: "\(model.analysis.citiesVisited.count) cities")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassPanel()
        .fixedSize()
    }
}

/// Top-right: distance, passports and regional badges.
struct DistanceBadgeHUD: View {
    @Environment(AppModel.self) private var model
    var compact = false
    var alignment: HorizontalAlignment = .trailing
    var showsBadges = true

    var body: some View {
        let km = model.analysis.kilometersTraveled
        VStack(alignment: alignment, spacing: 6) {
            HStack(spacing: 12) {
                HUDStat(value: Self.km(km), label: "Km traveled", alignment: alignment,
                        spoken: "\(Self.spokenKm(km)) kilometers traveled")
                HUDDivider()
                HUDStat(value: "\(model.analysis.passportsStamped)", label: "Stamps", alignment: alignment,
                        spoken: "\(model.analysis.passportsStamped) passport stamps")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassPanel()
            .fixedSize()

            let unlocked = model.analysis.badges.filter(\.unlocked)
            if showsBadges, !unlocked.isEmpty {
                VStack(alignment: alignment, spacing: 4) {
                    ForEach(unlocked.prefix(compact ? 2 : 4)) { b in BadgeChip(badge: b) }
                }
            }
        }
    }

    private static let decimal: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static func km(_ v: Double) -> String {
        if v >= 100_000 { return String(format: "%.0fk", v / 1000) }
        return decimal.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    }

    /// Full figure for VoiceOver ("157,000" rather than "157k").
    static func spokenKm(_ v: Double) -> String {
        decimal.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))"
    }
}

private struct HUDStat: View {
    let value: String
    let label: String
    var alignment: HorizontalAlignment = .leading
    let spoken: String

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(value).font(Theme.mono(.title3, .bold)).foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
            Text(label.uppercased()).font(Theme.caps()).tracking(0.4).foregroundStyle(Theme.textSecondary)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

private struct HUDDivider: View {
    @ScaledMetric(relativeTo: .title3) private var height: CGFloat = 26
    var body: some View { Rectangle().fill(Theme.stroke).frame(width: 1, height: height).accessibilityHidden(true) }
}

struct BadgeChip: View {
    let badge: Badge
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: badge.symbol).font(Theme.rounded(.caption2, .bold)).accessibilityHidden(true)
            Text(badge.title).font(Theme.rounded(.caption))
        }
        .lineLimit(1)
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .foregroundStyle(badge.unlocked ? Theme.amber : Theme.textTertiary)
        .background(Color.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().strokeBorder(badge.unlocked ? Theme.amber.opacity(0.45) : Theme.stroke))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Badge: \(badge.title)")
    }
}
