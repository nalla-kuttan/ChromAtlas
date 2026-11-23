import SwiftUI

struct AssetDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let record: AssetRecord

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GeometryReader { g in
                        AssetThumbnail(record: record, side: g.size.width, showBadges: false)
                    }
                    .aspectRatio(1, contentMode: .fit)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.placeLabel ?? "No location")
                            .font(Theme.rounded(.title2, .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(record.date.formatted(date: .complete, time: .shortened))
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if let p = record.solarPhase { tag(p.label, p.symbol) }
                            tag(record.season.label, record.season.symbol)
                            if let t = record.tripID, let trip = model.analysis.trips.first(where: { $0.id == t }) {
                                tag(trip.title, "airplane")
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Palette").font(Theme.rounded(.subheadline)).foregroundStyle(Theme.textSecondary)
                            .accessibilityAddTraits(.isHeader)
                        GeometryReader { g in
                            let total = max(0.001, record.colors.reduce(0) { $0 + $1.weight })
                            HStack(spacing: 0) {
                                ForEach(Array(record.colors.enumerated()), id: \.offset) { _, c in
                                    Rectangle().fill(c.lab.color).frame(width: g.size.width * c.weight / total)
                                }
                            }
                        }
                        .frame(height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                        ForEach(Array(record.colors.enumerated()), id: \.offset) { _, c in
                            HStack {
                                Circle().fill(c.lab.color).frame(width: 12, height: 12).accessibilityHidden(true)
                                Text(ChromaticZone.name(hue: c.lab.hueDegrees, chroma: c.lab.chroma, lightness: c.lab.L))
                                    .font(Theme.rounded(.subheadline, .medium))
                                Spacer()
                                Text("\(Int((c.weight * 100).rounded()))%").font(Theme.mono(.subheadline, .medium)).foregroundStyle(Theme.textSecondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }

                    Button {
                        let c = record.colors.first(where: { $0.lab.chroma > 0.04 }) ?? record.colors.first
                        if let c {
                            model.filter.color = ColorSelection(hue: c.lab.hueDegrees,
                                                                saturation: min(1, c.lab.chroma / ColorSelection.maxChroma))
                        }
                        dismiss()
                    } label: {
                        Label("Find photos with this palette", systemImage: "eyedropper.halffull")
                            .font(Theme.rounded(.callout))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Theme.amber, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func tag(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(Theme.rounded(.caption))
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.surface, in: Capsule())
    }
}
