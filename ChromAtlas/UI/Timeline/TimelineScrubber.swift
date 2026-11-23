import SwiftUI

/// Continuous multi-year scrubber: density histogram, trip spans, and a brushable time window.
struct TimelineScrubber: View {
    @Environment(AppModel.self) private var model
    @State private var dragMode: DragMode?
    @State private var lastYearHaptic: Int?
    /// Year-label row grows with Dynamic Type; the chart band below keeps its height.
    @ScaledMetric(relativeTo: .caption2) private var labelHeight: CGFloat = 13
    @ScaledMetric(relativeTo: .caption2) private var labelWidth: CGFloat = 30

    private let band: CGFloat = 44
    private enum DragMode { case lower, upper, brush(anchor: Double), move(offset: Double, width: Double) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = model.dateSpan
            let len = max(1, span.upperBound - span.lowerBound)
            let x = { (t: TimeInterval) -> CGFloat in CGFloat((t - span.lowerBound) / len) * w }
            let t = { (x: CGFloat) -> TimeInterval in span.lowerBound + Double(min(max(x / w, 0), 1)) * len }
            let top = labelHeight

            ZStack(alignment: .topLeading) {
                // Year ticks + labels. When years are too close for their labels (narrow width or large text),
                // every nth year is labelled; ticks stay on every year.
                let years = yearMarks(span)
                let yearWidth = w * CGFloat(365.25 * 86400 / len)
                let every = max(1, Int(((labelWidth + 4) / max(yearWidth, 1)).rounded(.up)))
                ForEach(Array(years.enumerated()), id: \.element.0) { i, mark in
                    let xx = x(mark.1)
                    Rectangle().fill(Theme.stroke).frame(width: 1, height: band).offset(x: xx, y: top)
                    if i % every == 0, xx + 3 + labelWidth <= w {
                        Text(verbatim: "\(mark.0)")
                            .font(Theme.rounded(.caption2))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize()
                            .offset(x: xx + 3, y: 0)
                    }
                }

                // Density histogram
                Canvas { ctx, size in
                    let months = model.monthlyDensity
                    guard !months.isEmpty else { return }
                    let maxC = Double(months.map(\.count).max() ?? 1)
                    let bw = size.width / CGFloat(months.count)
                    for (i, m) in months.enumerated() where m.count > 0 {
                        let h = CGFloat(sqrt(Double(m.count) / maxC)) * (size.height - 2)
                        let rect = CGRect(x: CGFloat(i) * bw + 0.5, y: size.height - h, width: max(1, bw - 1), height: h)
                        let tt = (m.month.timeIntervalSince1970 - span.lowerBound) / len
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Color(ArcPalette.chronological(tt)).opacity(0.55)))
                    }
                }
                .frame(height: 30)
                .offset(y: top + 2)

                // Trip spans
                ForEach(model.analysis.trips) { trip in
                    let x0 = x(trip.start.timeIntervalSince1970), x1 = x(trip.end.timeIntervalSince1970)
                    let active = model.filter.tripID == trip.id || model.result.matchingTrips.contains(trip.id)
                    Capsule()
                        .fill(Color(ArcPalette.chronological(Double(x0 / max(w, 1)))))
                        .opacity(model.filter.isEmpty || active ? 1 : 0.25)
                        .frame(width: max(4, x1 - x0), height: 4)
                        .offset(x: x0, y: top + 36)
                }

