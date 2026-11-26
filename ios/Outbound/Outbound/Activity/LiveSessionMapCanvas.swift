import MapKit
import SwiftUI

struct LiveSessionMapLocation: Equatable {
    let coordinate: CLLocationCoordinate2D
    let course: CLLocationDirection?
    let updatedAt: Date?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.course == rhs.course && lhs.updatedAt == rhs.updatedAt
    }
}

/// Shared map canvas for the runner and invited followers. Both sides use the
/// same route drawing, runner marker, camera distance, and course orientation.
struct LiveSessionMapCanvas<AdditionalContent: MapContent>: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @Binding var position: MapCameraPosition
    @Binding var isFollowingLocation: Bool
    let location: LiveSessionMapLocation?
    let routeSegments: [[CLLocationCoordinate2D]]
    let activityType: ActivityType
    let tint: Color
    let isMoving: Bool
    let reduceMotion: Bool
    let followsLocation: Bool
    let participants: [LiveGroupParticipant]
    let focusedParticipantID: String?
    let onSelectParticipant: (LiveGroupParticipant) -> Void
    let onParticipantFocusInterrupted: () -> Void
    @MapContentBuilder let additionalContent: () -> AdditionalContent
    @State private var displayedLocation: LiveSessionMapLocation?
    @State private var displayedParticipants: [String: CLLocationCoordinate2D] = [:]
    @State private var runnerMotion: LiveMapLocationMotion?
    @State private var participantMotions: [String: LiveMapLocationMotion] = [:]
    @State private var activeParticipantFocus: String?
    @State private var participantCameraOrigin: CLLocationCoordinate2D?
    @State private var participantCameraStarted: ContinuousClock.Instant?

    init(
        position: Binding<MapCameraPosition>,
        isFollowingLocation: Binding<Bool>,
        location: LiveSessionMapLocation?,
        routeSegments: [[CLLocationCoordinate2D]],
        activityType: ActivityType,
        tint: Color,
        isMoving: Bool,
        reduceMotion: Bool,
        followsLocation: Bool,
        participants: [LiveGroupParticipant] = [],
        focusedParticipantID: String? = nil,
        onSelectParticipant: @escaping (LiveGroupParticipant) -> Void = { _ in },
        onParticipantFocusInterrupted: @escaping () -> Void = {},
        @MapContentBuilder additionalContent: @escaping () -> AdditionalContent
    ) {
        _position = position
        _isFollowingLocation = isFollowingLocation
        self.location = location
        self.routeSegments = routeSegments
        self.activityType = activityType
        self.tint = tint
        self.isMoving = isMoving
        self.reduceMotion = reduceMotion
        self.followsLocation = followsLocation
        self.participants = participants
        self.focusedParticipantID = focusedParticipantID
        self.onSelectParticipant = onSelectParticipant
        self.onParticipantFocusInterrupted = onParticipantFocusInterrupted
        self.additionalContent = additionalContent
    }

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
            ForEach(Array(routeSegments.enumerated()), id: \.offset) { _, segment in
                if segment.count > 1 {
                    MapPolyline(coordinates: segment)
                        .stroke(.black.opacity(0.2), lineWidth: 8)
                    MapPolyline(coordinates: segment)
                        .stroke(.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }

            additionalContent()

            ForEach(participants) { participant in
                if let coordinate = displayedParticipants[participant.id] ?? participant.coordinate {
                    Annotation(participant.displayName, coordinate: coordinate) {
                        LiveGroupParticipantPin(participant: participant, displayedAt: Date())
                            .onTapGesture { onSelectParticipant(participant) }
                    }
                }
            }

            if let location = displayedLocation ?? location {
                Annotation(
                    "",
                    coordinate: location.coordinate
                ) {
                    LiveActivityAvatar(
                        activityType: activityType,
                        tint: tint,
                        course: location.course,
                        isMoving: isMoving,
                        reduceMotion: reduceMotion
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        String(localized: "map.annotation.current_activity", defaultValue: "Current activity position")
                    )
                }
            }
        }
        .task(id: RunnerMotionRequest(location: location, followsLocation: followsLocation, reduceMotion: reduceMotion, isMoving: isMoving)) {
            guard let target = location else { displayedLocation = nil; runnerMotion = nil; return }
            // Sample the previous motion at retarget time, even when rapid
            // simulation fixes arrive before the next scheduled display frame.
            let start = runnerMotion?.current ?? displayedLocation ?? target
            let immediate = reduceMotion || !isMoving || displayedLocation == nil
            runnerMotion = LiveMapLocationMotion(start: immediate ? target : start, target: target)
            await animateMotion(immediate: immediate) { progress in
                let displayed = LiveMapMotion.location(from: start, to: target, progress: progress)
                displayedLocation = displayed
                if followsLocation { position = .camera(LiveSessionMapCamera.camera(for: displayed)) }
            }
        }
        .task(id: ParticipantMotionRequest(participants: participants, reduceMotion: reduceMotion, focusedParticipantID: focusedParticipantID)) {
            if activeParticipantFocus != focusedParticipantID {
                activeParticipantFocus = focusedParticipantID
                participantCameraOrigin = position.camera?.centerCoordinate
                participantCameraStarted = ContinuousClock().now
            }
            let starts = displayedParticipants
            let motions = Dictionary(uniqueKeysWithValues: participants.compactMap { participant -> (String, LiveMapLocationMotion)? in
                guard let coordinate = participant.coordinate else { return nil }
                let target = LiveSessionMapLocation(coordinate: coordinate, course: nil, updatedAt: participant.lastLocationAt)
                let start = participantMotions[participant.id]?.current
                    ?? LiveSessionMapLocation(coordinate: starts[participant.id] ?? coordinate, course: nil, updatedAt: nil)
                return (participant.id, LiveMapLocationMotion(start: reduceMotion ? target : start, target: target))
            })
            participantMotions = motions
            await animateMotion(immediate: reduceMotion || (starts.isEmpty && focusedParticipantID == nil)) { progress in
                displayedParticipants = motions.mapValues { LiveMapMotion.location(from: $0.start, to: $0.target, progress: progress).coordinate }
                if let focusedParticipantID, let coordinate = displayedParticipants[focusedParticipantID] {
                    let elapsed = participantCameraStarted?.duration(to: ContinuousClock().now).components
                    let seconds = Double(elapsed?.seconds ?? 1) + Double(elapsed?.attoseconds ?? 0) / 1e18
                    let cameraProgress = reduceMotion ? 1 : min(seconds / 0.9, 1)
                    let center = LiveMapMotion.coordinate(from: participantCameraOrigin ?? coordinate, to: coordinate, progress: cameraProgress)
                    position = .camera(LiveSessionMapCamera.camera(center: center, course: nil))
                }
            }
        }
        .task {
            await analyticsManager?.track(.init(.featureExposed, properties: [.feature: .string("live_map_motion_smoothing")]))
        }
        .onMapCameraChange(frequency: .continuous) { _ in
            if position.positionedByUser {
                isFollowingLocation = false
                if focusedParticipantID != nil { onParticipantFocusInterrupted() }
            }
        }
    }

    /// Both annotation and camera receive the same display frame. A new fix
    /// cancels the old task and resumes from its last displayed position.
    @MainActor
    private func animateMotion(immediate: Bool, update: (Double) -> Void) async {
        if immediate {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { update(1) }
            return
        }
        let clock = ContinuousClock()
        let started = clock.now
        while !Task.isCancelled {
            let elapsed = started.duration(to: clock.now).components
            let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
            let progress = min(seconds / 0.9, 1)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { update(progress) }
            if progress >= 1 { return }
            do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
        }
    }
}

