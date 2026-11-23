import SwiftUI

/// Self-scrolling live-filtered grid. `lane`/`laneCount` split results between flanking grids.
struct PhotoGrid: View {
    var lane = 0
    var laneCount = 1
    var columns = 3
    var spacing: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                PhotoGridContent(width: geo.size.width, lane: lane, laneCount: laneCount, columns: columns, spacing: spacing)
            }
        }
    }
}

/// Non-scrolling grid body, for embedding inside an outer ScrollView.
/// Shows results a page at a time and adds the next page as the last thumbnail scrolls into view.
struct PhotoGridContent: View {
    @Environment(AppModel.self) private var model
    var width: CGFloat
    var lane = 0
    var laneCount = 1
    var columns = 3
    var spacing: CGFloat = 4
    var pageSize = 300
    @State private var shown = 300

    var body: some View {
        let side = max(20, floor((width - spacing * CGFloat(columns - 1)) / CGFloat(columns)))
        let all = laneItems
        let items = Array(all.prefix(shown))
        if items.isEmpty {
            emptyState.frame(width: width).padding(.vertical, 30)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: spacing), count: columns), spacing: spacing) {
                ForEach(items, id: \.self) { idx in
                    let rec = model.asset(at: idx)
                    Button { model.selectedAsset = rec } label: { AssetThumbnail(record: rec, side: side) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows the photo's palette and details.")
                        .onAppear {
                            if idx == items.last, shown < all.count { shown += pageSize }
                        }
                }
            }
            .frame(width: width)
            .task(id: "\(model.resultVersion)-\(shown)") {
                // Look up only the page that was just added.
                let newPage = items.suffix(min(pageSize, items.count))
                ThumbnailLoader.shared.prefetch(newPage.map { model.asset(at: $0) })
            }
            .onChange(of: model.resultVersion) { shown = pageSize }
        }
    }

    private var laneItems: [Int32] {
        let m = model.result.matches
        guard laneCount > 1 else { return m }
        return stride(from: lane, to: m.count, by: laneCount).map { m[$0] }
    }

    @ViewBuilder private var emptyState: some View {
        if lane == 0 {
            VStack(spacing: 8) {
                Image(systemName: "camera.filters").font(.title2).foregroundStyle(Theme.textTertiary).accessibilityHidden(true)
                if model.assets.isEmpty {
                    Text("No photos indexed yet")
                        .font(Theme.rounded(.footnote, .medium)).foregroundStyle(Theme.textSecondary)
                } else {
                    let active = model.activeFilterDescriptions
                    Text("No photos match")
                        .font(Theme.rounded(.subheadline, .semibold)).foregroundStyle(Theme.textPrimary)
                    if !active.isEmpty {
                        Text(active.joined(separator: " + "))
                            .font(Theme.rounded(.footnote, .medium)).foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        withAnimation(.snappy) { model.clearAllFilters() }
                    } label: {
                        Text(active.count > 1 ? "Clear All Filters" : "Clear Filter")
                            .font(Theme.rounded(.footnote))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Theme.surfaceRaised, in: Capsule())
                            .foregroundStyle(Theme.textPrimary)
                            .tapTarget()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
        } else {
            Color.clear.frame(height: 1)
        }
    }
}
