import SwiftUI

/// Full-screen interactive map: large globe plus a trip rail.
struct MapModeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .subheadline) private var cardWidth: CGFloat = 210

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            RadialGradient(colors: [Color(red: 0.08, green: 0.16, blue: 0.3).opacity(0.6), .clear], center: .center, startRadius: 40, endRadius: 520)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            GlobeView(initialDistance: 2.6).globeAccessibility().ignoresSafeArea()

            VStack {
                HStack(alignment: .top) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(Theme.rounded(.subheadline, .bold))
                            .frame(width: Theme.minTap, height: Theme.minTap)
                            .glassPanel(radius: Theme.minTap / 2)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close map")
                    .accessibilityShowsLargeContentViewer { Label("Close map", systemImage: "xmark") }
                    Spacer()
                    DistanceBadgeHUD()
                }
                .padding(.horizontal, 16)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                Spacer()
                if let city = model.filter.cityID.flatMap({ GeoDatabase.shared.city(id: $0) }) {
                    HStack(spacing: 4) {
                        Text("\(city.country.flag) \(city.label)").font(Theme.rounded(.subheadline))
                            .accessibilityLabel(city.label)
                        Text("· \(model.result.matches.count) photos").font(Theme.mono(.footnote, .medium)).foregroundStyle(Theme.textSecondary)
                            .accessibilityLabel("\(model.result.matches.count) photos")
                        Button { model.filter.cityID = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: Theme.minTap, height: Theme.minTap)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, -10)
                        .padding(.trailing, -12)
                        .accessibilityLabel("Show all cities")
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 14).padding(.vertical, 8).glassPanel(radius: 20)
                }
                tripRail
            }
            .padding(.bottom, 8)
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private var tripRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.analysis.trips) { trip in
                    let active = model.filter.tripID == trip.id
                    let route = trip.stops.filter { !$0.isLayover }.compactMap { $0.city?.name }.uniqued()
                    Button {
                        withAnimation(.snappy) { model.apply(.trip(trip)) }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(trip.countries.map { Countries.info($0).flag }.joined()).font(.callout)
                            Text(trip.title).font(Theme.rounded(.subheadline)).lineLimit(1)
                            Text(route.joined(separator: " → "))
                                .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            HStack(spacing: 10) {
                                Label(DistanceBadgeHUD.km(trip.distanceKm) + " km", systemImage: "airplane")
                                Label("\(trip.assetIDs.count)", systemImage: "photo")
                            }
                            .font(Theme.mono(.caption, .medium)).foregroundStyle(Theme.textSecondary)
                        }
                        .frame(width: cardWidth, alignment: .leading)
                        .padding(12)
                        .glassPanel()
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(active ? Theme.amber : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(trip.title)
                    .accessibilityValue("\(route.joined(separator: ", ")). \(DistanceBadgeHUD.spokenKm(trip.distanceKm)) kilometers, \(trip.assetIDs.count) photos")
                    .accessibilitySelected(active)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