private struct RunnerMotionRequest: Equatable {
    let location: LiveSessionMapLocation?
    let followsLocation: Bool
    let reduceMotion: Bool
    let isMoving: Bool
}

private struct ParticipantMotionRequest: Equatable {
    let participants: [LiveGroupParticipant]
    let reduceMotion: Bool
    let focusedParticipantID: String?
}

private struct LiveMapLocationMotion {
    let start: LiveSessionMapLocation
    let target: LiveSessionMapLocation
    private let started: ContinuousClock.Instant

    init(start: LiveSessionMapLocation, target: LiveSessionMapLocation) {
        self.start = start
        self.target = target
        self.started = ContinuousClock().now
    }

    var current: LiveSessionMapLocation {
        let elapsed = started.duration(to: ContinuousClock().now).components
        let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        return LiveMapMotion.location(from: start, to: target, progress: min(seconds / 0.9, 1))
    }
}

private enum LiveMapMotion {
    static func location(from start: LiveSessionMapLocation, to target: LiveSessionMapLocation, progress: Double) -> LiveSessionMapLocation {
        LiveSessionMapLocation(
            coordinate: coordinate(from: start.coordinate, to: target.coordinate, progress: progress),
            course: course(from: start.course, to: target.course, progress: progress),
            updatedAt: target.updatedAt
        )
    }

