import SwiftUI

struct EnvironmentPills: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Season.allCases) { s in
                        PillToggle(title: s.label, symbol: s.symbol, tint: Self.seasonTint(s), isOn: model.filter.seasons.contains(s)) {
                            toggle(&model.filter.seasons, s)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SolarPhase.allCases) { p in
                        PillToggle(title: p.label, symbol: p.symbol, tint: Self.phaseTint(p), isOn: model.filter.phases.contains(p)) {
                            toggle(&model.filter.phases, p)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ v: T) {
        if set.contains(v) { set.remove(v) } else { set.insert(v) }
    }

    static func seasonTint(_ s: Season) -> Color {
        switch s {
        case .spring: return OKLab(L: 0.84, chroma: 0.12, hueDegrees: 140).color
        case .summer: return OKLab(L: 0.85, chroma: 0.14, hueDegrees: 95).color
        case .autumn: return OKLab(L: 0.75, chroma: 0.14, hueDegrees: 50).color
        case .winter: return OKLab(L: 0.85, chroma: 0.07, hueDegrees: 235).color
        }
    }

    static func phaseTint(_ p: SolarPhase) -> Color {
        switch p {
        case .daylight: return OKLab(L: 0.9, chroma: 0.09, hueDegrees: 100).color
        case .goldenHour: return Theme.amber
        case .blueHour: return OKLab(L: 0.72, chroma: 0.12, hueDegrees: 262).color
        case .night: return OKLab(L: 0.70, chroma: 0.10, hueDegrees: 290).color
        }
    }
}
