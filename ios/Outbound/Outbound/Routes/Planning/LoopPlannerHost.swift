import CoreLocation
import MapKit
import SwiftUI

/// Composition root: callers receive a selected canonical route, or cancellation.
/// No workout ownership or workout mutations live inside this host.
struct LoopPlannerHost: View {
    @EnvironmentObject private var routeStore: CommunityRouteStore
    @StateObject private var session: LoopPlanningSession
    let onSelect: (PreparedRoute) -> Void
    let onCancel: () -> Void
    init(activity: ActivityType = .running, distanceM: Double? = nil, units: MeasurementUnitSystem,
         onSelect: @escaping (PreparedRoute) -> Void, onCancel: @escaping () -> Void) {
        let account = ActivityAccountBoundary.current
        _session = StateObject(wrappedValue: LoopPlanningSession(activity: activity, distanceM: distanceM, units: units,
            repository: HTTPLoopPlanningRepository(), placeSearch: MapKitLoopPlaceSearch(), location: CoreLocationLoopProvider(),
            isCurrentAccount: { account == ActivityAccountBoundary.current }))
        self.onSelect = onSelect; self.onCancel = onCancel
    }
    var body: some View {
        LoopPlannerScreen(session: session, onUse: { candidate, number in
            guard session.current, session.candidates.contains(where: { $0.id == candidate.id }) else { return false }
            let name = candidate.name ?? String(format: String(localized: "route.planner.route_number", defaultValue: "Loop %d"), number)
            let route = PreparedRoute(id: candidate.id, name: name,
                points: candidate.points.map { RouteCoordinate(latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude) },
                source: candidate.source == .community ? .community : .generated,
                activityType: session.activity, routeShape: "loop", attribution: candidate.attribution, preservesWorkoutContext: true)
            guard route.isUsableForGuidance, routeStore.persistPlannerSelection(route) else { return false }
            onSelect(route); return true
        }, onCancel: onCancel)
    }
}

