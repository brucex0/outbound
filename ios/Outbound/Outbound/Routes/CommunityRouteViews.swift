import CoreLocation
import Combine
import MapKit
import SwiftUI
import UniformTypeIdentifiers

enum CommunityRouteLibraryMode { case discover, mine }

struct CommunityRouteLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CommunityRouteStore
    @StateObject private var locator = RouteDiscoveryLocator()
    @State private var query = ""
    @State private var importsFile = false
    @State private var importedRoute: PreparedRoute?
    @State private var selectedRoute: PreparedRoute?
    @State private var preparingRouteID: String?
    private let initialSelection: PreparedRoute?
    let mode: CommunityRouteLibraryMode
    private let onSelect: ((PreparedRoute?) -> Void)?

    init(mode: CommunityRouteLibraryMode = .discover) {
        self.mode = mode
        initialSelection = nil
        onSelect = nil
    }

    init(selection: PreparedRoute?, onSelect: @escaping (PreparedRoute?) -> Void) {
        mode = .discover
        initialSelection = selection
        self.onSelect = onSelect
        _selectedRoute = State(initialValue: selection)
    }

    private var routes: [CommunityRoute] { mode == .mine ? store.mine : store.discovered }

    var body: some View {
        List {
            if mode == .discover {
                Section {
                    Button { locator.requestLocation() } label: {
                        Label(
                            String(localized: "route.library.action.find_nearby", defaultValue: "Find routes near me"),
                            systemImage: "location.fill"
                        )
                    }
                    Button { importsFile = true } label: {
                        Label(
                            String(localized: "route.library.action.import", defaultValue: "Import GPX or GeoJSON"),
                            systemImage: "square.and.arrow.down"
                        )
                    }
                }
            }
            if !store.imported.isEmpty {
                Section(String(localized: "route.library.section.imported", defaultValue: "Imported routes")) {
                    ForEach(store.imported) { route in
                        importedRouteDestination(route: route) { ImportedRouteRow(route: route) }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.deleteImported(route)
                            } label: {
                                Label(
                                    String(localized: "route.library.action.delete", defaultValue: "Delete"),
                                    systemImage: "trash"
                                )
                            }
                        }
                    }
                }
            }
            Section(
                mode == .mine
                    ? String(localized: "route.library.section.saved_published", defaultValue: "Saved and published")
                    : String(localized: "route.library.section.community", defaultValue: "Community routes")
            ) {
                if store.isLoading && routes.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(String(localized: "route.library.loading", defaultValue: "Loading routes"))
                } else if routes.isEmpty {
                    ContentUnavailableView(
                        mode == .mine
                            ? String(localized: "route.library.empty.saved.title", defaultValue: "No saved routes")
                            : String(localized: "route.library.empty.community.title", defaultValue: "No routes found"),
                        systemImage: "map",
                        description: Text(
                            mode == .mine
                                ? String(localized: "route.library.empty.saved.description", defaultValue: "Publish a route from one of your activities or save a community route.")
                                : String(localized: "route.library.empty.community.description", defaultValue: "Try another search or import a route to follow.")
                        )
                    )
                } else {
                    ForEach(routes) { route in
                        communityRouteDestination(route: route) { CommunityRouteRow(route: route) }
                    }
                }
            }
        }
        .navigationTitle(
            onSelect == nil
                ? (mode == .mine
                    ? String(localized: "library.my_routes", defaultValue: "My Routes")
                    : String(localized: "route.library.title.explore", defaultValue: "Explore Routes"))
                : String(localized: "route.library.title.select", defaultValue: "Select Route")
        )
        .toolbar {
            if onSelect != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "route.library.action.close", defaultValue: "Close")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        preparingRouteID != nil
                            ? String(localized: "route.library.accessibility.preparing", defaultValue: "Preparing route")
                            : (selectedRoute == nil
                                ? String(localized: "route.library.action.remove_selection", defaultValue: "Remove Route")
                                : String(localized: "route.library.action.use_selection", defaultValue: "Use This Route"))
                    ) {
                        onSelect?(selectedRoute)
                        dismiss()
                    }
                    .disabled(
                        preparingRouteID != nil
                            || (selectedRoute == nil && initialSelection == nil)
                    )
                }
            }
        }
        .searchable(
            text: $query,
            prompt: Text(String(localized: "route.library.search.prompt", defaultValue: "Route or location"))
        )
        .onSubmit(of: .search) { Task { await store.search(query) } }
        .task {
            if mode == .mine {
                await store.refreshMine()
            } else {
                if onSelect != nil { locator.requestLocation() }
                await store.refreshDiscovery()
            }
        }
        .onChange(of: locator.location) { _, location in guard let location else { return }; Task { await store.refreshNearby(location: location) } }
        .fileImporter(isPresented: $importsFile, allowedContentTypes: [.xml, .json, .data]) { result in
            do {
                let url = try result.get(); guard url.startAccessingSecurityScopedResource() else { throw RouteImportError.invalid }; defer { url.stopAccessingSecurityScopedResource() }
                if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   fileSize > RouteFileImporter.maximumFileBytes {
                    throw RouteImportError.tooLarge
                }
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let data = try file.read(upToCount: RouteFileImporter.maximumFileBytes + 1) ?? Data()
                let route = try RouteFileImporter.parse(data: data, filename: url.lastPathComponent)
                guard store.saveImported(route) else { return }
                importedRoute = route
            } catch { store.errorMessage = error.localizedDescription }
        }
        .navigationDestination(item: $importedRoute) { route in
            if onSelect == nil {
                PreparedRoutePreview(route: route, onUse: nil)
            } else {
                PreparedRoutePreview(route: route) {
                    selectedRoute = route
                    importedRoute = nil
                    onSelect?(route)
                    dismiss()
                }
            }
        }
        .overlay(alignment: .top) { if let message = store.errorMessage { RouteToast(message: message).onTapGesture { store.errorMessage = nil } } }
    }

    @ViewBuilder
    private func importedRouteDestination<Row: View>(route: PreparedRoute, @ViewBuilder row: () -> Row) -> some View {
        if onSelect != nil {
            Button {
                selectedRoute = selectedRoute?.id == route.id ? nil : route
            } label: {
                HStack {
                    row()
                    Spacer()
                    if selectedRoute?.id == route.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel(String(localized: "route.library.accessibility.selected", defaultValue: "Selected route"))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(preparingRouteID != nil)
        } else if route.source == .imported {
            NavigationLink { PreparedRoutePreview(route: route, onUse: nil) } label: { row() }
        }
    }

    @ViewBuilder
    private func communityRouteDestination<Row: View>(route: CommunityRoute, @ViewBuilder row: () -> Row) -> some View {
        if onSelect != nil {
            Button {
                if selectedRoute?.id == route.id {
                    selectedRoute = nil
                    return
                }
                preparingRouteID = route.id
                Task {
                    let prepared = await store.prepare(route)
                    guard preparingRouteID == route.id else { return }
                    selectedRoute = prepared
                    preparingRouteID = nil
                }
            } label: {
                HStack {
                    row()
                    Spacer()
                    if preparingRouteID == route.id {
                        ProgressView()
                            .accessibilityLabel(String(localized: "route.library.accessibility.preparing", defaultValue: "Preparing route"))
                    } else if selectedRoute?.id == route.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel(String(localized: "route.library.accessibility.selected", defaultValue: "Selected route"))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(preparingRouteID != nil)
        } else {
            NavigationLink { CommunityRouteDetailView(route: route) } label: { row() }
        }
    }
}

private struct ImportedRouteRow: View {
    let route: PreparedRoute

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down")
                .foregroundStyle(.orange)
                .frame(width: 34, height: 34)
                .background(.orange.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(route.name).font(.headline)
                Text(String(localized: "route.library.imported.device_private", defaultValue: "Private on this device"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CommunityRouteRow: View {
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    let route: CommunityRoute
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: route.routeShape == "loop" ? "arrow.triangle.2.circlepath" : "point.topleft.down.to.point.bottomright.curvepath")
                .foregroundStyle(.orange).frame(width: 34, height: 34).background(.orange.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(route.name).font(.headline)
                Text(
                    String(
                        format: String(
                            localized: "route.library.row.summary_format",
                            defaultValue: "%1$@ · by %2$@"
                        ),
                        locale: .autoupdatingCurrent,
                        measurementPreferences.unitSystem.distanceString(meters: route.distanceM, fractionDigits: 1),
                        route.owner.displayName
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if route.isBookmarked && !route.isOwnedByCurrentUser {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(String(localized: "route.library.accessibility.saved", defaultValue: "Saved to My Routes"))
            }
        }
    }
}

struct CommunityRouteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var store: CommunityRouteStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    let route: CommunityRoute
    @State private var preparedRoute: PreparedRoute?
    @State private var isPreparingRoute = true
    @State private var isBookmarked: Bool
    @State private var isMutatingMembership = false
    @State private var showsRemovePublishedConfirmation = false
    @State private var feedbackMessage: String?

    init(route: CommunityRoute) {
        self.route = route
        _isBookmarked = State(initialValue: route.isBookmarked)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Group {
                    if let preparedRoute {
                        RoutePreviewMap(points: preparedRoute.points)
                    } else if isPreparingRoute {
                        ZStack {
                            Color(.secondarySystemBackground)
                            ProgressView()
                                .accessibilityLabel(String(localized: "route.library.detail.loading", defaultValue: "Loading route details"))
                        }
                    } else {
                        ContentUnavailableView {
                            Label(
                                String(localized: "route.library.detail.unavailable.title", defaultValue: "Route unavailable"),
                                systemImage: "wifi.exclamationmark"
                            )
                        } description: {
                            Text(
                                String(
                                    localized: "route.library.detail.unavailable.description",
                                    defaultValue: "Connect to the internet and try loading the route again."
                                )
                            )
                        } actions: {
                            Button(String(localized: "route.library.detail.retry", defaultValue: "Try Again")) {
                                Task { await prepareRoute() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(height: 310)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 6) {
                    Text(route.name).font(.title2.bold())
                    Text(
                        String(
                            format: String(
                                localized: "route.library.detail.creator_format",
                                defaultValue: "Created by %@"
                            ),
                            locale: .autoupdatingCurrent,
                            route.owner.displayName
                        )
                    )
                    .foregroundStyle(.secondary)
                    HStack {
                        Label(measurementPreferences.unitSystem.distanceString(meters: route.distanceM, fractionDigits: 1), systemImage: "arrow.left.and.right")
                        if let elevation = route.elevationGainM { Label(measurementPreferences.unitSystem.elevationString(meters: elevation), systemImage: "mountain.2") }
                    }.font(.subheadline.weight(.semibold))
                    Text(
                        String(
                            format: String(
                                localized: "route.library.detail.stats_format",
                                defaultValue: "Saves: %1$lld · Completions: %2$lld"
                            ),
                            locale: .autoupdatingCurrent,
                            route.bookmarkCount,
                            route.completionCount
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if let description = route.description { Text(description).padding(.top, 4) }
                }
                Button {
                    guard let preparedRoute else { return }
                    store.launch(preparedRoute)
                } label: {
                    Label(
                        String(localized: "route.library.action.start", defaultValue: "Start Route Guidance"),
                        systemImage: routeActivitySystemImage(ActivityType(rawValue: route.activityType))
                    )
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(preparedRoute == nil)
                routeMembershipButton
            }.padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepareRoute() }
        .confirmationDialog(
            String(
                localized: "route.library.remove_published.confirmation_title",
                defaultValue: "Remove published route?"
            ),
            isPresented: $showsRemovePublishedConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                String(
                    localized: "route.library.remove_published.confirm",
                    defaultValue: "Remove Published Route"
                ),
                role: .destructive
            ) {
                Task { await removePublishedRoute() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(
                String(
                    localized: "route.library.remove_published.confirmation_message",
                    defaultValue: "This route will disappear from My Routes and the community. Your original activity will not be deleted."
                )
            )
        }
        .overlay(alignment: .top) {
            if let feedbackMessage {
                RouteToast(message: feedbackMessage)
                    .onTapGesture { self.feedbackMessage = nil }
            }
        }
        .task(id: feedbackMessage) {
            guard feedbackMessage != nil else { return }
            try? await Task.sleep(for: .seconds(2.5))
            feedbackMessage = nil
        }
    }

    @ViewBuilder
    private var routeMembershipButton: some View {
        if route.isOwnedByCurrentUser {
            Button(role: .destructive) {
                showsRemovePublishedConfirmation = true
            } label: {
                Label(
                    String(
                        localized: "route.library.remove_published.action",
                        defaultValue: "Remove Published Route"
                    ),
                    systemImage: "trash"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isMutatingMembership)
        } else {
            Button {
                Task { await updateBookmark() }
            } label: {
                if isMutatingMembership {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(
                            String(
                                localized: "route.library.bookmark.updating",
                                defaultValue: "Updating saved route"
                            )
                        )
                } else {
                    Label(
                        isBookmarked
                            ? String(localized: "library.my_routes.remove", defaultValue: "Remove from My Routes")
                            : String(localized: "library.my_routes.save", defaultValue: "Save to My Routes"),
                        systemImage: isBookmarked ? "bookmark.slash" : "bookmark"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(isMutatingMembership)
        }
    }

    private func prepareRoute() async {
        isPreparingRoute = true
        store.errorMessage = nil
        preparedRoute = await store.prepare(route)
        isPreparingRoute = false
    }

    private func updateBookmark() async {
        isMutatingMembership = true
        defer { isMutatingMembership = false }
        let requestedState = !isBookmarked
        guard let updatedState = await store.setBookmarked(route, bookmarked: requestedState) else {
            feedbackMessage = store.errorMessage
                ?? String(localized: "Route could not be saved. Try again.")
            store.errorMessage = nil
            track(.init(.routeBookmarkChanged, properties: [.result: .string("failed")]))
            return
        }
        isBookmarked = updatedState
        track(.init(.routeBookmarkChanged, properties: [
            .result: .string(updatedState ? "saved" : "removed"),
        ]))
    }

    private func removePublishedRoute() async {
        isMutatingMembership = true
        defer { isMutatingMembership = false }
        guard await store.removePublishedRoute(route) else {
            feedbackMessage = store.errorMessage
                ?? String(
                    localized: "route.library.remove_published.error",
                    defaultValue: "Published route could not be removed. Try again."
                )
            store.errorMessage = nil
            track(.init(.routePublicationRemoved, properties: [.result: .string("failed")]))
            return
        }
        track(.init(.routePublicationRemoved, properties: [.result: .string("removed")]))
        dismiss()
    }

    private func track(_ event: ProductAnalyticsEvent) {
        guard let analyticsManager else { return }
        Task { await analyticsManager.track(event) }
    }
}

private struct PreparedRoutePreview: View {
    @EnvironmentObject private var store: CommunityRouteStore
    let route: PreparedRoute
    let onUse: (() -> Void)?
    var body: some View {
        VStack(spacing: 20) {
            RoutePreviewMap(points: route.points).clipShape(RoundedRectangle(cornerRadius: 18))
            VStack(spacing: 5) {
                Text(route.name).font(.title2.bold())
                Text(
                    String(
                        localized: "route.import.preview.privacy",
                        defaultValue: "Imported routes stay private on this device until you complete and save your own activity."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            Button {
                if let onUse { onUse() } else { store.launch(route) }
            } label: {
                Label(
                    String(localized: "route.import.action.use", defaultValue: "Use for Route Guidance"),
                    systemImage: routeActivitySystemImage(route.activityType)
                )
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            Button(role: .destructive) { store.deleteImported(route) } label: {
                Label(
                    String(localized: "route.import.action.delete", defaultValue: "Delete Imported Route"),
                    systemImage: "trash"
                )
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .navigationTitle(String(localized: "route.import.preview.title", defaultValue: "Preview Route"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func routeActivitySystemImage(_ activityType: ActivityType?) -> String {
    activityType.map { SportType(activityType: $0).systemImage } ?? "map.fill"
}

struct RoutePreviewMap: View {
    private let showsEndpoints: Bool
    @StateObject private var geometry: RoutePreviewGeometry
    @State private var position: MapCameraPosition = .automatic

    init(points: [RouteCoordinate], showsEndpoints: Bool = false) {
        self.showsEndpoints = showsEndpoints
        _geometry = StateObject(wrappedValue: RoutePreviewGeometry(points: points))
    }

    var body: some View {
        Map(position: $position) {
            if geometry.coordinates.count > 1 {
                MapPolyline(coordinates: geometry.coordinates)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if showsEndpoints, let start = geometry.start {
                Annotation(
                    geometry.endpointsOverlap
                        ? String(localized: "route.guidance.map.start_finish", defaultValue: "Route start and finish")
                        : String(localized: "route.guidance.map.start", defaultValue: "Route start"),
                    coordinate: start
                ) {
                    Image(systemName: geometry.endpointsOverlap ? "flag.checkered" : "flag.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(geometry.endpointsOverlap ? Color.orange : Color.green, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            if showsEndpoints,
               !geometry.endpointsOverlap,
               let finish = geometry.finish {
                Annotation(
                    String(localized: "route.guidance.map.finish", defaultValue: "Route finish"),
                    coordinate: finish
                ) {
                    Image(systemName: "flag.checkered")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.orange, in: Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
            .mapStyle(.standard(elevation: .realistic))
            .accessibilityLabel(String(localized: "route.library.map.accessibility_label", defaultValue: "Route preview map"))
            .onAppear { position = .rect(geometry.mapRect) }
    }
}

private final class RoutePreviewGeometry: ObservableObject {
    let coordinates: [CLLocationCoordinate2D]
    let mapRect: MKMapRect
    let start: CLLocationCoordinate2D?
    let finish: CLLocationCoordinate2D?
    let endpointsOverlap: Bool

    init(points: [RouteCoordinate]) {
        coordinates = RouteWorkingGeometry.displayPoints(points).map(\.locationCoordinate)
        start = coordinates.first
        finish = coordinates.last

        let bounds = coordinates.reduce(MKMapRect.null) { partial, coordinate in
            let mapPoint = MKMapPoint(coordinate)
            return partial.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 1, height: 1))
        }
        mapRect = bounds.isNull
            ? .world
            : bounds.insetBy(dx: -2_000, dy: -2_000)

        if let start, let finish {
            endpointsOverlap = MKMapPoint(start).distance(to: MKMapPoint(finish)) <= 20
        } else {
            endpointsOverlap = false
        }
    }
}

private struct RouteToast: View { let message: String; var body: some View { Label(message, systemImage: "exclamationmark.circle.fill").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 10).background(.regularMaterial, in: Capsule()).shadow(radius: 8).padding(.top, 8) } }

final class RouteDiscoveryLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    private let manager = CLLocationManager()
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyKilometer }
    func requestLocation() { if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }; manager.requestLocation() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { location = locations.last }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
