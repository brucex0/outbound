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
            let name = session.candidateTitle(candidate, number: number)
            let route = session.restoredRoute.flatMap { $0.id == candidate.id ? $0.preservingWorkoutContext() : nil } ?? PreparedRoute(id: candidate.id, name: name,
                points: candidate.points.map { RouteCoordinate(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude) },
                source: PreparedRoute.Source(rawValue: candidate.source.rawValue) ?? .imported,
                activityType: session.activity, routeShape: "loop", attribution: candidate.attribution, preservesWorkoutContext: true)
            guard route.isUsableForGuidance, routeStore.persistPlannerSelection(route), ActivityLaunchPreferenceStore.selectRoute(route) else { return false }
            onSelect(route); return true
        }, onSavedSelection: { route in
            guard ActivityLaunchPreferenceStore.selectRoute(route) else {
                session.showToast(String(localized: "route.planner.save_failed", defaultValue: "Route could not be saved on this device. Try again.")); return
            }
            // Selection policy belongs to this opening; canonical caches remain unchanged.
            onSavedSelection(route.map {
                PreparedRoute(id: $0.id, name: $0.name, points: $0.points, source: $0.source,
                              activityType: $0.activityType, routeShape: $0.routeShape, direction: $0.direction,
                              attribution: $0.attribution, preservesWorkoutContext: true)
            })
        }, onCancel: onCancel)
    }
}

private extension LoopPlanningSession {
    func candidateTitle(_ candidate: LoopPlanningCandidate, number: Int) -> String {
        // Reopening a committed selection must keep its canonical name, even if
        // its previous comparison position differs from this sole preview.
        if candidates.count == 1, let restoredRoute, restoredRoute.id == candidate.id {
            return restoredRoute.name
        }
        let numbered = String(format: String(localized: "route.planner.route_number", defaultValue: "Loop %d"), number)
        guard candidate.source == .generated else { return candidate.name ?? numbered }
        // Generated snapshots have no authored/renameable title. Their stored
        // slot label belongs to an older comparison, not the current map order.
        var title = numbered
        var suffix = 2
        while candidates.contains(where: {
            $0.source != .generated && $0.name?.localizedCaseInsensitiveCompare(title) == .orderedSame
        }) {
            title = String(format: String(localized: "route.planner.duplicate_numbered_name", defaultValue: "%@ (%d)"), numbered, suffix)
            suffix += 1
        }
        return title
    }
}

