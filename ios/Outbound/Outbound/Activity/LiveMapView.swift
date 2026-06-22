import MapKit
import SwiftUI
import UIKit

struct LiveMapView: View {
    @EnvironmentObject var measurementPreferences: MeasurementPreferences
    @EnvironmentObject var liveGroupStore: LiveGroupStore
    @ObservedObject var recorder: ActivityRecorder
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var coach: VirtualCoach
    @ObservedObject var musicStore: MusicStore
    let intent: SessionIntent?
    let capturedPhotoCount: Int
    let lastCapturedPhoto: UIImage?
    @Binding var activePage: SessionPage
    let onStart: () -> Void
    let onFinish: () -> Void

    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isFollowingUser = true
    @State private var statusCardHeight: CGFloat = 132
    @State private var focusedParticipantID: String?
    @State private var isGroupManagementExpanded = false

    var body: some View {
        ZStack {
            Map(position: $mapPosition, interactionModes: [.pan, .zoom, .rotate]) {
                if let startCoordinate {
                    Annotation("Trail Start", coordinate: startCoordinate) {
                        Circle()
                            .fill(.green)
                            .frame(width: 14, height: 14)
                            .overlay {
                                Circle()
                                    .stroke(.white, lineWidth: 3)
                            }
                            .shadow(radius: 4)
                    }
                }
                if trailCoordinates.count > 1 {
                    MapPolyline(coordinates: trailCoordinates)
                        .stroke(.black.opacity(0.2), lineWidth: 8)
                    MapPolyline(coordinates: trailCoordinates)
                        .stroke(.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if let currentCoordinate {
                    Annotation("Current Position", coordinate: currentCoordinate) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 16, height: 16)
                            .overlay {
                                Circle()
                                    .stroke(.white, lineWidth: 3)
                            }
                            .shadow(radius: 4)
                    }
                }
                ForEach(liveGroupStore.visibleParticipants) { participant in
                    if let coordinate = participant.coordinate {
                        Annotation(participant.displayName, coordinate: coordinate) {
                            LiveGroupParticipantPin(participant: participant)
                                .onTapGesture {
                                    focusedParticipantID = participant.id
                                    isFollowingUser = false
                                    updateMapCamera(for: coordinate, animated: true)
                                }
                        }
                    }
                }
            }
            .onMapCameraChange(frequency: .onEnd) { _ in
                if mapPosition.positionedByUser {
                    isFollowingUser = false
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Spacer()

                if liveGroupStore.isSharing {
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
                }

                if !liveGroupStore.visibleParticipants.isEmpty {
                    LiveGroupRunnerStrip(
                        participants: liveGroupStore.visibleParticipants,
                        currentCoordinate: currentCoordinate,
                        unitSystem: measurementPreferences.unitSystem,
                        focusedParticipantID: focusedParticipantID,
                        onSelect: { participant in
                            guard let coordinate = participant.coordinate else { return }
                            focusedParticipantID = participant.id
                            isFollowingUser = false
                            updateMapCamera(for: coordinate, animated: true)
                        }
                    )
                    .padding(.horizontal, 16)
                }

                SessionStatusCard(
                    state: recorder.state,
                    isCompact: false,
                    intent: intent,
                    elapsedText: recorder.elapsedSeconds.formatted(),
                    elapsedSeconds: recorder.elapsedSeconds,
                    paceLabel: recorder.state == .paused ? "Avg. pace" : "Pace",
                    paceText: sessionPaceText,
                    distanceText: measurementPreferences.unitSystem.distanceValueString(meters: recorder.distanceMeters),
                    distanceMeters: recorder.distanceMeters,
                    distanceLabel: measurementPreferences.unitSystem.distanceLabel,
                    elevationText: measurementPreferences.unitSystem.elevationValueString(meters: recorder.elevationGainMeters),
                    elevationLabel: measurementPreferences.unitSystem.elevationLabel,
                    heartRateText: recorder.heartRate.map { "\($0)" } ?? "--",
                    coachMessage: coachMessage,
                    musicPlayback: musicStore.playback.hasActiveQueue ? musicStore.playback : nil,
                    showsMusicDisabledState: musicStore.hasDeveloperTokenError,
                    musicErrorMessage: musicStore.hasDeveloperTokenError ? nil : musicStore.lastErrorMessage,
                    onTogglePlayback: {
                        Task { await musicStore.togglePlayback() }
                    },
                    onSkipTrack: {
                        Task { await musicStore.skipToNext() }
                    },
                    onStart: onStart,
                    onPause: pauseActivity,
                    onResume: resumeActivity,
                    onFinish: onFinish
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SessionStatusCardHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }

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
        .onReceive(locationManager.$location) { loc in
            guard let loc, isFollowingUser else { return }
            updateMapCamera(for: loc, animated: true)
        }
        .onPreferenceChange(SessionStatusCardHeightPreferenceKey.self) { height in
            statusCardHeight = height
        }
    }

    private var coachMessage: String? {
        guard recorder.state != .idle, !coach.lastNudge.isEmpty else { return nil }
        return coach.lastNudge
    }

    private var trailCoordinates: [CLLocationCoordinate2D] {
        locationManager.trackPoints.map(\.coordinate)
    }

    private var startCoordinate: CLLocationCoordinate2D? {
        trailCoordinates.first
    }

    private var currentCoordinate: CLLocationCoordinate2D? {
        trailCoordinates.last
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
            .accessibilityLabel("Show Camera")

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
            .accessibilityLabel("Recenter Map")
        }
    }

    private var railBottomPadding: CGFloat {
        max(statusCardHeight + 38, 150)
    }

    private var sessionPaceText: String {
        switch recorder.state {
        case .idle:
            return "--"
        case .active:
            return recorder.currentPace?.paceString(for: measurementPreferences.unitSystem) ?? "--"
        case .paused:
            guard recorder.distanceMeters > 0 else { return "--" }
            return (Double(recorder.elapsedSeconds) / (recorder.distanceMeters / 1000)).paceString(for: measurementPreferences.unitSystem)
        }
    }

    private func pauseActivity() {
        recorder.pause()
    }

    private func resumeActivity() {
        recorder.resume()
    }

    private func updateMapCamera(for location: CLLocation, animated: Bool) {
        let update = {
            mapPosition = .camera(MapCamera(
                centerCoordinate: location.coordinate,
                distance: 400,
                heading: location.course >= 0 ? location.course : 0,
                pitch: 0
            ))
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
                            Label("Invite", systemImage: "square.and.arrow.up")
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
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
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
            .accessibilityLabel("\(participant.displayName), \(participant.isFresh ? "live" : "last seen")")
    }

    private var pinColor: Color {
        let palette: [Color] = [.blue, .green, .purple, .pink, .teal]
        let index = abs(participant.id.hashValue) % palette.count
        return palette[index]
    }
}

private struct LiveGroupRunnerStrip: View {
    let participants: [LiveGroupParticipant]
    let currentCoordinate: CLLocationCoordinate2D?
    let unitSystem: MeasurementUnitSystem
    let focusedParticipantID: String?
    let onSelect: (LiveGroupParticipant) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(participants) { participant in
                    Button {
                        onSelect(participant)
                    } label: {
                        HStack(spacing: 8) {
                            Text(participant.initials)
                                .font(.caption.weight(.black))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(pinColor(for: participant).opacity(participant.isFresh ? 1 : 0.52), in: Circle())

                            VStack(alignment: .leading, spacing: 1) {
                                Text(participant.displayName)
                                    .font(.caption.weight(.bold))
                                    .lineLimit(1)
                                Text(statusText(for: participant))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 46)
                        .background(
                            Capsule()
                                .fill(focusedParticipantID == participant.id ? Color.orange.opacity(0.18) : Color(.systemBackground).opacity(0.92))
                        )
                        .overlay {
                            Capsule()
                                .stroke(focusedParticipantID == participant.id ? Color.orange : Color.black.opacity(0.08), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func statusText(for participant: LiveGroupParticipant) -> String {
        var parts: [String] = []
        if let distanceText = distanceText(to: participant.coordinate) {
            parts.append(distanceText)
        }
        if let lastLocationAt = participant.lastLocationAt {
            parts.append(participant.isFresh ? "last \(relativeAge(from: lastLocationAt))" : "last seen \(relativeAge(from: lastLocationAt))")
        } else {
            parts.append("waiting")
        }
        return parts.joined(separator: " - ")
    }

    private func distanceText(to coordinate: CLLocationCoordinate2D?) -> String? {
        guard let currentCoordinate, let coordinate else { return nil }
        let current = CLLocation(latitude: currentCoordinate.latitude, longitude: currentCoordinate.longitude)
        let other = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let meters = current.distance(from: other)
        return unitSystem.distanceValueString(meters: meters)
    }

    private func relativeAge(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m"
    }

    private func pinColor(for participant: LiveGroupParticipant) -> Color {
        let palette: [Color] = [.blue, .green, .purple, .pink, .teal]
        let index = abs(participant.id.hashValue) % palette.count
        return palette[index]
    }
}
