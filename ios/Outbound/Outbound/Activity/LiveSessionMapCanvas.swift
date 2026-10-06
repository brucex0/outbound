import MapKit
import SwiftUI

struct LiveSessionMapLocation {
    let coordinate: CLLocationCoordinate2D
    let course: CLLocationDirection?
    let updatedAt: Date?
}

/// Shared map canvas for the runner and invited followers. Both sides use the
/// same route drawing, runner marker, camera distance, and course orientation.
struct LiveSessionMapCanvas<AdditionalContent: MapContent>: View {
    @Binding var position: MapCameraPosition
    @Binding var isFollowingLocation: Bool
    let location: LiveSessionMapLocation?
    let routeSegments: [[CLLocationCoordinate2D]]
    let activityType: ActivityType
    let tint: Color
    let isMoving: Bool
    let reduceMotion: Bool
    let followsLocation: Bool
    @MapContentBuilder let additionalContent: () -> AdditionalContent

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

            if let location {
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
        .onChange(of: location?.updatedAt, initial: true) { _, _ in
            guard followsLocation, let location else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                position = .camera(LiveSessionMapCamera.camera(for: location))
            }
        }
        .onMapCameraChange(frequency: .onEnd) { _ in
            if position.positionedByUser {
                isFollowingLocation = false
            }
        }
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