    static func coordinate(from start: CLLocationCoordinate2D, to target: CLLocationCoordinate2D, progress: Double) -> CLLocationCoordinate2D {
        let longitude = start.longitude + shortestDelta(from: start.longitude, to: target.longitude) * progress
        return CLLocationCoordinate2D(
            latitude: start.latitude + (target.latitude - start.latitude) * progress,
            longitude: (longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        )
    }

    static func course(from start: CLLocationDirection?, to target: CLLocationDirection?, progress: Double) -> CLLocationDirection {
        let start = start.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
        let target = target.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
        return (start + shortestDelta(from: start, to: target) * progress + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func shortestDelta(from start: Double, to target: Double) -> Double {
        ((target - start + 540).truncatingRemainder(dividingBy: 360)) - 180
    }
}

enum LiveSessionMapCamera {
    static let distance: CLLocationDistance = 400

    static func camera(for location: LiveSessionMapLocation) -> MapCamera {
        camera(center: location.coordinate, course: location.course)
    }

    static func camera(
        center coordinate: CLLocationCoordinate2D,
        course: CLLocationDirection?
    ) -> MapCamera {
        let heading = course.flatMap { $0 >= 0 && $0.isFinite ? $0 : nil } ?? 0
        return MapCamera(centerCoordinate: coordinate, distance: distance, heading: heading, pitch: 0)
    }
}

struct LiveActivityAvatar: View {
    let activityType: ActivityType
    let tint: Color
    let course: CLLocationDirection?
    let isMoving: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !isMoving || reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * animationFrequency
            let stride = reduceMotion || !isMoving ? 0 : sin(phase * .pi * 2)

            avatarContent(stride: stride)
                .rotationEffect(.degrees(validCourse))
                .offset(y: abs(stride) * -animationAmplitude)
                .frame(width: 30, height: 30)
                .shadow(color: .white.opacity(0.9), radius: 1.5)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
        }
    }

    @ViewBuilder
    private func avatarContent(stride: Double) -> some View {
        switch activityType {
        case .running, .walking, .hiking:
            ArticulatedActivityFigure(tint: tint, stride: stride, strideAngle: strideAngle)
        case .cycling, .swimming, .strengthTraining, .mobility:
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
        }
    }

    private var systemImage: String {
        switch activityType {
        case .running: "figure.run"
        case .cycling: "bicycle"
        case .hiking: "figure.hiking"
        case .walking: "figure.walk"
        case .swimming: "figure.open.water.swim"
        case .strengthTraining: "dumbbell.fill"
        case .mobility: "figure.flexibility"
        }
    }

    private var validCourse: Double {
        guard let course, course >= 0, course.isFinite else { return 0 }
        return course
    }

    private var animationFrequency: Double {
        activityType == .cycling ? 2.2 : 1.65
    }

    private var animationAmplitude: Double {
        activityType == .cycling ? 0.8 : 1.5
    }

    private var strideAngle: Double {
        switch activityType {
        case .running: 38
        case .walking: 24
        case .hiking: 28
        case .cycling, .swimming, .strengthTraining, .mobility: 0
        }
    }
}

private struct ArticulatedActivityFigure: View {
    let tint: Color
    let stride: Double
    let strideAngle: Double

    var body: some View {
        ZStack {
            limb(length: 9, width: 3, color: .primary.opacity(0.82))
                .rotationEffect(.degrees(-stride * strideAngle), anchor: .top)
                .offset(x: -2.2, y: 8)

            limb(length: 9, width: 3, color: .primary.opacity(0.82))
                .rotationEffect(.degrees(stride * strideAngle), anchor: .top)
                .offset(x: 2.2, y: 8)

            limb(length: 8, width: 2.5, color: .primary.opacity(0.78))
                .rotationEffect(.degrees(stride * strideAngle * 0.9), anchor: .top)
                .offset(x: -4, y: -1)

            limb(length: 8, width: 2.5, color: .primary.opacity(0.78))
                .rotationEffect(.degrees(-stride * strideAngle * 0.9), anchor: .top)
                .offset(x: 4, y: -1)

            Capsule(style: .continuous)
                .fill(tint)
                .frame(width: 8, height: 12)
                .offset(y: 1.5)

            Circle()
                .fill(Color.primary.opacity(0.88))
                .frame(width: 7, height: 7)
                .offset(y: -8)
        }
        .frame(width: 24, height: 28)
    }

    private func limb(length: CGFloat, width: CGFloat, color: Color) -> some View {
        Capsule(style: .continuous)
            .fill(color)
            .frame(width: width, height: length)
            .frame(width: width, height: length, alignment: .top)
    }
}
