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
                        VStack(spacing: 10) {
                            routeCard
                            if showsLaunchGoalCard { goalCard }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                        .reportsActivityLaunchFloatingContentHeight()
                        .reportsMapAttributionOcclusionHeight()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if showsManualGoalPills { goalPillRow.padding(.vertical, 10) }
            if showsEnableLocationChip { enableLocationChip.padding(.bottom, 10) }
            launchDock
        }
    }
}
