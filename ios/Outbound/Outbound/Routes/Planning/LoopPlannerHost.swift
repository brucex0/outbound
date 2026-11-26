import CoreLocation
import MapKit
import SwiftUI

/// Composition root: callers receive a selected canonical route, or cancellation.
/// No workout ownership or workout mutations live inside this host.
struct LoopPlannerHost: View {
    @EnvironmentObject private var routeStore: CommunityRouteStore
    @ObservedObject var presentation: LoopPlanningPresentation
    private var session: LoopPlanningSession { presentation.session }
    let onSelect: (PreparedRoute) -> Void
    let onSavedSelection: (PreparedRoute?) -> Void
    let onCancel: () -> Void
    var body: some View {
        LoopPlannerScreen(presentation: presentation, session: session, onUse: { candidate, number in
            guard session.current, session.resultsCurrent, session.candidates.contains(where: { $0.id == candidate.id }) else { return false }
            let name = candidate.name ?? String(format: String(localized: "route.planner.route_number", defaultValue: "Loop %d"), number)
            let route = PreparedRoute(id: candidate.id, name: name,
                points: candidate.points.map { RouteCoordinate(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude) },
                source: candidate.source == .community ? .community : .generated,
                activityType: session.activity, routeShape: "loop", attribution: candidate.attribution, preservesWorkoutContext: true)
            guard route.isUsableForGuidance, routeStore.persistPlannerSelection(route) else { return false }
            onSelect(route); return true
        }, onSavedSelection: { route in
            // Selection policy belongs to this opening; canonical caches remain unchanged.
            onSavedSelection(route.map {
                PreparedRoute(id: $0.id, name: $0.name, points: $0.points, source: $0.source,
                              activityType: $0.activityType, routeShape: $0.routeShape, direction: $0.direction,
                              attribution: $0.attribution, preservesWorkoutContext: true)
            })
        }, onCancel: onCancel)
    }
}