                // Selection window
                if let r = model.filter.timeRange {
                    let x0 = x(r.lowerBound), x1 = x(r.upperBound)
                    Rectangle().fill(Color.black.opacity(0.55)).frame(width: max(0, x0), height: band).offset(y: top)
                    Rectangle().fill(Color.black.opacity(0.55)).frame(width: max(0, w - x1), height: band).offset(x: x1, y: top)
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.amber, lineWidth: 1.5)
                        .frame(width: max(6, x1 - x0), height: band).offset(x: x0, y: top)
                    handle.offset(x: x0 - 5, y: top + 10)
                    handle.offset(x: x1 - 5, y: top + 10)
                }
            }
            .frame(width: w, height: top + band, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let tx = t(g.location.x)
                        if dragMode == nil {
                            if let r = model.filter.timeRange {
                                let sx = g.startLocation.x
                                // 22 pt either side of a handle gives it a 44 pt grab zone.
                                if abs(sx - x(r.lowerBound)) < 22 { dragMode = .lower }
                                else if abs(sx - x(r.upperBound)) < 22 { dragMode = .upper }
                                else if sx > x(r.lowerBound), sx < x(r.upperBound) {
                                    dragMode = .move(offset: t(sx) - r.lowerBound, width: r.upperBound - r.lowerBound)
                                } else { dragMode = .brush(anchor: t(sx)) }
                            } else {
                                dragMode = .brush(anchor: t(g.startLocation.x))
                            }
                        }
                        var f = model.filter
                        switch dragMode! {
                        case .lower: if let r = f.timeRange { f.timeRange = min(tx, r.upperBound - 86400)...r.upperBound }
                        case .upper: if let r = f.timeRange { f.timeRange = r.lowerBound...max(tx, r.lowerBound + 86400) }
                        case .brush(let a): f.timeRange = min(a, tx)...max(a, tx) + 1
                        case .move(let off, let width):
                            let lo = min(max(tx - off, span.lowerBound), span.upperBound - width)
                            f.timeRange = lo...(lo + width)
                        }
                        f.tripID = nil
                        model.filter = f
                        let year = Calendar.current.component(.year, from: Date(timeIntervalSince1970: tx))
                        if year != lastYearHaptic {
                            lastYearHaptic = year
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                    .onEnded { _ in
                        if case .brush = dragMode, let r = model.filter.timeRange, r.upperBound - r.lowerBound < 3 * 86400 {
                            model.filter.timeRange = nil   // a tap clears the window
                        }
                        dragMode = nil
                    }
            )
        }
        .frame(height: labelHeight + band)
        .accessibilityElement()
        .accessibilityLabel("Timeline")
        .accessibilityValue(rangeLabel)
        .accessibilityHint("Swipe up or down to step through years.")
        .accessibilityAdjustableAction { direction in stepYear(direction == .increment ? 1 : -1) }
        .accessibilityAction(named: "Show all time") { model.filter.timeRange = nil }
    }

    private var handle: some View {
        RoundedRectangle(cornerRadius: 3).fill(Theme.amber).frame(width: 10, height: 24)
            .overlay(VStack(spacing: 2) { ForEach(0..<3) { _ in Rectangle().fill(.black.opacity(0.5)).frame(width: 4, height: 1) } })
    }

    private var rangeLabel: String {
        guard let r = model.filter.timeRange else { return "All time" }
        let lo = Date(timeIntervalSince1970: r.lowerBound), hi = Date(timeIntervalSince1970: r.upperBound)
        return "\(lo.formatted(date: .abbreviated, time: .omitted)) to \(hi.formatted(date: .abbreviated, time: .omitted))"
    }

    /// VoiceOver: moves the window one calendar year at a time, starting from the first or last year.
    private func stepYear(_ delta: Int) {
        let years = yearMarks(model.dateSpan).map(\.0)
        guard let first = years.first, let last = years.last else { return }
        let cal = Calendar(identifier: .gregorian)
        let target: Int
        if let r = model.filter.timeRange {
            let current = cal.component(.year, from: Date(timeIntervalSince1970: (r.lowerBound + r.upperBound) / 2))
            target = min(max(current + delta, first), last)
        } else {
            target = delta > 0 ? first : last
        }
        let start = cal.date(from: DateComponents(year: target, month: 1, day: 1))!.timeIntervalSince1970
        let end = cal.date(from: DateComponents(year: target + 1, month: 1, day: 1))!.timeIntervalSince1970 - 1
        var f = model.filter
        f.tripID = nil
        f.timeRange = start...end
        model.filter = f
    }

    private func yearMarks(_ span: ClosedRange<TimeInterval>) -> [(Int, TimeInterval)] {
        let cal = Calendar(identifier: .gregorian)
        let y0 = cal.component(.year, from: Date(timeIntervalSince1970: span.lowerBound))
        let y1 = cal.component(.year, from: Date(timeIntervalSince1970: span.upperBound))
        guard y1 >= y0 else { return [] }
        return (y0...y1).compactMap { y in
            let d = cal.date(from: DateComponents(year: y, month: 1, day: 1))!.timeIntervalSince1970
            return d < span.upperBound ? (y, d) : nil
        }
    }
}

struct ChapterChips: View {
    @Environment(AppModel.self) private var model
    var showsColorChip = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if !model.filter.isEmpty {
                    Button {
                        withAnimation(.snappy) { model.clearAllFilters() }
                    } label: {
                        Label("Clear", systemImage: "xmark")
                            .font(Theme.rounded(.caption))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Theme.surfaceRaised, in: Capsule())
                            .foregroundStyle(Theme.textPrimary)
                            .tapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear all filters")
                }
                if showsColorChip, model.filter.hasColorFilter {
                    Button { model.tab = .palette } label: {
                        HStack(spacing: 6) {
                            Circle().fill(colorSwatch).frame(width: 10, height: 10)
                            Text("Color")
                            Image(systemName: "chevron.forward").font(Theme.rounded(.caption2, .bold))
                        }
                        .font(Theme.rounded(.footnote))
                        .lineLimit(1)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .foregroundStyle(Theme.textPrimary)
                        .background(Theme.surfaceRaised, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.amber.opacity(0.6)))
                        .tapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Color filter: \(model.colorCallout)")
                    .accessibilityHint("Opens the Palette tab.")
                }
                ForEach(model.chapters) { chapter in
                    ChapterChip(chapter: chapter, active: model.isActive(chapter)) {
                        withAnimation(.snappy) { model.apply(chapter) }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var colorSwatch: Color {
        guard let c = model.filter.color else { return Color.white.opacity(0.5) }
        return c.isNeutral ? .gray : OKLab(L: 0.74, chroma: c.targetChroma, hueDegrees: c.hue).color
    }
}

private struct ChapterChip: View {
    let chapter: Chapter
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                switch chapter {
                case .trip(let t):
                    Text(t.countries.prefix(3).map { Countries.info($0).flag }.joined()).font(.caption)
                    Text(t.title)
                case .year(let y, _):
                    Image(systemName: "calendar").font(Theme.rounded(.caption2, .bold))
                    Text(verbatim: "\(y)")
                case .aesthetic(let name, let hue, let sat):
                    Circle().fill(OKLab(L: 0.74, chroma: max(0.08, sat * ColorSelection.maxChroma), hueDegrees: hue).color)
                        .frame(width: 10, height: 10)
                    Text(name)
                }
            }
            .font(Theme.rounded(.footnote))
            .lineLimit(1)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(active ? Color.black.opacity(0.85) : Theme.textPrimary.opacity(0.85))
            .background(active ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(Theme.surface), in: Capsule())
            .overlay(Capsule().strokeBorder(active ? .clear : Theme.stroke))
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilitySelected(active)
        .sensoryFeedback(.selection, trigger: active)
    }

    private var spokenLabel: String {
        switch chapter {
        case .trip(let t): return "Trip: \(t.title)"
        case .year(let y, _): return "Year \(y)"
        case .aesthetic(let name, _, _): return "Palette: \(name)"
        }
    }
}
