import SwiftUI

/// Shared launch layout used by Today and the standalone recording surface.
/// Domain selection and persistence remain with the launch coordinator/host;
/// this view only composes the map, peer cards, goal controls, and dock.
struct ActivitySetupView: View {
    let isEmbeddedInToday: Bool
    let usesEmbeddedPlannedContent: Bool
    let showsRouteCard: Bool
    let showsLaunchGoalCard: Bool
    let showsManualGoalPills: Bool
    let showsEnableLocationChip: Bool
    let map: AnyView
    let offlineStatus: AnyView
    let routeCard: AnyView
    let goalCard: AnyView
    let goalPillRow: AnyView
    let enableLocationChip: AnyView
    let launchDock: AnyView
    let contextualStartControl: AnyView
    let onAppear: () -> Void

    var body: some View {
        Group {
            if isEmbeddedInToday {
                embeddedLayout
            } else {
                standaloneLayout
            }
        }
        .onAppear(perform: onAppear)
    }

    private var standaloneLayout: some View {
        ZStack(alignment: .bottom) {
            if !usesEmbeddedPlannedContent { map }

            VStack(spacing: 10) {
                offlineStatus
                Spacer(minLength: 96)
                if showsLaunchGoalCard { goalCard.padding(.horizontal, 18) }
                if showsManualGoalPills { goalPillRow.padding(.bottom, 2) }
                if showsEnableLocationChip { enableLocationChip }
                launchDock
            }
            .padding(.bottom, 70)

            contextualStartControl.padding(.bottom, 3)
        }
    }

    private var embeddedLayout: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                Color.clear.allowsHitTesting(false)

                if showsLaunchGoalCard || showsRouteCard {
                    VStack(spacing: 10) {
                        offlineStatus
                        Spacer(minLength: 72)
                        ActivityLaunchSummaryLayout {
                            if showsRouteCard { routeCard }
                            if showsLaunchGoalCard { goalCard }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, showsLaunchGoalCard ? 20 : 12)
                        .reportsActivityLaunchFloatingContentHeight()
                        .reportsMapAttributionOcclusionHeight()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            VStack(spacing: 0) {
                if showsManualGoalPills { goalPillRow.padding(.vertical, 10) }
                if showsEnableLocationChip { enableLocationChip.padding(.bottom, 10) }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ActivityLaunchMapControlsHeightPreferenceKey.self,
                        value: proxy.size.height
                    )
                }
            }
            launchDock
        }
    }
}

/// Center compact peers in a row when they fit; otherwise wrap into a centered
/// stack. Each peer keeps its own actions and receives the full available width
/// when wrapping so large text and long route/workout names remain readable.
private struct ActivityLaunchSummaryLayout: Layout {
    private let gap: CGFloat = OutboundSpacing.standard

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let layout = arrangement(proposal: proposal, subviews: subviews)
        return CGSize(width: layout.width, height: layout.isRow
            ? layout.sizes.map(\.height).max() ?? 0
            : layout.sizes.reduce(0) { $0 + $1.height } + gap * CGFloat(max(0, subviews.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrangement(proposal: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        let rowWidth = layout.sizes.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, subviews.count - 1))
        var x = bounds.midX - rowWidth / 2
        var y = bounds.minY
        for (index, view) in subviews.enumerated() {
            let size = layout.sizes[index]
            if layout.isRow {
                view.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
                x += size.width + gap
            } else {
                view.place(at: CGPoint(x: bounds.midX, y: y), anchor: .top, proposal: ProposedViewSize(size))
                y += size.height + gap
            }
        }
    }

    private func arrangement(proposal: ProposedViewSize, subviews: Subviews) -> (width: CGFloat, sizes: [CGSize], isRow: Bool) {
        let ideals = subviews.map { $0.sizeThatFits(.unspecified) }
        let idealWidth = ideals.reduce(0) { $0 + $1.width } + gap * CGFloat(max(0, subviews.count - 1))
        let availableWidth = max(0, proposal.width ?? idealWidth)
        let isRow = idealWidth <= availableWidth
        let sizes = zip(subviews, ideals).map { view, ideal in
            view.sizeThatFits(ProposedViewSize(width: min(ideal.width, availableWidth), height: nil))
        }
        return (availableWidth, sizes, isRow)
    }
}