private struct LoopPlannerScreen: View {
    @Environment(\.outboundTheme) private var theme
    @Environment(\.analyticsManager) private var analytics
    @ObservedObject var presentation: LoopPlanningPresentation
    @ObservedObject var session: LoopPlanningSession
    @State private var camera: MapCameraPosition = .automatic
    private var detail: LoopPlanningCandidate? { presentation.detail }
    @FocusState private var placeSearchFocused: Bool
    @State private var query = ""
    @State private var distanceDraft = ""
    @State private var climbingDraft = false
    let onUse: (LoopPlanningCandidate, Int) -> Bool
    let onSavedSelection: (PreparedRoute?) -> Void
    let onCancel: () -> Void
    var body: some View {
        NavigationStack {
            map
                .safeAreaInset(edge: .top) { mapControls }
                .safeAreaInset(edge: .bottom) { comparison }
                .navigationTitle(String(localized: "route.planner.title", defaultValue: "Find a loop"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String(localized: "Back")) { presentation.cancel(); onCancel() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(String(localized: "route.planner.saved_routes", defaultValue: "Saved routes")) {
                            presentation.openSavedRoutes()
                            Task { await analytics?.track(.init(.routeLibraryOpened)) }
                        }.accessibilityIdentifier("loop.saved_routes")
                    }
                }
                .overlay(alignment: .top) { if let toast = session.toast { RouteToast(message: toast) } }
                .sheet(item: $presentation.sheet) { sheetContent($0) }
                .onChange(of: session.generation) { _, generation in
                    guard let generation else { return }
                    Task { await analytics?.track(.init(.activityConfigurationChanged, properties: [
                        .changeType: .string("loop_planner_generate"), .activityType: .string(session.activity.rawValue),
                        .entrySource: .string(generation.trigger.rawValue)])) }
                }
                .onChange(of: session.cacheEvent) { _, event in
                    guard let event else { return }
                    Task { await analytics?.track(.init(.featureExposed, properties: [
                        .feature: .string("loop_planner_cache"), .result: .string(event.result)])) }
                }
                .onChange(of: session.resultsCurrent) { _, current in
                    if !current, detail != nil { presentation.sheet = nil }
                }
                .onChange(of: session.candidates.map(\.points)) { _, _ in fitCandidates() }
                .onChange(of: session.busy) { wasBusy, busy in
                    if wasBusy && !busy && session.candidates.isEmpty && (session.searched || session.generationUnavailable) {
                        centerOnStart()
                    }
                }
#if DEBUG && targetEnvironment(simulator)
                .onReceive(NotificationCenter.default.publisher(for: TodayPrescriptionRefreshProbe.notification)) { _ in
                    if ProcessInfo.processInfo.arguments.contains("-OutboundUITestDeferredPlannerLocation"), session.start == nil, !session.locating {
                        session.requestLocation(trigger: .initialLocation)
                    }
                }
#endif
                .task {
                    presentation.startIfNeeded()
                    await analytics?.track(.init(.featureExposed, properties: [.feature: .string("loop_planner")]))
                }
        }
#if DEBUG
        .background {
            if ProcessInfo.processInfo.arguments.contains("-OutboundDebugPlannerFrameProbe") {
                LoopPlannerFrameProbe(presentation: presentation).frame(width: 1, height: 1)
            }
        }
#endif
    }
    private var distanceButton: some View {
        Button { distanceDraft = session.distanceText; presentation.sheet = .distance } label: {
            Text(session.distanceM.map { session.units.distanceString(meters: $0, fractionDigits: 1) }
                 ?? String(localized: "route.planner.distance", defaultValue: "Distance")).outboundTapTarget()
        }.accessibilityIdentifier("loop.distance")
    }
    private var startButton: some View {
        Button { query = ""; session.clearSearch(); presentation.sheet = .location } label: {
            Label(String(localized: "route.planner.start", defaultValue: "Start"), systemImage: "location").outboundTapTarget()
        }.accessibilityIdentifier("loop.start")
    }
    private var optionsButton: some View {
        Button { climbingDraft = session.lessClimbing; presentation.sheet = .options } label: {
            Image(systemName: "slider.horizontal.3").outboundTapTarget()
        }.accessibilityLabel(String(localized: "route.planner.options", defaultValue: "Route options")).accessibilityIdentifier("loop.options")
    }
    private var mapControls: some View {
        // Only lightweight controls participate in fitting; all state and the
        // native presentation owner remain above these layout candidates.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: OutboundSpacing.compact) { distanceButton; startButton; Spacer(minLength: 0); optionsButton }
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) { distanceButton; startButton; optionsButton }
        }
        .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
        .padding(.horizontal, OutboundSpacing.screen).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
    }
    private var comparison: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
            if session.choosingStart {
                HStack {
                    Text(String(localized: "route.planner.tap_start", defaultValue: "Tap the map to move the start.")).font(.footnote)
                    Button(String(localized: "Cancel")) { session.cancelChoosingPoint() }
                }
            }
            if session.locating {
                ProgressView(String(localized: "route.planner.locating", defaultValue: "Finding your location…"))
            } else if session.busy {
                ProgressView(String(localized: "route.planner.searching", defaultValue: "Finding loops…"))
            } else if session.locationUnavailable {
                Text(String(localized: "route.planner.location_unavailable", defaultValue: "Choose a start on the map or enable location access in Settings.")).font(.footnote)
                Button(String(localized: "route.planner.choose_start", defaultValue: "Choose a start")) { query = ""; presentation.sheet = .location }
            } else if session.generationUnavailable && (!session.resultsCurrent || session.candidates.isEmpty) {
                Text(session.generationFailureMessage).font(.footnote).foregroundStyle(.secondary)
            } else if !session.supported {
                Text(String(localized: "route.planner.unsupported", defaultValue: "Loop planning is not available for this activity yet.")).font(.footnote)
            } else if session.searched && session.candidates.isEmpty {
                Text(String(localized: "route.planner.no_results", defaultValue: "No loops found within ±10%. Try another start, distance or via place.")).font(.footnote).foregroundStyle(.secondary)
                Button(String(localized: "route.planner.move_start", defaultValue: "Move start")) { moveStart() }
            }
            if !session.candidates.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: OutboundSpacing.compact) {
                        ForEach(Array(session.candidates.enumerated()), id: \.element.id) { index, candidate in
                            Button { presentation.sheet = .details(candidate) } label: {
                                candidateCard(candidate, number: index + 1).frame(width: 210)
                            }.buttonStyle(.plain).disabled(!session.resultsCurrent)
                                .accessibilityIdentifier("loop.candidate.\(index)")
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            if !session.busy && !session.locating && session.start != nil && !session.choosingStart && !session.locationUnavailable {
                Button(session.resultsCurrent && !session.candidates.isEmpty
                       ? String(localized: "route.planner.new_routes", defaultValue: "New routes")
                       : String(localized: "route.planner.retry", defaultValue: "Try again")) { session.generate() }
                    .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                    .disabled(!session.canGenerate)
            }
        }.padding(OutboundSpacing.standard).background(.regularMaterial)
    }
    @ViewBuilder private func sheetContent(_ sheet: LoopPlanningPresentation.Sheet) -> some View {
        switch sheet {
        case .savedRoutes:
            NavigationStack {
                CommunityRouteLibraryView(draft: presentation.savedDraft, onClose: { presentation.sheet = nil }) { route in
                    guard session.current else { return }
                    onSavedSelection(route)
                }.savedRoutesOnly()
            }
        case .details(let candidate):
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                        candidateCard(candidate, number: (session.candidates.firstIndex(where: { $0.id == candidate.id }) ?? 0) + 1)
                        Text(candidate.source == .community
                             ? String(localized: "route.planner.existing_route", defaultValue: "Community route")
                             : String(localized: "route.planner.generated_route", defaultValue: "Generated route")).font(.caption).foregroundStyle(.secondary)
                        Text(candidate.attribution).font(.caption).foregroundStyle(.secondary)
                        Text(String(format: String(localized: "route.planner.start_distance", defaultValue: "Route starts %@ from your chosen start"), session.units.distanceString(meters: startDistance(candidate), fractionDigits: 2)))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button(String(localized: "route.detail.action.use_route", defaultValue: "Use route")) { use(candidate) }
                            .buttonStyle(.borderedProminent).tint(theme.actionColor)
                            .buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control)).disabled(!session.resultsCurrent)
                    }.padding(OutboundSpacing.screen)
                }
                .navigationTitle(String(localized: "route.planner.route_details", defaultValue: "Route details"))
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "Close")) { presentation.sheet = nil } } }
            }
            .overlay(alignment: .top) { if let toast = session.toast { RouteToast(message: toast) } }
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        default:
            NavigationStack {
                ScrollView { editor(sheet).padding(OutboundSpacing.screen) }
                    .navigationTitle(editorTitle(sheet))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "Close")) { presentation.sheet = nil } } }
            }
            .overlay(alignment: .top) { if let toast = session.toast { RouteToast(message: toast) } }
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .startupUIStabilityDiagnostics("loop_inputs")
        }
    }
    private func editorTitle(_ sheet: LoopPlanningPresentation.Sheet) -> String {
        switch sheet {
        case .distance: String(localized: "route.planner.distance", defaultValue: "Distance")
        case .location: String(localized: "route.planner.start", defaultValue: "Start")
        case .via: String(localized: "route.planner.include_place", defaultValue: "Include a place")
        default: String(localized: "route.planner.options", defaultValue: "Route options")
        }
    }
    @ViewBuilder private func editor(_ sheet: LoopPlanningPresentation.Sheet) -> some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
            switch sheet {
            case .distance:
                HStack {
                    TextField(session.units.distanceUnit, text: $distanceDraft).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        .accessibilityLabel(String(localized: "route.planner.distance", defaultValue: "Distance"))
                    Text(session.units.distanceUnit)
                }
                ViewThatFits(in: .horizontal) {
                    HStack { distancePresets }
                    VStack(alignment: .leading) { distancePresets }
                }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                Button(String(localized: "Done")) {
                    presentation.sheet = nil; session.applyDistance(distanceDraft)
                }.buttonStyle(.borderedProminent).tint(theme.actionColor)
                    .buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                    .disabled(!session.validDistanceText(distanceDraft))
            case .location, .via:
                if case .location = sheet {
                    ViewThatFits(in: .horizontal) {
                        HStack { locationActions }
                        VStack(alignment: .leading) { locationActions }
                    }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                }
                HStack {
                    TextField(String(localized: "route.planner.search_places", defaultValue: "Search places"), text: $query)
                        .textFieldStyle(.roundedBorder).focused($placeSearchFocused).autocorrectionDisabled()
                        .submitLabel(.search).onSubmit { submitPlaceSearch() }
                        .onChange(of: query) { _, value in session.queryChanged(value) }
                    Button { submitPlaceSearch() } label: { Image(systemName: "magnifyingglass").outboundTapTarget() }
                        .accessibilityLabel(String(localized: "Search")).accessibilityIdentifier("loop.place.search")
                }
                if session.placeSearchState == .loading {
                    ProgressView(String(localized: "route.planner.searching_places", defaultValue: "Searching places…"))
                } else if session.placeSearchState == .empty {
                    Text(String(localized: "route.planner.no_places", defaultValue: "No places found. Try another address.")).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(Array(session.places.enumerated()), id: \.element.id) { index, place in
                    Button { choose(place, asVia: isVia(sheet)) } label: { Text(place.name).outboundTapTarget() }
                        .accessibilityIdentifier("loop.place.\(index)")
                }
                if isVia(sheet) {
                    if session.via != nil {
                        Button(String(localized: "route.planner.remove_via", defaultValue: "Remove via place")) { presentation.sheet = nil; session.setVia(nil, lessClimbing: climbingDraft) }
                    }
                    ForEach(session.recommendations) { place in
                        Button { choose(place, asVia: true) } label: { Label(place.name, systemImage: "leaf").outboundTapTarget() }
                    }
                }
            case .options:
                Toggle(String(localized: "route.planner.less_climbing", defaultValue: "Less climbing"), isOn: $climbingDraft).accessibilityIdentifier("loop.less_climbing")
                Button(String(localized: "route.planner.include_place", defaultValue: "Include a place")) {
                    query = ""; session.clearSearch(); presentation.sheet = .via
                }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                Button(String(localized: "Done")) { presentation.sheet = nil; session.applyPreference(lessClimbing: climbingDraft) }
                    .buttonStyle(.borderedProminent).tint(theme.actionColor).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
            default: EmptyView()
            }
        }
    }
    private var distancePresets: some View {
        ForEach([3,5,10], id: \.self) { value in
            Button { distanceDraft = String(value) } label: { Text("\(value) \(session.units.distanceUnit)").outboundTapTarget() }
        }
    }
    @ViewBuilder private var locationActions: some View {
        Button { presentation.sheet = nil; session.requestLocation() } label: {
            Label(String(localized: "route.planner.my_location", defaultValue: "My location"), systemImage: "location").outboundTapTarget()
        }
        Button { moveStart() } label: {
            Text(String(localized: "route.planner.move_start", defaultValue: "Move start")).outboundTapTarget()
        }
    }
    private func isVia(_ sheet: LoopPlanningPresentation.Sheet) -> Bool { if case .via = sheet { true } else { false } }
    private func submitPlaceSearch() {
        placeSearchFocused = false
        session.search(query)
    }
    private func choose(_ place: LoopPlanningPlace, asVia: Bool) {
        presentation.sheet = nil; session.clearSearch(); query = ""
        if asVia { session.setVia(place.coordinate, lessClimbing: climbingDraft) } else { session.setStart(place.coordinate) }
    }
    private func moveStart() {
        session.beginChoosingPoint(); presentation.sheet = nil; centerOnStart()
    }
    private func centerOnStart() {
        guard let start = session.start else { return }
        camera = .region(.init(center: start.locationCoordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
    }
    private func fitCandidates() {
        let points = session.candidates.flatMap(\.points).map { MKMapPoint($0.locationCoordinate) }
        guard let first = points.first else { return }
        let rect = points.dropFirst().reduce(MKMapRect(origin: first, size: MKMapSize(width: 1, height: 1))) {
            $0.union(MKMapRect(origin: $1, size: MKMapSize(width: 1, height: 1)))
        }
        camera = .rect(rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2))
    }
    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let start = session.start { Marker(String(localized: "route.planner.start", defaultValue: "Start"), systemImage: "figure.walk", coordinate: start.locationCoordinate).tint(theme.accentColor) }
                if let via = session.via { Marker(String(localized: "route.planner.via", defaultValue: "Via place"), systemImage: "mappin", coordinate: via.locationCoordinate).tint(theme.secondaryColor) }
                ForEach(Array(session.candidates.enumerated()), id: \.element.id) { index, candidate in
                    MapPolyline(coordinates: displayPoints(candidate)).stroke(routeColor(index).opacity(detail == nil || detail?.id == candidate.id ? 1 : 0.25), lineWidth: detail?.id == candidate.id ? 7 : 4)
                    if let midpoint = candidate.points.dropFirst(candidate.points.count / 2).first {
                        Annotation("\(index + 1)", coordinate: midpoint.locationCoordinate) {
                            Button { guard session.resultsCurrent else { return }; presentation.sheet = .details(candidate) } label: {
                                Text("\(index + 1)").font(.headline).padding(10).background(.regularMaterial, in: Circle())
                                    .overlay(Circle().stroke(routeColor(index).opacity(detail == nil || detail?.id == candidate.id ? 1 : 0.25), lineWidth: 3))
                                    .outboundTapTarget()
                            }.accessibilityLabel(candidateTitle(candidate, number: index + 1))
                        }
                    }
                }
            }
            .accessibilityIdentifier("loop.map")
            .startupUIStabilityDiagnostics("loop_map")
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                guard let point = proxy.convert(tap.location, from: .local) else { return }
                if session.choosingStart {
                    session.setStart(.init(latitude: point.latitude, longitude: point.longitude)); return
                }
                if session.resultsCurrent, let candidate = nearestCandidate(point) { presentation.sheet = .details(candidate) }
            })
        }
    }
    private func candidateCard(_ candidate: LoopPlanningCandidate, number: Int) -> some View {
        HStack(alignment: .top, spacing: OutboundSpacing.standard) {
            Text("\(number)").font(.headline).padding(10).background(routeColor(number-1).opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(candidateTitle(candidate, number: number)).font(.headline)
                Text(session.units.distanceString(meters: candidate.distanceM, fractionDigits: 2)).font(.subheadline)
                if let gain = candidate.elevationGainM {
                    Text(String(format: String(localized: "route.planner.ascent", defaultValue: "%@ climbing"), session.units.elevationString(meters: gain))).font(.caption).foregroundStyle(.secondary)
                }
                if candidate.source == .community {
                    Text(String(localized: "route.planner.existing_route", defaultValue: "Community route")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }.padding(OutboundSpacing.standard).background(.regularMaterial, in: RoundedRectangle(cornerRadius: OutboundRadius.card)).outboundTapTarget()
    }
    private func candidateTitle(_ candidate: LoopPlanningCandidate, number: Int) -> String {
        candidate.name ?? String(format: String(localized: "route.planner.route_number", defaultValue: "Loop %d"), number)
    }
    private func use(_ candidate: LoopPlanningCandidate) {
        guard session.current, session.resultsCurrent else { return }
        let number = (session.candidates.firstIndex(where: { $0.id == candidate.id }) ?? 0) + 1
        guard onUse(candidate, number) else {
            session.showToast(String(localized: "route.planner.save_failed", defaultValue: "Route could not be saved on this device. Try again.")); return
        }
        session.cancel(); presentation.sheet = nil
    }
    private func startDistance(_ candidate: LoopPlanningCandidate) -> Double {
        CLLocation(latitude: candidate.requestedStart.latitude, longitude: candidate.requestedStart.longitude)
            .distance(from: CLLocation(latitude: candidate.snappedStart.latitude, longitude: candidate.snappedStart.longitude))
    }
    private func displayPoints(_ candidate: LoopPlanningCandidate) -> [CLLocationCoordinate2D] {
        let step = max(1, candidate.points.count / 2000)
        var result = stride(from: 0, to: candidate.points.count, by: step).map { candidate.points[$0].locationCoordinate }
        if let last = candidate.points.last { result.append(last.locationCoordinate) }; return result
    }
    private func nearestCandidate(_ point: CLLocationCoordinate2D) -> LoopPlanningCandidate? {
        let origin = MKMapPoint(point)
        return session.candidates.compactMap { candidate -> (LoopPlanningCandidate, Double)? in
            let points = displayPoints(candidate).map(MKMapPoint.init)
            let minimum = zip(points, points.dropFirst()).map { a,b -> Double in
                let dx = b.x-a.x, dy = b.y-a.y, denominator = dx*dx+dy*dy
                let t = denominator > 0 ? min(1,max(0,((origin.x-a.x)*dx+(origin.y-a.y)*dy)/denominator)) : 0
                return origin.distance(to: .init(x: a.x+t*dx, y: a.y+t*dy))
            }.min() ?? .infinity
            return minimum < 100 ? (candidate, minimum) : nil
        }.min(by: { $0.1 < $1.1 })?.0
    }
    private func routeColor(_ index: Int) -> Color {
        // Route identity colors are semantic and paired with visible numbers.
        switch index % 3 { case 0: .blue; case 1: .orange; default: .purple }
    }
}

private extension LoopPlanningCoordinate {
    var locationCoordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
