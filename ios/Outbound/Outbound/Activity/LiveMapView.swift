import MapKit
import OSLog
import SwiftUI
import UIKit

struct LiveMapView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.analyticsManager) private var analyticsManager
    @Environment(\.outboundTheme) private var theme
    @EnvironmentObject var measurementPreferences: MeasurementPreferences
    @EnvironmentObject var liveGroupStore: LiveGroupStore
    @EnvironmentObject var onboardingStore: OnboardingStore
    @ObservedObject var recorder: ActivityRecorder
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var guide: VirtualGuide
    @ObservedObject var musicStore: MusicStore
    let intent: SessionIntent?
    var locationPermissionUnavailable = false
    let capturedPhotoCount: Int
    let lastCapturedPhoto: UIImage?
    @Binding var activePage: SessionPage
    @Binding var isWorkoutPanelExpanded: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onFinish: () -> Void
    let isFinishEnabled: Bool
    var reservesAssistantSpace = false

    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isFollowingUser = true
    @State private var statusCardHeight: CGFloat = 132
    @State private var bottomOverlayHeight: CGFloat = 168
    @State private var eventParticipants: [ActivityEventParticipantDTO] = []
    @State private var participantToast: String?
    @State private var focusedParticipantID: String?
    @State private var isGroupManagementExpanded = false
    @State private var hasTrackedRouteDisplay = false
    @State private var hasTrackedActivityAvatarDisplay = false
    @State private var locationClock = Date()
    @State private var cachedPlannedRouteCoordinates: [CLLocationCoordinate2D] = []

    var body: some View {
        let _ = locationClock // Re-evaluate stale pins even when GPS/network delivery stops.
        GeometryReader { geometry in
            ZStack {
                // Keep the native map and its camera alive across page changes. The pager
                // moves it offscreen; hiding it on selection exposes a blank transition frame.
                mapSurface
                    .allowsHitTesting(activePage == .map)
                    .accessibilityHidden(activePage != .map)
                bottomControls(expandedHeight: geometry.size.height)
                if !isWorkoutPanelExpanded {
                    rightControls
                }
            }
            .overlay(alignment: .top) {
                topGroupControls
                    .padding(.top, 62)
                    .opacity(isWorkoutPanelExpanded ? 0 : 1)
                    .allowsHitTesting(!isWorkoutPanelExpanded)
                    .accessibilityHidden(isWorkoutPanelExpanded)
            }
            .overlay(alignment: .center) {
                if let participantToast {
                    Text(participantToast)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .allowsHitTesting(false)
                }
            }
            .task(id: liveGroupStore.activeSession?.id) {
                while !Task.isCancelled, liveGroupStore.activeSession != nil {
                    locationClock = Date()
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
            .task(id: participantToast) {
                guard participantToast != nil else { return }
                do { try await Task.sleep(for: .seconds(2.2)) } catch { return }
                participantToast = nil
            }
            .onChange(of: intent?.activityEvent?.id) { _, _ in eventParticipants = [] }
            .onReceive(locationManager.$location) { loc in
                guard let loc else { return }
                trackActivityAvatarDisplayIfNeeded()
                if recorder.state == .idle, !plannedRouteCoordinates.isEmpty {
                    framePlannedRoute(including: loc.coordinate)
                }
            }
            .onAppear {
                cachePlannedRouteCoordinates()
                guard !plannedRouteCoordinates.isEmpty else { return }
                if recorder.state == .idle {
                    framePlannedRoute(including: locationManager.location?.coordinate)
                }
                trackRouteDisplayIfNeeded()
            }
            .onChange(of: plannedRouteCacheKey) { _, _ in
                cachePlannedRouteCoordinates()
            }
            .onChange(of: recorder.state) { _, state in
                if state == .idle { framePlannedRoute(including: locationManager.location?.coordinate) }
            }
            .onPreferenceChange(SessionStatusCardHeightPreferenceKey.self) { height in
                if height > 0 {
                    statusCardHeight = height
                }
            }
            .onPreferenceChange(MapAttributionOcclusionHeightPreferenceKey.self) { height in
                if height > 0 {
                    bottomOverlayHeight = max(height, statusCardHeight + 18)
                }
            }
        }
    }

    private var mapSurface: some View {
        ActivityMapSurface(safeZone: ActivityMapSafeZone(bottomInset: bottomOverlayHeight + 8)) {
            LiveSessionMapCanvas(
                position: $mapPosition,
                isFollowingLocation: $isFollowingUser,
                location: currentMapLocation,
                routeSegments: trailCoordinateSegments,
                activityType: activityType,
                tint: theme.accentColor,
                isMoving: recorder.state == .active,
                reduceMotion: reduceMotion,
                followsLocation: isFollowingUser && !(recorder.state == .idle && !plannedRouteCoordinates.isEmpty)
            ) {
                if plannedRouteCoordinates.count > 1 {
                    MapPolyline(coordinates: plannedRouteCoordinates)
                        .stroke(.white.opacity(0.9), style: selectedRouteHaloStyle)
                    MapPolyline(coordinates: plannedRouteCoordinates)
                        .stroke(selectedRouteColor, style: selectedRouteStyle)
                }
                if let routeStartCoordinate {
                    Annotation(
                        routeEndpointsOverlap
                            ? String(localized: "route.guidance.map.start_finish", defaultValue: "Route start and finish")
                            : String(localized: "route.guidance.map.start", defaultValue: "Route start"),
                        coordinate: routeStartCoordinate
                    ) {
                        RouteEndpointPin(
                            systemImage: routeEndpointsOverlap ? "flag.checkered" : "flag.fill",
                            color: routeEndpointsOverlap ? .orange : .green
                        )
                    }
                }
                if !routeEndpointsOverlap, let routeFinishCoordinate {
                    Annotation(
                        String(localized: "route.guidance.map.finish", defaultValue: "Route finish"),
                        coordinate: routeFinishCoordinate
                    ) {
                        RouteEndpointPin(systemImage: "flag.checkered", color: .orange)
                    }
                }
                if plannedRouteCoordinates.isEmpty, let startCoordinate {
                    Annotation("Trail Start", coordinate: startCoordinate) {
                        Circle()
                            .fill(.green)
                            .frame(width: 14, height: 14)
                            .overlay { Circle().stroke(.white, lineWidth: 3) }
                            .shadow(radius: 4)
                    }
                }
                ForEach(liveGroupStore.visibleParticipants) { participant in
                    if let coordinate = participant.coordinate {
                        Annotation(participant.displayName, coordinate: coordinate) {
                            LiveGroupParticipantPin(participant: participant, displayedAt: locationClock)
                                .onTapGesture {
                                    focusedParticipantID = participant.id
                                    isFollowingUser = false
                                    updateMapCamera(for: coordinate, animated: true)
                                }
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private var matchingLiveParticipants: [LiveGroupParticipant] {
        let matchesEvent = intent?.activityEvent == nil || liveGroupStore.activeSession?.activityEventId == intent?.activityEvent?.id
        return matchesEvent ? liveGroupStore.participants.filter { $0.status != "left" } : []
    }

    private var participantPills: [LiveGroupRunnerPill] {
        let liveParticipants = matchingLiveParticipants
        if intent?.activityEvent != nil {
            let attendees = eventParticipants.filter {
                $0.status == "going" || $0.status == "participating" || $0.startedAt != nil || $0.isRecording == true
            }
            let attendeeIDs = Set(attendees.map { $0.person.id })
            let attendeePills = attendees.map { attendee in
                LiveGroupRunnerPill(
                    id: attendee.person.id, displayName: attendee.person.displayName,
                    avatarURL: attendee.person.avatarUrl,
                    liveParticipant: liveParticipants.first { $0.userId == attendee.person.id }
                )
            }
            // Live membership can arrive before the next event-roster refresh.
            return attendeePills + liveParticipants.filter { !attendeeIDs.contains($0.userId) }.map {
                LiveGroupRunnerPill(id: $0.userId, displayName: $0.displayName, avatarURL: nil, liveParticipant: $0)
            }
        }
        return liveParticipants.filter { !$0.isCurrentUser }.map {
            LiveGroupRunnerPill(id: $0.userId, displayName: $0.displayName, avatarURL: nil, liveParticipant: $0)
        }
    }

    private var isSharingEventLiveMap: Bool {
        liveGroupStore.isSharing && liveGroupStore.activeSession?.activityEventId == intent?.activityEvent?.id
    }

    private func toggleEventLiveMap() {
        track(.init(.groupActivityLocationSharingChanged, properties: [.selectionType: .string(isSharingEventLiveMap ? "off" : "on"), .result: .string("requested")]))
        if isSharingEventLiveMap {
            liveGroupStore.stopFromManagementControl()
        } else if let event = intent?.activityEvent {
            Task {
                track(.init(.groupRunJoinAttempted))
                await liveGroupStore.joinActivityEvent(event.id)
                if isSharingEventLiveMap {
                    track(.init(.groupRunJoined, properties: [
                        .participantCountBucket: .string(ProductAnalyticsBucket.count(liveGroupStore.participants.count))
                    ]))
                }
            }
        }
    }

    private var topGroupControls: some View {
        VStack(spacing: 8) {
            if let event = intent?.activityEvent {
                GroupActivityPresenceView(
                    eventID: event.id, title: event.title,
                    isSharingLiveMap: isSharingEventLiveMap,
                    isLiveMapBusy: liveGroupStore.isJoining || (liveGroupStore.isSharing && !isSharingEventLiveMap),
                    onToggleLiveMap: toggleEventLiveMap,
                    onParticipantsLoaded: { eventParticipants = $0 },
                    onSelectParticipant: { attendee in
                        focusParticipant(matchingLiveParticipants.first { $0.userId == attendee.person.id }, source: "group_card")
                    }
                )
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
                .padding(.trailing, reservesAssistantSpace ? AssistantLauncherButton.diameter + 8 : 0)
            } else if liveGroupStore.isSharing {
                LiveGroupManagementPanel(
                    title: liveGroupStore.displayTitle,
                    statusSummary: liveGroupStore.statusSummary,
                    participants: liveGroupStore.participants,
                    isExpanded: $isGroupManagementExpanded,
                    isCreator: liveGroupStore.activeSession?.isCreatedByCurrentUser == true,
                    onInvite: {
                        Task {
                            guard let presentation = liveGroupStore.invitePresentation(intent: intent) else { return }
                            await SystemSharePresenter.present(activityItems: presentation.activityItems)
                        }
                    },
                    onStop: {
                        liveGroupStore.stopFromManagementControl()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.trailing, reservesAssistantSpace ? AssistantLauncherButton.diameter + 8 : 0)
            }

            if !participantPills.isEmpty {
                LiveGroupRunnerStrip(
                    participants: participantPills,
                    displayedAt: locationClock,
                    focusedParticipantID: focusedParticipantID,
                    onSelect: { participant in
                        focusParticipant(participant.liveParticipant, source: "participant_pill")
                    }
                )
                .padding(.horizontal, 16)
            }

        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: LiveGroupTopControlsHeightPreferenceKey.self, value: proxy.size.height)
            }
        }
    }

    private func focusParticipant(_ participant: LiveGroupParticipant?, source: String) {
        let coordinate = participant?.isCurrentUser == true
            ? currentCoordinate
            : (participant?.isVisibleOnMap == true ? participant?.coordinate : nil)
        guard let coordinate else {
            track(.init(.groupParticipantLocationUnavailable, properties: [.sourceType: .string(source)]))
            participantToast = String(localized: "group.activity.location_unavailable", table: "GroupActivity")
            return
        }
        track(.init(.groupParticipantFocused, properties: [.sourceType: .string(source)]))
        focusedParticipantID = participant?.id
        isFollowingUser = false
        updateMapCamera(for: coordinate, animated: true)
    }


    private func bottomControls(expandedHeight: CGFloat) -> some View {
        VStack {
            Spacer()

            VStack(spacing: 12) {
                if !isWorkoutPanelExpanded, let routeGuidance = recorder.routeGuidanceSnapshot {
                    if routeGuidance.state == .acquiring, routeStartCoordinate != nil {
                        Button(action: openRouteStartDirections) {
                            RouteGuidanceStatusView(snapshot: routeGuidance, unitSystem: measurementPreferences.unitSystem)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    } else {
                        RouteGuidanceStatusView(snapshot: routeGuidance, unitSystem: measurementPreferences.unitSystem)
                            .padding(.horizontal, 16)
                    }
                }

                statusCard(expandedHeight: expandedHeight)
                    .padding(.horizontal, isWorkoutPanelExpanded ? 0 : 16)
                    .padding(.bottom, isWorkoutPanelExpanded ? 0 : 18)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: MapAttributionOcclusionHeightPreferenceKey.self,
                        value: isWorkoutPanelExpanded ? 0 : proxy.size.height
                    )
                }
            }
        }
    }

    private func statusCard(expandedHeight: CGFloat) -> some View {
        ActivityControlSheet(isExpanded: isWorkoutPanelExpanded) {
            SessionStatusCard(
            state: recorder.state,
                        locationPermissionUnavailable: locationPermissionUnavailable,
            isExpanded: $isWorkoutPanelExpanded,
            expandedHeight: expandedHeight,
            intent: intent,
            companionType: recorder.companionType,
            elapsedText: recorder.movingSeconds.formatted(),
            elapsedSeconds: recorder.elapsedSeconds,
            paceLabel: recorder.activityType == .cycling ? (recorder.state == .paused ? String(localized: "activity.metric.avg_speed", defaultValue: "Avg Speed") : String(localized: "session.metric.speed", defaultValue: "Speed")) : recorder.state == .paused
                ? String(localized: "session.metric.average_pace", defaultValue: "Avg. pace")
                : String(localized: "session.metric.pace", defaultValue: "Pace"),
            paceText: sessionPaceText,
            distanceText: measurementPreferences.unitSystem.distanceValueString(meters: recorder.distanceMeters),
            distanceMeters: recorder.distanceMeters,
            energyKilocalories: estimatedEnergyKilocalories,
            walkingStepCount: recorder.walkingStepCount,
            cadenceStepsPerMinute: recorder.currentCadenceStepsPerMinute,
            distanceLabel: measurementPreferences.unitSystem.distanceLabel,
            elevationText: measurementPreferences.unitSystem.elevationValueString(meters: recorder.elevationGainMeters),
            elevationLabel: measurementPreferences.unitSystem.elevationLabel,
            heartRateText: heartRateDisplayText,
            guideMessage: guideMessage,
            musicPlayback: musicStore.playback.hasActiveQueue ? musicStore.playback : nil,
            showsMusicDisabledState: musicStore.hasDeveloperTokenError,
            musicErrorMessage: musicStore.hasDeveloperTokenError ? nil : musicStore.lastErrorMessage,
            onTogglePlayback: {
                trackMusicControl(musicStore.playback.isPlaying ? "pause" : "resume")
                Task { await musicStore.togglePlayback() }
            },
            onSkipTrack: {
                trackMusicControl("skip")
                Task { await musicStore.skipToNext() }
            },
            onStart: onStart,
            onPause: onPause,
            onResume: onResume,
            onFinish: onFinish,
            isFinishEnabled: isFinishEnabled
            )
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SessionStatusCardHeightPreferenceKey.self,
                    value: isWorkoutPanelExpanded ? 0 : proxy.size.height
                )
            }
        }
    }

    private var rightControls: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()
                rightControlRail
            }
            .padding(.trailing, 16)
            .padding(.bottom, railBottomPadding)
        }
    }

    private var selectedRouteColor: Color {
        Color(red: 1, green: 0.32, blue: 0)
    }

    private var selectedRouteHaloStyle: StrokeStyle {
        StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
    }

    private var selectedRouteStyle: StrokeStyle {
        StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
    }

    private var guideMessage: String? {
        guard recorder.state != .idle, !guide.lastNudge.isEmpty else { return nil }
        return guide.lastNudge
    }

    private var estimatedEnergyKilocalories: Double? {
        WorkoutCalorieEstimator.liveEnergyKilocalories(
            activityType: intent?.resolvedActivityType ?? .running,
            distanceMeters: recorder.distanceMeters,
            durationSeconds: recorder.elapsedSeconds,
            elevationGainMeters: recorder.elevationGainMeters,
            weightKilograms: onboardingStore.latestWeightKilograms
        )
    }

    private var trailCoordinates: [CLLocationCoordinate2D] {
        locationManager.trackCoordinates
    }

    private var trailCoordinateSegments: [[CLLocationCoordinate2D]] {
        locationManager.trackCoordinateSegments
    }

    private var plannedRouteCoordinates: [CLLocationCoordinate2D] {
        if !recorder.routeGuidanceCoordinates.isEmpty {
            return recorder.routeGuidanceCoordinates
        }
        return cachedPlannedRouteCoordinates
    }

    private var plannedRouteCacheKey: String? {
        guard let route = intent?.preparedRoute else { return nil }
        return "\(route.id):\(route.direction.rawValue):\(route.points.count)"
    }

    private func cachePlannedRouteCoordinates() {
        guard let route = intent?.preparedRoute else {
            cachedPlannedRouteCoordinates = []
            return
        }
        cachedPlannedRouteCoordinates = RouteWorkingGeometry.displayPoints(route.directedPoints)
            .map(\.locationCoordinate)
    }

    private func framePlannedRoute(including userCoordinate: CLLocationCoordinate2D?) {
        guard plannedRouteCoordinates.count > 1 else { return }
        var rect = plannedRouteCoordinates.reduce(MKMapRect.null) { partial, coordinate in
            let point = MKMapPoint(coordinate)
            return partial.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        if let userCoordinate {
            let point = MKMapPoint(userCoordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        let horizontalPadding = max(rect.width * 0.12, 1_500)
        let verticalPadding = max(rect.height * 0.12, 1_500)
        mapPosition = .rect(rect.insetBy(dx: -horizontalPadding, dy: -verticalPadding))
    }

    private func openRouteStartDirections() {
        guard let coordinate = routeStartCoordinate,
              CLLocationCoordinate2DIsValid(coordinate) else { return }
        // Endpoints are preserved in the working geometry, including reverse direction.
        // Omitting the origin lets Maps use the current location.
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.path = "/"
        components.queryItems = [
            URLQueryItem(name: "daddr", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "dirflg", value: "d")
        ]
        guard let url = components.url else { return }
        UIApplication.shared.open(url) { opened in
            track(.init(.routeStartDirectionsOpened, properties: [
                .result: .string(opened ? "success" : "failure")
            ]))
            guard !opened else { return }
            Logger(subsystem: "plainstride.outbound", category: "RouteNavigation")
                .error("Open route-start directions failed provider=apple_maps")
            participantToast = String(localized: "route.directions.open_failed", defaultValue: "Couldn’t open Maps. Try again.")
        }
    }

    private func trackRouteDisplayIfNeeded() {
        guard !hasTrackedRouteDisplay, let route = intent?.preparedRoute else { return }
        hasTrackedRouteDisplay = true
        track(.init(.routeDisplayed, properties: [.sourceType: .string(route.source.rawValue)]))
    }

    private func track(_ event: ProductAnalyticsEvent) {
        guard let analyticsManager else { return }
        Task { await analyticsManager.track(event) }
    }

    private var startCoordinate: CLLocationCoordinate2D? {
        trailCoordinates.first
    }

    private var routeStartCoordinate: CLLocationCoordinate2D? {
        plannedRouteCoordinates.first
    }

    private var routeFinishCoordinate: CLLocationCoordinate2D? {
        plannedRouteCoordinates.last
    }

    private var routeEndpointsOverlap: Bool {
        guard let routeStartCoordinate, let routeFinishCoordinate else { return false }
        return CLLocation(
            latitude: routeStartCoordinate.latitude,
            longitude: routeStartCoordinate.longitude
        ).distance(from: CLLocation(
            latitude: routeFinishCoordinate.latitude,
            longitude: routeFinishCoordinate.longitude
        )) <= 20
    }

    private var currentCoordinate: CLLocationCoordinate2D? {
        locationManager.location?.coordinate ?? trailCoordinates.last
    }

    private var activityType: ActivityType {
        intent?.resolvedActivityType ?? .running
    }

    private var currentMapLocation: LiveSessionMapLocation? {
        if recorder.state == .active,
           let coordinate = trailCoordinateSegments.last?.last,
           let location = locationManager.trackPoints.last {
            return LiveSessionMapLocation(
                coordinate: coordinate,
                course: recordedTrackCourse,
                updatedAt: location.timestamp
            )
        }
        guard let location = locationManager.location else { return nil }
        return LiveSessionMapLocation(
            coordinate: location.coordinate,
            course: location.course,
            updatedAt: location.timestamp
        )
    }

    private var recordedTrackCourse: CLLocationDirection? {
        guard let segment = locationManager.trackCoordinateSegments.last,
              let end = segment.last
        else { return nil }
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        guard let start = segment.dropLast().reversed().first(where: { coordinate in
            endLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) >= 3
        }) else { return nil }

        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude)
            - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func trackActivityAvatarDisplayIfNeeded() {
        guard !hasTrackedActivityAvatarDisplay,
              recorder.state != .idle,
              let analyticsManager else { return }
        hasTrackedActivityAvatarDisplay = true
        Task {
            await analyticsManager.track(.init(.featureExposed, properties: [
                .feature: .string("live_map_activity_avatar")
            ]))
        }
    }

    private var rightControlRail: some View {
        VStack(spacing: 14) {
            CapturedPhotoStackView(
                image: lastCapturedPhoto,
                count: capturedPhotoCount,
                isConfirming: false
            )

            Button { activePage = .camera } label: {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(.black.opacity(0.42)))
            }
            .accessibilityLabel(String(localized: "map.action.show_camera", defaultValue: "Show Camera"))

            Button {
                if let loc = locationManager.location {
                    isFollowingUser = true
                    focusedParticipantID = nil
                    updateMapCamera(for: loc, animated: true)
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(.black.opacity(0.42)))
            }
            .accessibilityLabel(String(localized: "map.action.recenter", defaultValue: "Recenter Map"))
        }
    }

    private var railBottomPadding: CGFloat {
        max(bottomOverlayHeight + 20, 150)
    }

    private var sessionPaceText: String {
        if recorder.activityType == .cycling {
            if recorder.state == .paused {
                return measurementPreferences.unitSystem.speedString(meters: recorder.distanceMeters, seconds: Double(recorder.movingSeconds))
            }
            guard let pace = recorder.currentPace, pace > 0 else { return "—" }
            return measurementPreferences.unitSystem.speedString(meters: 1000, seconds: pace)
        }
        switch recorder.state {
        case .idle:
            return "--"
        case .active:
            return recorder.currentPace?.paceString(for: measurementPreferences.unitSystem) ?? "--"
        case .paused:
            return recorder.averagePace?.paceString(for: measurementPreferences.unitSystem) ?? "--"
        }
    }

    private func trackMusicControl(_ control: String) {
        guard let analyticsManager else { return }
        Task {
            await analyticsManager.track(.init(.musicControlUsed, properties: [.control: .string(control)]))
        }
    }

    private var heartRateDisplayText: String {
        if let bpm = recorder.heartRate {
            guard let zone = recorder.heartRateZone else { return "\(bpm)" }
            return "\(bpm) · " + String(
                format: String(localized: "watch.hr.zone.format", defaultValue: "Zone %d"),
                zone
            )
        }
        return recorder.heartRateSignalState == .unavailable
            ? String(localized: "watch.hr.unavailable", defaultValue: "No signal")
            : String(localized: "watch.hr.waiting", defaultValue: "Waiting")
    }

    private func updateMapCamera(for location: CLLocation, animated: Bool) {
        let update = {
            mapPosition = .camera(LiveSessionMapCamera.camera(for: LiveSessionMapLocation(
                coordinate: location.coordinate,
                course: location.course,
                updatedAt: location.timestamp
            )))
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.6)) {
                update()
            }
        } else {
            update()
        }
    }

    private func updateMapCamera(for coordinate: CLLocationCoordinate2D, animated: Bool) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        updateMapCamera(for: location, animated: animated)
    }
}

