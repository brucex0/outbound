import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

extension ActivityFlowView {
    var readyView: some View {
        ActivitySetupView(
            isEmbeddedInToday: false,
            usesEmbeddedPlannedContent: model.usesEmbeddedPlannedContent,
            showsRouteCard: model.setup.plannedIntent?.preparedRoute != nil,
            showsLaunchGoalCard: model.showsLaunchGoalCard,
            showsManualGoalPills: model.setup.showsManualGoalPills,
            showsEnableLocationChip: model.showsEnableLocationChip,
            map: AnyView(launchMap),
            offlineStatus: AnyView(offlineStatusBanner),
            routeCard: AnyView(launchRouteCardView),
            goalCard: AnyView(launchGoalCard),
            goalPillRow: AnyView(launchGoalPillRow),
            enableLocationChip: AnyView(enableLocationChip),
            launchDock: AnyView(launchDock),
            contextualStartControl: AnyView(contextualStartControl),
            onAppear: model.prepareSetupSurface
        )
    }

    var embeddedReadyView: some View {
        ActivitySetupView(
            isEmbeddedInToday: true,
            usesEmbeddedPlannedContent: model.usesEmbeddedPlannedContent,
            showsRouteCard: model.setup.plannedIntent?.preparedRoute != nil,
            showsLaunchGoalCard: model.showsLaunchGoalCard,
            showsManualGoalPills: model.setup.showsManualGoalPills,
            showsEnableLocationChip: model.showsEnableLocationChip,
            map: AnyView(EmptyView()),
            offlineStatus: AnyView(offlineStatusBanner),
            routeCard: AnyView(launchRouteCardView),
            goalCard: AnyView(launchGoalCard),
            goalPillRow: AnyView(launchGoalPillRow),
            enableLocationChip: AnyView(enableLocationChip),
            launchDock: AnyView(launchDock),
            contextualStartControl: AnyView(EmptyView()),
            onAppear: model.prepareSetupSurface
        )
    }

    @ViewBuilder
    var launchRouteCardView: some View {
        if let route = model.setup.plannedIntent?.preparedRoute {
            launchRoutePreviewCard(route)
        }
    }

    var offlineStatusBanner: some View {
        Group {
            if model.dependencies.connectivityStore.isOffline {
                OfflineStatusBanner(compact: true)
                    .padding(.horizontal, 16)
            }
        }
    }

    var enableLocationChip: some View {
        Button {
            model.isLocationPermissionModalPresented = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "location.slash.fill")
                    .font(.caption.weight(.bold))
                Text(String(localized: "record.location.chip.label", defaultValue: "Enable location"))
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(theme.actionColor, in: Capsule())
            .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "record.location.chip.accessibility", defaultValue: "Enable location access"))
        .accessibilityHint(String(localized: "record.location.chip.accessibility_hint", defaultValue: "Opens options to turn location access on"))
    }

    @ViewBuilder
    var launchMap: some View {
        let map = ActivityLaunchMap(
            locationManager: model.recorder.locationManager,
            route: model.setup.plannedIntent?.preparedRoute
        )
        if host.isEmbeddedInToday {
            map
        } else {
            map.ignoresSafeArea()
        }
    }

    var launchGoalCard: some View {
        Button {
            model.track(.init(.goalEditorOpened, properties: [
                .activityType: .string((model.setup.plannedIntent ?? .freestyleRun).resolvedActivityType.rawValue),
                .goalType: .string(model.analyticsGoalType)
            ]))
            if model.setup.selectedGoalMode == .curated {
                model.openCuratedWorkoutPicker()
            } else if model.setup.selectedGoalMode == .race {
                model.setup.showsRacePlanner = true
            } else if model.setup.selectedGoalMode != .freestyle {
                model.setup.setupSheet = .goal
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.setup.launchGoalValue)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    if model.autoStopAtGoalEnabled,
                       [.distance, .time, .calories].contains(model.setup.selectedGoalMode) {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.fill")
                            Text(String(localized: "today.stop.at.goal", defaultValue: "Pause at goal"))
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.accentColor)
                    } else if !model.setup.launchGoalHint.isEmpty {
                        Text(model.setup.launchGoalHint)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: model.setup.selectedGoalMode == .freestyle ? "checkmark" : "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(theme.accentColor)
                    .frame(width: 38, height: 38)
                    .background(theme.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(model.setup.selectedGoalMode == .planned || model.setup.selectedGoalMode == .freestyle)
    }

    func launchRoutePreviewCard(_ route: PreparedRoute) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "map.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(theme.actionColor.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(model.routeDistanceLabel(route))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Button(String(localized: "common.change", defaultValue: "Change")) {
                model.openRouteLibrary()
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                model.removeSelectedRoute(route)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 32, height: 32)
                    .background(.thinMaterial, in: Circle())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "record.route.remove", defaultValue: "Remove route"))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.actionColor.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: 12, y: 5)
    }
}