private struct LoopPlannerScreen: View {
    @Environment(\.outboundTheme) private var theme
    @Environment(\.analyticsManager) private var analytics
    @ObservedObject var presentation: LoopPlanningPresentation
    @ObservedObject var session: LoopPlanningSession
    @State private var summaryHeights: [String: CGFloat] = [:]
    @State private var selectedIndex = 0
    @State private var viewportHeight = 600.0
    @State private var camera: MapCameraPosition = .automatic
    @FocusState private var placeSearchFocused: Bool
    @FocusState private var startSearchFocused: Bool
    @State private var query = ""
    @State private var startQuery = ""
    @State private var distanceDraft = ""
    @State private var climbingDraft = false
    let onUse: (LoopPlanningCandidate, Int) -> Bool
    let onSavedSelection: (PreparedRoute?) -> Void
    let onCancel: () -> Void
    init(presentation: LoopPlanningPresentation, session: LoopPlanningSession,
         onUse: @escaping (LoopPlanningCandidate, Int) -> Bool,
         onSavedSelection: @escaping (PreparedRoute?) -> Void, onCancel: @escaping () -> Void) {
        self.presentation = presentation; self.session = session
        self.onUse = onUse; self.onSavedSelection = onSavedSelection; self.onCancel = onCancel
        if let start = session.start {
            _camera = State(initialValue: .region(.init(center: start.locationCoordinate, latitudinalMeters: 1500, longitudinalMeters: 1500)))
        }
    }
    var body: some View {
        NavigationStack {
            map
                .safeAreaInset(edge: .top) { mapControls }
                .safeAreaInset(edge: .bottom) { comparison }
                .onGeometryChange(for: Double.self) { Double($0.size.height) } action: { viewportHeight = $0 }
                .overlay {
                    if session.locating || session.busy {
                        ProgressView(session.locating
                            ? String(localized: "route.planner.locating", defaultValue: "Finding your location…")
                            : String(localized: "route.planner.searching", defaultValue: "Finding loops…"))
                            .font(.subheadline).multilineTextAlignment(.center)
                            .padding(OutboundSpacing.standard)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
                            .padding(.horizontal, OutboundSpacing.screen)
                            .allowsHitTesting(false)
                    }
                }
                .navigationTitle(String(localized: "route.planner.title", defaultValue: "Find a route"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String(localized: "Back")) { presentation.cancel(); onCancel() }
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
                .onChange(of: session.placeSearchState) { _, state in
                    let result: String
                    switch state {
                    case .ready: result = "results"
                    case .empty: result = "empty"
                    case .failed: result = "failure"
                    default: return
                    }
                    Task { await analytics?.track(.init(.featureExposed, properties: [.feature: .string("loop_planner_place_search"), .result: .string(result)])) }
                }
                .onChange(of: session.locationSourceResult) { _, result in
                    guard let result else { return }
                    Task { await analytics?.track(.init(.featureExposed, properties: [
                        .feature: .string("loop_planner_location"), .result: .string(result)])) }
                }
                .onChange(of: session.cacheEvent) { _, event in
                    guard let event else { return }
                    Task { await analytics?.track(.init(.featureExposed, properties: [
                        .feature: .string("loop_planner_cache"), .result: .string(event.result)])) }
                }
                .onChange(of: session.candidates.map(\.points)) { _, _ in
                    selectedIndex = 0; fitCandidates()
                }
                .onChange(of: startSearchFocused) { _, focused in
                    if !focused, presentation.sheet == nil { session.clearSearch() }
                }
                .onChange(of: presentation.sheet?.id) { old, new in
                    if old == "location", new == nil { session.clearSearch() }
                }
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
                    if !session.candidates.isEmpty {
                        fitCandidates()
                        await analytics?.track(.init(.featureExposed, properties: [.feature: .string("loop_planner_selection"), .result: .string("restored")]))
                    }
                    await analytics?.track(.init(.featureExposed, properties: [
                        .feature: .string("loop_planner"), .result: .string("compact_comparison")]))
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
        Button { startSearchFocused = false; distanceDraft = session.distanceText; presentation.sheet = .distance } label: {
            compactControlLabel {
                Text(session.distanceM.map { session.units.distanceString(meters: $0, fractionDigits: 1) }
                     ?? String(localized: "route.planner.distance", defaultValue: "Distance"))
            }
        }.accessibilityIdentifier("loop.distance")
    }
    private var startSearch: some View {
        HStack(spacing: 0) {
            Button { openStartSearch() } label: {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).outboundTapTarget()
            }.accessibilityLabel(String(localized: "route.planner.search_places", defaultValue: "Search places"))
            TextField(session.start == nil
                      ? String(localized: "route.planner.search_start", defaultValue: "Search for a start")
                      : session.startLabel, text: $startQuery)
                .textFieldStyle(.plain).focused($startSearchFocused).autocorrectionDisabled()
                .frame(minHeight: 44).contentShape(Rectangle())
                .submitLabel(.search).onSubmit { openStartSearch() }
                .onChange(of: startQuery) { _, value in
                    guard startSearchFocused else { return }; session.queryChanged(value)
                }
                .accessibilityLabel(String(localized: "route.planner.start", defaultValue: "Start"))
                .accessibilityIdentifier("loop.start")
            Button { useMyLocation() } label: {
                Image(systemName: "location.fill").foregroundStyle(theme.accentColor).outboundTapTarget()
            }.accessibilityLabel(String(localized: "route.planner.my_location", defaultValue: "My location"))
                .accessibilityIdentifier("loop.my_location")
        }
        .buttonStyle(.plain)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
    }
    private var optionsButton: some View {
        Button { startSearchFocused = false; climbingDraft = session.lessClimbing; presentation.sheet = .options } label: {
            compactControlLabel { Image(systemName: "slider.horizontal.3") }
        }
            .accessibilityLabel(String(localized: "route.planner.options", defaultValue: "Route options")).accessibilityIdentifier("loop.options")
    }
    private var mapControls: some View {
        // Fit only lightweight controls; the session and presentation stay above
        // both layouts. The compact fill sits inside each label's 44 pt hit target.
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: OutboundSpacing.compact) {
                    startSearch.frame(minWidth: 140)
                    distanceButton.fixedSize(horizontal: true, vertical: false)
                    optionsButton
                }
                VStack(spacing: 0) {
                    startSearch
                    HStack(spacing: OutboundSpacing.compact) { distanceButton; Spacer(minLength: 0); optionsButton }
                }
            }
            if startSearchFocused && !startQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView { placeResults(asVia: false) }.frame(maxHeight: 240)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, OutboundSpacing.compact)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
    }
    private func openStartSearch() {
        startSearchFocused = false
        query = startQuery
        presentation.sheet = .location
        Task { await analytics?.track(.init(.featureExposed, properties: [
            .feature: .string("loop_planner_start_search"), .result: .string("opened")])) }
        session.search(query)
    }
    private func useMyLocation() {
        startSearchFocused = false; placeSearchFocused = false
        startQuery = ""; query = ""; session.clearSearch(); presentation.sheet = nil
        session.requestLocation()
    }
    private var comparison: some View {
        VStack(alignment: .leading, spacing: 0) {
            if session.choosingStart {
                HStack {
                    Text(String(localized: "route.planner.tap_start", defaultValue: "Tap the map to move the start.")).font(.footnote)
                    Button(String(localized: "Cancel")) { session.cancelChoosingPoint() }
                }
            }
            if !session.locating && !session.busy {
                comparisonStatus
            }
            if !session.candidates.isEmpty {
                HStack { Spacer(minLength: 0); comparisonNavigation; Spacer(minLength: 0) }
                TabView(selection: $selectedIndex) {
                    ForEach(Array(session.candidates.enumerated()), id: \.element.id) { index, candidate in
                        ScrollView(.vertical) {
                            candidateSummary(candidate, number: index + 1)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                    if abs((summaryHeights[candidate.id] ?? 0) - height) > 0.5 {
                                        summaryHeights[candidate.id] = height
                                    }
                                }
                        }.scrollIndicators(.hidden).tag(index)
                            .accessibilityIdentifier("loop.candidate.\(index)")
                    }
                }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: comparisonSummaryHeight)
                ViewThatFits(in: .horizontal) {
                    HStack { moreRoutesButton; Spacer(); highlightedUseButton }
                    VStack(alignment: .leading, spacing: 0) {
                        moreRoutesButton
                        highlightedUseButton
                    }
                }
                .onChange(of: selectedIndex) { _, _ in
                    Task { await analytics?.track(.init(.featureExposed, properties: [.feature: .string("loop_planner_comparison"), .result: .string("browsed")])) }
                }
            }
            if session.candidates.isEmpty && !session.busy && !session.locating && session.start != nil && !session.choosingStart && !session.locationUnavailable {
                moreRoutesButton
            }
        }.padding(.horizontal, OutboundSpacing.compact).padding(.top, 4).background(.regularMaterial)
    }
    @ViewBuilder private var comparisonStatus: some View {
        if session.locationUnavailable {
            Text(String(localized: "route.planner.location_unavailable", defaultValue: "Choose a start on the map or enable location access in Settings.")).font(.footnote)
            Button(String(localized: "route.planner.choose_start", defaultValue: "Choose a start")) { query = ""; presentation.sheet = .location }
        } else if session.generationUnavailable && (!session.resultsCurrent || session.candidates.isEmpty) {
            Text(session.generationFailureMessage).font(.footnote).foregroundStyle(.secondary)
        } else if !session.supported {
            Text(String(localized: "route.planner.unsupported", defaultValue: "Loop planning is not available for this activity yet.")).font(.footnote)
        } else if session.searched && session.candidates.isEmpty {
            Text(String(localized: "route.planner.no_results", defaultValue: "No loops found within ±10%. Try another start, distance or via place.")).font(.footnote).foregroundStyle(.secondary)
            Button(String(localized: "route.planner.move_start", defaultValue: "Choose on map")) { moveStart() }
        }
    }
    private var comparisonSummaryHeight: CGFloat {
        let contentHeight = session.candidates.indices.contains(selectedIndex)
            ? summaryHeights[session.candidates[selectedIndex].id] ?? 112 : 112
        return min(max(44, contentHeight), max(80, CGFloat(viewportHeight * 0.28)))
    }
    private var comparisonNavigation: some View {
        HStack(spacing: 0) {
            Button { selectCandidate(-1) } label: { Image(systemName: "chevron.left").outboundTapTarget() }
                .accessibilityLabel(String(localized: "route.planner.previous", defaultValue: "Previous route"))
                .disabled(selectedIndex == 0)
            Text(String(format: String(localized: "route.planner.position", defaultValue: "%d of %d"), selectedIndex + 1, session.candidates.count))
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).fixedSize()
            Button { selectCandidate(1) } label: { Image(systemName: "chevron.right").outboundTapTarget() }
                .accessibilityLabel(String(localized: "route.planner.next", defaultValue: "Next route"))
                .disabled(selectedIndex >= session.candidates.count - 1)
        }
    }
    private var moreRoutesButton: some View {
        Button { session.generate() } label: {
            compactControlLabel {
                Text((session.resultsCurrent || session.busy || session.locating) && !session.candidates.isEmpty
                     ? String(localized: "route.planner.new_routes", defaultValue: "More routes")
                     : String(localized: "route.planner.retry", defaultValue: "Try again"))
            }
        }.buttonStyle(.plain).disabled(!session.canGenerate)
    }
    private func compactControlLabel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .foregroundStyle(Color.primary)
            .padding(.horizontal, OutboundSpacing.compact).padding(.vertical, 6)
            .background(OutboundPalette.surface, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
            .outboundTapTarget()
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
                OutboundGoalPresetFlow(horizontalSpacing: 8, verticalSpacing: 4) {
                    distancePresets
                }
                Button(String(localized: "Done")) {
                    presentation.sheet = nil; session.applyDistance(distanceDraft)
                }.buttonStyle(OutboundButtonStyle(.primary))
                    .buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                    .disabled(!session.validDistanceText(distanceDraft))
            case .location, .via:
                if case .location = sheet {
                    ViewThatFits(in: .horizontal) {
                        HStack { locationActions }
                        VStack(alignment: .leading) { locationActions }
                    }.buttonStyle(OutboundButtonStyle(.secondary)).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                }
                if isVia(sheet) {
                HStack {
                    TextField(String(localized: "route.planner.search_places", defaultValue: "Search places"), text: $query)
                        .textFieldStyle(.roundedBorder).focused($placeSearchFocused).autocorrectionDisabled()
                        .submitLabel(.search).onSubmit { submitPlaceSearch() }
                        .onChange(of: query) { _, value in session.queryChanged(value) }
                    Button { submitPlaceSearch() } label: { Image(systemName: "magnifyingglass").outboundTapTarget() }
                        .accessibilityLabel(String(localized: "Search")).accessibilityIdentifier("loop.place.search")
                }
                }
                placeResults(asVia: isVia(sheet))
                if isVia(sheet) {
                    includedPlaceControl
                    ForEach(session.recommendations) { place in
                        Button { choose(place, asVia: true) } label: { Label(place.name, systemImage: "leaf").outboundTapTarget() }
                    }
                }
            case .options:
                Toggle(String(localized: "route.planner.less_climbing", defaultValue: "Less climbing"), isOn: $climbingDraft).accessibilityIdentifier("loop.less_climbing")
                includedPlaceControl
                Button(String(localized: "route.planner.include_place", defaultValue: "Include a place")) {
                    query = ""; session.clearSearch(); presentation.sheet = .via
                }.buttonStyle(OutboundButtonStyle(.secondary)).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                Button(String(localized: "Done")) { presentation.sheet = nil; session.applyPreference(lessClimbing: climbingDraft) }
                    .buttonStyle(OutboundButtonStyle(.primary)).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
            default: EmptyView()
            }
        }
    }
    @ViewBuilder private var includedPlaceControl: some View {
        if let place = session.includedPlace {
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                Text(String(localized: "route.planner.included_place", defaultValue: "Included place"))
                    .outboundTextStyle(.sectionHeading)
                Text(place.name)
                    .outboundTextStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("loop.included_place")
                Button(role: .destructive) {
                    session.setVia(nil, lessClimbing: climbingDraft)
                    trackIncludedPlaceChange("removed")
                } label: {
                    Text(String(localized: "Remove")).outboundTapTarget()
                }
                .buttonStyle(OutboundButtonStyle(.secondary))
                .buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                .accessibilityLabel(String(format: String(localized: "route.planner.remove_place", defaultValue: "Remove %@"), place.name))
                .accessibilityIdentifier("loop.included_place.remove")
            }
        }
    }
    private func trackIncludedPlaceChange(_ result: String) {
        Task { await analytics?.track(.init(.featureExposed, properties: [
            .feature: .string("loop_planner_included_place"), .result: .string(result)])) }
    }
    private var distancePresets: some View {
        ForEach([3,5,10], id: \.self) { value in
            OutboundGoalPresetButton(title: "\(value) \(session.units.distanceUnit)") {
                distanceDraft = String(value)
            }
        }
    }
    @ViewBuilder private var locationActions: some View {
        Button { useMyLocation() } label: {
            Label(String(localized: "route.planner.my_location", defaultValue: "My location"), systemImage: "location").outboundTapTarget()
        }
        Button { moveStart() } label: {
            Text(String(localized: "route.planner.move_start", defaultValue: "Choose on map")).outboundTapTarget()
        }
    }
    private func isVia(_ sheet: LoopPlanningPresentation.Sheet) -> Bool { if case .via = sheet { true } else { false } }
    private func submitPlaceSearch() {
        placeSearchFocused = false
        session.search(query)
    }
    private func choose(_ place: LoopPlanningPlace, asVia: Bool) {
        startSearchFocused = false; placeSearchFocused = false
        presentation.sheet = nil; session.clearSearch(); query = ""
        if asVia {
            session.setVia(place.coordinate, name: place.name, lessClimbing: climbingDraft)
            trackIncludedPlaceChange("selected")
        } else {
            startQuery = ""; session.setStart(place.coordinate, label: place.name)
        }
    }
    private func moveStart() {
        startSearchFocused = false; startQuery = ""
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
                if let place = session.includedPlace { Marker(place.name, systemImage: "mappin", coordinate: place.coordinate.locationCoordinate).tint(theme.secondaryColor) }
                ForEach(Array(session.candidates.enumerated()), id: \.element.id) { index, candidate in
                    MapPolyline(coordinates: displayPoints(candidate)).stroke(routeColor(index), lineWidth: index == selectedIndex ? 7 : 2)
                    if let midpoint = candidate.points.dropFirst(candidate.points.count / 2).first {
                        Annotation("\(index + 1)", coordinate: midpoint.locationCoordinate) {
                            Button { guard session.resultsCurrent else { return }; selectedIndex = index } label: {
                                Text("\(index + 1)").font(.headline).padding(10).background(.regularMaterial, in: Circle())
                                    .overlay(Circle().stroke(routeColor(index), lineWidth: 3))
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
                if session.resultsCurrent, let candidate = nearestCandidate(point) {
                    selectedIndex = session.candidates.firstIndex(where: { $0.id == candidate.id }) ?? 0
                }
            })
        }
    }
    private func candidateSummary(_ candidate: LoopPlanningCandidate, number: Int) -> some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
            Text(candidateTitle(candidate, number: number)).font(.title3.weight(.semibold))
            HStack(alignment: .top, spacing: OutboundSpacing.standard) {
                metric(symbol: "arrow.left.and.right", label: String(localized: "route.planner.distance", defaultValue: "Distance"),
                       value: session.units.distanceString(meters: candidate.distanceM, fractionDigits: 2))
                metric(symbol: "mountain.2", label: String(localized: "route.planner.climbing", defaultValue: "Climbing"),
                       value: candidate.elevationGainM.map { session.units.elevationString(meters: $0) }
                           ?? String(localized: "route.planner.unknown_elevation", defaultValue: "Unavailable"))
            }
            if startDistance(candidate) >= 50 {
                Text(String(format: String(localized: "route.planner.start_distance", defaultValue: "Route starts %@ from your chosen start"), session.units.distanceString(meters: startDistance(candidate), fractionDigits: 2)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func metric(symbol: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OutboundSpacing.compact) {
            Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(value).fixedSize(horizontal: false, vertical: true)
        }
        .font(.title3.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
    @ViewBuilder private func placeResults(asVia: Bool) -> some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
            if session.placeSearchState == .loading {
                ProgressView(String(localized: "route.planner.searching_places", defaultValue: "Searching places…"))
            } else if session.placeSearchState == .empty {
                Text(String(localized: "route.planner.no_places", defaultValue: "No places found. Try another address.")).foregroundStyle(.secondary)
            } else if session.placeSearchState == .failed {
                Text(String(localized: "route.planner.search_failed", defaultValue: "Places could not be loaded. Try again.")).foregroundStyle(.secondary)
            }
            ForEach(Array(session.places.enumerated()), id: \.element.id) { index, place in
                Button { choose(place, asVia: asVia) } label: {
                    Text(place.name).frame(maxWidth: .infinity, alignment: .leading).outboundTapTarget()
                }.accessibilityIdentifier("loop.place.\(index)")
            }
        }.font(.body).padding(.vertical, OutboundSpacing.compact)
    }
    @ViewBuilder private var highlightedUseButton: some View {
        if session.candidates.indices.contains(selectedIndex) {
            useButton(session.candidates[selectedIndex])
                .accessibilityIdentifier("loop.use_route")
        }
    }
    private func useButton(_ candidate: LoopPlanningCandidate) -> some View {
        Button(String(localized: "route.detail.action.use_route", defaultValue: "Use route")) {
            use(candidate)
        }
        .buttonStyle(OutboundButtonStyle(.primary))
        .buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
        .frame(minHeight: 44)
        .disabled(!session.current || !session.resultsCurrent)
    }
    private func candidateTitle(_ candidate: LoopPlanningCandidate, number: Int) -> String {
        session.candidateTitle(candidate, number: number)
    }
    private func use(_ candidate: LoopPlanningCandidate) {
        guard session.current, session.resultsCurrent,
              let index = session.candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
        startSearchFocused = false; placeSearchFocused = false
        let accepted = onUse(candidate, index + 1)
        Task { await analytics?.track(.init(.featureExposed, properties: [
            .feature: .string("loop_planner_use"), .entrySource: .string("map"),
            .result: .string(accepted ? "success" : "failure")])) }
        guard accepted else {
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
    private func selectCandidate(_ offset: Int) {
        selectedIndex = min(max(0, selectedIndex + offset), session.candidates.count - 1)
    }
    private func routeColor(_ index: Int) -> Color {
        // Semantic map selection stays blue across app themes; numbers also identify routes.
        index == selectedIndex ? .blue : .secondary.opacity(0.55)
    }
}

private extension LoopPlanningCoordinate {
    var locationCoordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