private struct RouteEndpointPin: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 3)
    }
}

private struct RouteGuidanceStatusView: View {
    let snapshot: RouteGuidanceSnapshot
    let unitSystem: MeasurementUnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(statusColor)
                    .frame(width: 30, height: 30)
                    .background(statusColor.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "route.guidance.title", defaultValue: "Route Guidance"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(statusText)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 8)

                Text(progressText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            ProgressView(value: snapshot.progressFraction)
                .tint(statusColor)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color(.systemBackground).opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch snapshot.state {
        case .acquiring:
            String(localized: "route.guidance.status.acquiring", defaultValue: "Go to the route start to begin")
        case .onRoute:
            String(localized: "route.guidance.status.on_route", defaultValue: "On route")
        case .offRoute:
            String(localized: "route.guidance.status.off_route", defaultValue: "Off route")
        case .wrongWay:
            String(localized: "route.guidance.status.wrong_way", defaultValue: "Wrong way")
        case .arrived:
            String(localized: "route.guidance.status.arrived", defaultValue: "Route complete")
        }
    }

    private var statusIcon: String {
        switch snapshot.state {
        case .acquiring: "location.magnifyingglass"
        case .onRoute: "location.fill"
        case .offRoute: "exclamationmark.triangle.fill"
        case .wrongWay: "arrow.uturn.backward.circle.fill"
        case .arrived: "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch snapshot.state {
        case .acquiring: .secondary
        case .onRoute: .blue
        case .offRoute, .wrongWay: .orange
        case .arrived: .green
        }
    }

