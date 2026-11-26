import SwiftUI
import Combine
import PhotosUI
import CoreLocation
import MapKit
import UIKit

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
            showsLaunchGoalCard: model.setup.selectedWorkoutChoice != .planned,
            showsManualGoalPills: false,
            showsEnableLocationChip: model.showsEnableLocationChip,
            map: AnyView(EmptyView()),
            offlineStatus: AnyView(offlineStatusBanner),
            routeCard: AnyView(launchRouteCardView),
            goalCard: AnyView(compactLaunchGoalCard),
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
            if host.isEmbeddedInToday {
                ActivityLaunchRoutePill(
                    name: route.name,
                    distance: compactLaunchUnits(model.routeDistanceLabel(route)),
                    onChange: model.openRouteLibrary,
                    onRemove: { model.removeSelectedRoute(route) }
                ) { change, remove in
                    AnyView(routeDetailsPopover(onChange: change, onRemove: remove))
                }
            } else {
                launchRoutePreviewCard(route)
            }
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
            if host.isEmbeddedInToday {
                HStack(spacing: 4) {
                    if model.autoStopAtGoalEnabled,
                       [.distance, .time, .calories].contains(model.setup.selectedGoalMode) {
                        Image(systemName: "pause.fill")
                            .accessibilityLabel(String(localized: "today.stop.at.goal", defaultValue: "Pause at goal"))
                    }
                    Text([SessionGoalMode.distance, .time, .calories, .race].contains(model.setup.selectedGoalMode)
                         ? compactLaunchUnits(model.setup.launchGoalValue) : model.setup.launchGoalValue)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(.regularMaterial, in: Capsule())
                .outboundTapTarget()
                .accessibilityHint(model.setup.launchGoalHint)
            } else {
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
                        }
                        if !model.setup.launchGoalHint.isEmpty {
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
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activity.goal.edit")
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

/// Remove only number/unit whitespace; preserve spaces in workout and route names.
private func compactLaunchUnits(_ value: String) -> String {
    value.replacingOccurrences(of: "(?<=\\d)[\\s\\u00a0\\u202f]+(?=[^\\W\\d_])", with: "", options: .regularExpression)
        .replacingOccurrences(of: "[.,]0(?=[^\\W\\d_])", with: "", options: .regularExpression)
}

private struct ActivityLaunchRoutePill: View {
    let name: String
    let distance: String
    let onChange: () -> Void
    let onRemove: () -> Void
    let details: (@escaping () -> Void, @escaping () -> Void) -> AnyView
    @State private var showsDetails = false
    @StateObject private var dismissal = ActivityLaunchRouteDismissal()

    var body: some View {
        Button { showsDetails = true } label: {
            HStack(spacing: 6) {
                Text(name)
                    .fixedSize(horizontal: false, vertical: true)
                Text(distance)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, OutboundSpacing.compact)
            .frame(minHeight: 44)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: OutboundRadius.card, style: .continuous))
            .outboundTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(distance)")
        .popover(isPresented: $showsDetails) {
            details(
                { dismissal.dismiss { showsDetails = false; onChange() } },
                { dismissal.dismiss { showsDetails = false; onRemove() } }
            )
            .background(ActivityLaunchRouteDismissalAnchor(dismissal: dismissal).frame(width: 0, height: 0))
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// SwiftUI popovers have no dismissal-completion hook. The anchor keeps route
/// selection from presenting until UIKit has fully removed this popover.
@MainActor
private final class ActivityLaunchRouteDismissal: ObservableObject {
    weak var anchor: UIViewController?

    func dismiss(completion: @escaping () -> Void) {
        guard var controller = anchor else {
            ActivityDiagnosticLog.error(.lifecycle, "route_details_dismiss_failed reason=missing_anchor")
            return
        }
        while let parent = controller.parent { controller = parent }
        guard controller.presentingViewController != nil else {
            ActivityDiagnosticLog.error(.lifecycle, "route_details_dismiss_failed reason=missing_presentation")
            return
        }
        controller.dismiss(animated: true, completion: completion)
    }
}

private struct ActivityLaunchRouteDismissalAnchor: UIViewControllerRepresentable {
    let dismissal: ActivityLaunchRouteDismissal

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        dismissal.anchor = controller
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        dismissal.anchor = uiViewController
    }
}