private struct LoopPlannerScreen: View {
    @Environment(\.outboundTheme) private var theme
    @Environment(\.analyticsManager) private var analytics
    @ObservedObject var session: LoopPlanningSession
    @State private var camera: MapCameraPosition = .automatic
    @State private var detail: LoopPlanningCandidate?
    @State private var showsInputs = true
    @State private var query = ""
    @State private var searchVia = false
    @State private var movingStart = false
    @State private var pendingPlace: LoopPlanningPlace?
    @State private var pendingCoordinate: CLLocationCoordinate2D?
    @State private var pinWasMoved = false
    let onUse: (LoopPlanningCandidate, Int) -> Bool
    let onCancel: () -> Void
    var body: some View {
        NavigationStack {
            map
                .safeAreaInset(edge: .top) {
                    HStack {
                        Button { showsInputs = true } label: {
                            Label(String(localized: "route.planner.edit_inputs", defaultValue: "Start, distance & via"), systemImage: "slider.horizontal.3").outboundTapTarget()
                        }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                        Spacer(minLength: 0)
                    }.padding(.horizontal, OutboundSpacing.screen).background(.regularMaterial)
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                        if movingStart { Text(String(localized: "route.planner.tap_start", defaultValue: "Tap the map to move the start.")).font(.footnote) }
                        if let place = pendingPlace { pinConfirmation(place) }
                        if session.busy { ProgressView(String(localized: "route.planner.searching", defaultValue: "Finding loops…")) }
                        if session.searched && session.candidates.isEmpty {
                            Text(String(localized: "route.planner.no_results", defaultValue: "No loops found within ±10%. Try another start, distance or via place.")).font(.footnote).foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal) {
                            HStack(spacing: OutboundSpacing.compact) {
                                ForEach(Array(session.candidates.enumerated()), id: \.element.id) { index, candidate in
                                    Button { detail = candidate } label: { candidateCard(candidate, number: index + 1).frame(width: 210) }.buttonStyle(.plain)
                                }
                            }
                        }.scrollIndicators(.hidden)
                        HStack {
                            Text(session.distanceM.map { session.units.distanceString(meters: $0, fractionDigits: 1) } ?? String(localized: "route.planner.choose_distance", defaultValue: "Choose a distance")).font(.subheadline)
                            Spacer()
                            Button(String(localized: "route.planner.find_loops", defaultValue: "Find loops")) { generate() }
                                .buttonStyle(.borderedProminent).tint(theme.actionColor).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                                .disabled(!session.canGenerate || pendingPlace != nil)
                        }
                    }.padding(OutboundSpacing.standard).background(.regularMaterial)
                }
            .navigationTitle(String(localized: "route.planner.title", defaultValue: "Find a loop"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Back")) { session.cancel(); onCancel() }
                }
            }
            .overlay(alignment: .top) { if let toast = session.toast { RouteToast(message: toast) } }
            .sheet(isPresented: $showsInputs) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OutboundSpacing.section) {
                            controls
                            if !session.supported { Text(String(localized: "route.planner.unsupported", defaultValue: "Loop planning is not available for this activity yet.")).foregroundStyle(.secondary) }
                            if !session.recommendations.isEmpty {
                                Text(String(localized: "route.planner.nearby_parks", defaultValue: "Nearby parks")).font(.headline)
                                ForEach(session.recommendations) { place in
                                    Button { preview(place, asVia: true) } label: { Label(place.name, systemImage: "leaf").outboundTapTarget() }
                                        .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                                }
                            }
                        }.padding(OutboundSpacing.screen)
                    }
                    .navigationTitle(String(localized: "route.planner.title", defaultValue: "Find a loop"))
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "Close")) { showsInputs = false } } }
                }.overlay(alignment: .top) { if let toast = session.toast { RouteToast(message: toast) } }
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .sheet(item: $detail) { candidate in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OutboundSpacing.section) {
                            candidateCard(candidate, number: (session.candidates.firstIndex(where: { $0.id == candidate.id }) ?? 0) + 1)
                            Text(candidate.attribution).font(.caption).foregroundStyle(.secondary)
                            let displacement = startDistance(candidate)
                            Text(String(format: String(localized: "route.planner.start_distance", defaultValue: "Route starts %@ from your chosen start"), session.units.distanceString(meters: displacement, fractionDigits: 2)))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(String(localized: "route.planner.check_access", defaultValue: "Check access, crossings and conditions before heading out. Place pins may not mark entrances.")).font(.footnote).foregroundStyle(.secondary)
                            Button(String(localized: "route.detail.action.use_route", defaultValue: "Use route")) { use(candidate) }
                                .buttonStyle(.borderedProminent).tint(theme.actionColor)
                                .buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                        }.padding(OutboundSpacing.screen)
                    }
                    .navigationTitle(String(localized: "route.planner.route_details", defaultValue: "Route details"))
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "Close")) { detail = nil } } }
                }.overlay(alignment: .top) { if let toast = session.toast { RouteToast(message: toast) } }
                    .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            }
            .onChange(of: session.candidates.map(\.id)) { _, ids in
                if let detail, !ids.contains(detail.id) { self.detail = nil }
                camera = .automatic
            }
            .onDisappear { session.cancel() }
            .task {
                session.requestLocation()
                await analytics?.track(.init(.featureExposed, properties: [.feature: .string("loop_planner")]))
            }
        }
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
                            Button { detail = candidate } label: {
                                Text("\(index + 1)").font(.headline).padding(10).background(.regularMaterial, in: Circle())
                                    .overlay(Circle().stroke(routeColor(index).opacity(detail == nil || detail?.id == candidate.id ? 1 : 0.25), lineWidth: 3))
                                    .outboundTapTarget()
                            }.accessibilityLabel(candidateTitle(candidate, number: index + 1))
                        }
                    }
                }
                ForEach(session.recommendations) { place in
                    Annotation(place.name, coordinate: place.coordinate.locationCoordinate) {
                        Button { preview(place, asVia: true) } label: { Image(systemName: "leaf.circle.fill").font(.title2).foregroundStyle(theme.secondaryColor).outboundTapTarget() }
                            .accessibilityLabel(place.name)
                    }
                }
                if let point = pendingCoordinate {
                    Marker(String(localized: "route.planner.confirm_pin", defaultValue: "Confirm pin"), coordinate: point).tint(theme.actionColor)
                }
            }
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                guard let point = proxy.convert(tap.location, from: .local) else { return }
                if pendingPlace != nil { pendingCoordinate = point; pinWasMoved = true; return }
                if movingStart {
                    session.setStart(.init(latitude: point.latitude, longitude: point.longitude)); movingStart = false; return
                }
                if let candidate = nearestCandidate(point) { detail = candidate }
            })
        }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
            HStack {
                Button { session.requestLocation() } label: { Label(String(localized: "route.planner.my_location", defaultValue: "My location"), systemImage: "location") }
                Button { movingStart.toggle(); showsInputs = false; pendingPlace = nil; pendingCoordinate = nil } label: { Label(String(localized: "route.planner.move_start", defaultValue: "Move start"), systemImage: "mappin.and.ellipse") }
            }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
            if movingStart { Text(String(localized: "route.planner.tap_start", defaultValue: "Tap the map to move the start.")).font(.footnote).foregroundStyle(.secondary) }
            Picker(String(localized: "route.planner.search_for", defaultValue: "Search for"), selection: $searchVia) {
                Text(String(localized: "route.planner.start", defaultValue: "Start")).tag(false)
                Text(String(localized: "route.planner.via", defaultValue: "Via place")).tag(true)
            }.pickerStyle(.segmented)
            HStack {
                TextField(String(localized: "route.planner.search_places", defaultValue: "Search places"), text: $query)
                    .textFieldStyle(.roundedBorder).submitLabel(.search).onSubmit { session.search(query) }
                    .onChange(of: query) { _, _ in session.clearSearch() }
                Button { session.search(query) } label: { Image(systemName: "magnifyingglass").outboundTapTarget() }
                    .accessibilityLabel(String(localized: "Search"))
            }
            ForEach(session.places) { place in
                Button { preview(place, asVia: searchVia) } label: { Text(place.name).outboundTapTarget() }
            }
            if session.via != nil {
                Button(String(localized: "route.planner.remove_via", defaultValue: "Remove via place")) { session.setVia(nil) }.buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
            }
            HStack {
                Text(String(localized: "route.planner.distance", defaultValue: "Distance"))
                TextField(session.units.distanceUnit, text: $session.distanceText).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(String(localized: "route.planner.distance", defaultValue: "Distance"))
                Text(session.units.distanceUnit)
            }
            HStack {
                ForEach([3,5,10], id: \.self) { value in
                    Button("\(value) \(session.units.distanceUnit)") { session.distanceText = String(value) }
                }
            }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
            if let meters = session.distanceM {
                Text(String(format: String(localized: "route.planner.range", defaultValue: "Accepting %@–%@ (±10%%)"), session.units.distanceString(meters: meters * 0.9, fractionDigits: 1), session.units.distanceString(meters: meters * 1.1, fractionDigits: 1)))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Toggle(String(localized: "route.planner.less_climbing", defaultValue: "Less climbing"), isOn: $session.lessClimbing)
            Text(String(localized: "route.planner.climbing_explanation", defaultValue: "Ranks options with known elevation gain first.")).font(.caption).foregroundStyle(.secondary)
            Button {
                showsInputs = false; generate()
            } label: {
                Text(String(localized: "route.planner.find_loops", defaultValue: "Find loops")).outboundTapTarget()
            }.buttonStyle(.borderedProminent).tint(theme.actionColor).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
                .disabled(!session.canGenerate || pendingPlace != nil)
        }
    }
    private func generate() {
        detail = nil; session.generate()
        Task { await analytics?.track(.init(.activityConfigurationChanged, properties: [.changeType: .string("loop_planner_generate"), .activityType: .string(session.activity.rawValue)])) }
    }
    private func pinConfirmation(_ place: LoopPlanningPlace) -> some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
            Text(place.name).font(.headline)
            Text(String(localized: "route.planner.confirm_access", defaultValue: "Choose a usable entrance or access point on the map, then confirm.")).font(.footnote)
            HStack {
                Button(String(localized: "route.planner.confirm_pin", defaultValue: "Confirm pin")) {
                    guard let point = pendingCoordinate else { return }
                    let coordinate = LoopPlanningCoordinate(latitude: point.latitude, longitude: point.longitude)
                    if searchVia { session.setVia(coordinate) } else { session.setStart(coordinate) }
                    pendingPlace = nil; pendingCoordinate = nil; session.clearSearch(); query = ""
                }
                .disabled(!pinWasMoved)
                Button(String(localized: "Cancel")) { pendingPlace = nil; pendingCoordinate = nil }
            }.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
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
                Text(candidate.source == .community
                     ? String(localized: "route.planner.existing_route", defaultValue: "Community route")
                     : String(localized: "route.planner.generated_route", defaultValue: "Generated route"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }.padding(OutboundSpacing.standard).background(.regularMaterial, in: RoundedRectangle(cornerRadius: OutboundRadius.card)).outboundTapTarget()
    }
    private func candidateTitle(_ candidate: LoopPlanningCandidate, number: Int) -> String {
        candidate.name ?? String(format: String(localized: "route.planner.route_number", defaultValue: "Loop %d"), number)
    }
    private func preview(_ place: LoopPlanningPlace, asVia: Bool) {
        showsInputs = false; pinWasMoved = false; searchVia = asVia; pendingPlace = place; pendingCoordinate = place.coordinate.locationCoordinate; movingStart = false
        camera = .region(.init(center: place.coordinate.locationCoordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
    }
    private func use(_ candidate: LoopPlanningCandidate) {
        guard session.current else { return }
        let number = (session.candidates.firstIndex(where: { $0.id == candidate.id }) ?? 0) + 1
        guard onUse(candidate, number) else {
            session.showToast(String(localized: "route.planner.save_failed", defaultValue: "Route could not be saved on this device. Try again.")); return
        }
        session.cancel(); detail = nil
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