    private var progressText: String {
        String(
            format: String(
                localized: "route.guidance.status.progress_format",
                defaultValue: "%1$@ remaining · %2$d%% complete"
            ),
            locale: .autoupdatingCurrent,
            unitSystem.distanceString(meters: snapshot.remainingDistanceMeters, fractionDigits: 1),
            Int((snapshot.progressFraction * 100).rounded())
        )
    }
}

private struct LiveGroupManagementPanel: View {
    let title: String
    let statusSummary: String
    let participants: [LiveGroupParticipant]
    @Binding var isExpanded: Bool
    let isCreator: Bool
    let onInvite: () -> Void
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.blue))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(statusSummary)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color(.tertiarySystemBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse group run" : "Expand group run")
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(participants) { participant in
                        HStack(spacing: 9) {
                            Text(participant.initials)
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(participant.isCurrentUser ? Color.orange : Color.blue))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(participant.isCurrentUser ? "You" : participant.displayName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(statusText(for: participant))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }

                    HStack(spacing: 8) {
                        Button(action: onInvite) {
                            Label(String(localized: "common.invite", defaultValue: "Invite"), systemImage: "square.and.arrow.up")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(Color(.tertiarySystemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive, action: onStop) {
                            Label(isCreator ? "End" : "Leave", systemImage: "xmark")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .background(Color(.tertiarySystemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground).opacity(0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private func statusText(for participant: LiveGroupParticipant) -> String {
        guard let lastLocationAt = participant.lastLocationAt else {
            return participant.statusLabel
        }
        let seconds = max(0, Int(Date().timeIntervalSince(lastLocationAt)))
        let age = seconds < 60 ? "\(seconds)s ago" : "\(seconds / 60)m ago"
        return participant.isFresh ? "Live - \(age)" : "\(participant.statusLabel) - \(age)"
    }
}

private struct LiveGroupParticipantPin: View {
    let participant: LiveGroupParticipant
    let displayedAt: Date

    private var participantAccessibilityLabel: String {
        if participant.isFresh {
            return String(localized: "\(participant.displayName), live")
        }
        return String(localized: "\(participant.displayName), last seen")
    }

    var body: some View {
        Text(participant.initials)
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(pinColor.opacity(participant.isFresh ? 1 : 0.52), in: Circle())
            .overlay {
                Circle()
                    .stroke(.white, lineWidth: 3)
            }
            .shadow(radius: 4)
            .accessibilityLabel(participantAccessibilityLabel)
    }

    private var pinColor: Color {
        let palette: [Color] = [.blue, .green, .purple, .pink, .teal]
        let index = abs(participant.id.hashValue) % palette.count
        return palette[index]
    }
}

private struct LiveGroupRunnerPill: Identifiable {
    let id: String
    let displayName: String
    let avatarURL: String?
    let liveParticipant: LiveGroupParticipant?

    var isSharingLocation: Bool {
        liveParticipant?.status == "active" || liveParticipant?.status == "stale"
    }
}

/// Single source for the freshness and accuracy copy in the runner strip and the
/// participant pins, so both surfaces age from the same displayed clock.
enum LiveGroupLocationText {
    static func status(_ participant: LiveGroupParticipant?, displayedAt: Date) -> String {
        guard let participant, participant.status == "active" || participant.status == "stale" else {
            return String(localized: "group.activity.location_not_sharing", table: "GroupActivity")
        }
        guard let measuredAt = participant.lastLocationAt else {
            return String(localized: "group.activity.location_waiting", table: "GroupActivity")
        }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 1
        let age = formatter.string(from: max(0, displayedAt.timeIntervalSince(measuredAt))) ?? "0"
        let format = participant.isFresh
            ? String(localized: "group.activity.location_recent", table: "GroupActivity")
            : String(localized: "group.activity.location_stale", table: "GroupActivity")
        return String(format: format, age)
    }

    static func accuracy(_ participant: LiveGroupParticipant?) -> String? {
        guard let accuracy = participant?.accuracyMeters, accuracy.isFinite, accuracy >= 0 else { return nil }
        return String(format: String(localized: "group.activity.location_accuracy", table: "GroupActivity"), Int(min(accuracy, 100_000)))
    }
}

private struct LiveGroupRunnerStrip: View {
    let participants: [LiveGroupRunnerPill]
    let displayedAt: Date
    let focusedParticipantID: String?
    let onSelect: (LiveGroupRunnerPill) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(participants.prefix(5))) { participant in
                    Button {
                        onSelect(participant)
                    } label: {
                        HStack(spacing: 6) {
                            SocialAvatar(name: participant.displayName, avatarURL: participant.avatarURL, size: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(shortName(for: participant))
                                    .font(.caption.weight(.bold))
                                    .lineLimit(1)
                                Text(LiveGroupLocationText.status(participant.liveParticipant, displayedAt: displayedAt))
                                    .font(.caption2)
                                if let accuracy = LiveGroupLocationText.accuracy(participant.liveParticipant) {
                                    Text(accuracy)
                                        .font(.caption2)
                                }
                            }
                            Image(systemName: participant.isSharingLocation ? "location.fill" : "location.slash")
                                .font(.caption2)
                                .foregroundStyle(participant.isSharingLocation ? Color.green : Color.secondary)
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 52)
                        .background(.regularMaterial, in: Capsule())
                        .overlay {
                            Capsule().stroke(isFocused(participant) ? Color.orange : Color.primary.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("live.group.participant.\(participant.id)")
                    .accessibilityLabel(participant.displayName)
                    .accessibilityValue(accessibilitySummary(participant))
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// Screen readers hear the same freshness and GPS uncertainty the pill shows.
    private func accessibilitySummary(_ participant: LiveGroupRunnerPill) -> String {
        let sharing = String(localized: participant.isSharingLocation
            ? "group.activity.location_sharing" : "group.activity.location_not_sharing", table: "GroupActivity")
        guard participant.isSharingLocation, participant.liveParticipant?.lastLocationAt != nil else { return sharing }
        let status = LiveGroupLocationText.status(participant.liveParticipant, displayedAt: displayedAt)
        guard let accuracy = LiveGroupLocationText.accuracy(participant.liveParticipant) else { return "\(sharing), \(status)" }
        return "\(sharing), \(status), \(accuracy)"
    }

    private func isFocused(_ participant: LiveGroupRunnerPill) -> Bool {
        guard let focusedParticipantID else { return false }
        return participant.liveParticipant?.id == focusedParticipantID
    }

    private func shortName(for participant: LiveGroupRunnerPill) -> String {
        let parts = participant.displayName.split(separator: " ")
        guard let first = parts.first else { return participant.displayName }
        let duplicates = participants.filter {
            $0.displayName.split(separator: " ").first?.lowercased() == first.lowercased()
        }.count > 1
        guard duplicates, parts.count > 1, let initial = parts.last?.first else { return String(first) }
        return "\(first) \(initial)."
    }
}

struct LiveGroupTopControlsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
