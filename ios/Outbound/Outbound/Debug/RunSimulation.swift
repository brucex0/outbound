#if DEBUG
import CoreLocation
import Foundation
import SwiftUI

struct RunSimulationState: Equatable {
    var speedKilometersPerHour: Double
    var timeRate: Int
    var isClockRunning: Bool
    var elapsedSeconds: Int
    var distanceMeters: Double
    let routeDistanceMeters: Double

    var isComplete: Bool {
        distanceMeters >= routeDistanceMeters
    }

    var speedMetersPerSecond: Double {
        speedKilometersPerHour / 3.6
    }
}

struct RunSimulationRouteSampler {
    private struct Segment {
        let start: RouteCoordinate
        let end: RouteCoordinate
        let startDistanceMeters: Double
        let lengthMeters: Double
        let courseDegrees: CLLocationDirection
    }

    let totalDistanceMeters: Double
    private let segments: [Segment]

    init?(route: PreparedRoute) {
        let points = route.directedPoints
        guard points.count > 1 else { return nil }

        var cumulativeDistance = 0.0
        var builtSegments: [Segment] = []
        builtSegments.reserveCapacity(points.count - 1)
        for (start, end) in zip(points, points.dropFirst()) {
            let startLocation = CLLocation(
                latitude: start.latitude,
                longitude: start.longitude
            )
            let endLocation = CLLocation(
                latitude: end.latitude,
                longitude: end.longitude
            )
            let length = startLocation.distance(from: endLocation)
            guard length > 0 else { continue }
            builtSegments.append(Segment(
                start: start,
                end: end,
                startDistanceMeters: cumulativeDistance,
                lengthMeters: length,
                courseDegrees: Self.course(from: start, to: end)
            ))
            cumulativeDistance += length
        }

        guard cumulativeDistance > 0, !builtSegments.isEmpty else { return nil }
        segments = builtSegments
        totalDistanceMeters = cumulativeDistance
    }

    func location(
        at distanceMeters: Double,
        speedMetersPerSecond: Double,
        timestamp: Date
    ) -> CLLocation? {
        let clampedDistance = max(0, min(distanceMeters, totalDistanceMeters))
        guard let segment = segments.last(where: { $0.startDistanceMeters <= clampedDistance })
            ?? segments.first
        else { return nil }

        let progress = min(
            1,
            max(0, (clampedDistance - segment.startDistanceMeters) / segment.lengthMeters)
        )
        let altitude: Double
        switch (segment.start.altitude, segment.end.altitude) {
        case let (.some(start), .some(end)):
            altitude = start + ((end - start) * progress)
        case let (.some(value), .none), let (.none, .some(value)):
            altitude = value
        case (.none, .none):
            altitude = 0
        }

        return CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: segment.start.latitude
                    + ((segment.end.latitude - segment.start.latitude) * progress),
                longitude: segment.start.longitude
                    + ((segment.end.longitude - segment.start.longitude) * progress)
            ),
            altitude: altitude,
            horizontalAccuracy: 3,
            verticalAccuracy: 3,
            course: segment.courseDegrees,
            speed: clampedDistance >= totalDistanceMeters ? 0 : speedMetersPerSecond,
            timestamp: timestamp
        )
    }

    private static func course(
        from start: RouteCoordinate,
        to end: RouteCoordinate
    ) -> CLLocationDirection {
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let longitudeDelta = (end.longitude - start.longitude) * .pi / 180
        let y = sin(longitudeDelta) * cos(endLatitude)
        let x = cos(startLatitude) * sin(endLatitude)
            - sin(startLatitude) * cos(endLatitude) * cos(longitudeDelta)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

enum HarvestHalfMarathonSimulation {
    static let launchArgument = "-OutboundSimulatedHarvestRun"
    static let routeID = "debug-redmond-harvest-half-marathon"

    /// Derived from Redmond_Harvest_Half_Marathon.gpx supplied for manual testing.
    /// The source's return-leg latitude `47.7900` is corrected to `47.6900` so
    /// the path rejoins its matching outbound point instead of jumping ~11 km north.
    static let route = PreparedRoute(
        id: routeID,
        name: String(
            localized: "run.simulation.route.name",
            defaultValue: "Redmond Harvest Half Marathon"
        ),
        points: [
            RouteCoordinate(latitude: 47.6705, longitude: -122.1215, altitude: 42),
            RouteCoordinate(latitude: 47.6730, longitude: -122.1215, altitude: 42),
            RouteCoordinate(latitude: 47.6730, longitude: -122.1280, altitude: 35),
            RouteCoordinate(latitude: 47.6780, longitude: -122.1310, altitude: 32),
            RouteCoordinate(latitude: 47.6900, longitude: -122.1395, altitude: 30),
            RouteCoordinate(latitude: 47.7050, longitude: -122.1480, altitude: 28),
            RouteCoordinate(latitude: 47.7200, longitude: -122.1550, altitude: 25),
            RouteCoordinate(latitude: 47.7350, longitude: -122.1580, altitude: 24),
            RouteCoordinate(latitude: 47.7450, longitude: -122.1610, altitude: 22),
            RouteCoordinate(latitude: 47.7350, longitude: -122.1580, altitude: 24),
            RouteCoordinate(latitude: 47.7200, longitude: -122.1550, altitude: 25),
            RouteCoordinate(latitude: 47.7050, longitude: -122.1480, altitude: 28),
            RouteCoordinate(latitude: 47.6900, longitude: -122.1395, altitude: 30),
            RouteCoordinate(latitude: 47.6780, longitude: -122.1310, altitude: 32),
            RouteCoordinate(latitude: 47.6705, longitude: -122.1215, altitude: 42),
        ],
        source: .imported,
        activityType: .running,
        routeShape: "out_and_back"
    )
}

struct RunSimulationControls: View {
    @ObservedObject var recorder: ActivityRecorder
    let onControlUsed: (_ control: String, _ selection: String) -> Void

    var body: some View {
        if let state = recorder.runSimulationState {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Label(
                        String(localized: "run.simulation.title", defaultValue: "Run Simulation"),
                        systemImage: "figure.run.circle.fill"
                    )
                    .font(.subheadline.weight(.bold))

                    Spacer(minLength: 4)

                    Text(state.elapsedSeconds.formatted())
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))

                    Menu {
                        ForEach([1, 10, 60], id: \.self) { rate in
                            Button {
                                recorder.setRunSimulationTimeRate(rate)
                                onControlUsed("time_rate", "rate_\(rate)x")
                            } label: {
                                if rate == state.timeRate {
                                    Label("\(rate)×", systemImage: "checkmark")
                                } else {
                                    Text("\(rate)×")
                                }
                            }
                        }
                    } label: {
                        Label("\(state.timeRate)×", systemImage: "speedometer")
                            .font(.caption.weight(.semibold))
                    }
                    .accessibilityLabel(String(localized: "run.simulation.time_rate", defaultValue: "Simulated time rate"))

                    Button {
                        recorder.toggleRunSimulationClock()
                        onControlUsed("clock", state.isClockRunning ? "paused" : "playing")
                    } label: {
                        Image(systemName: state.isClockRunning ? "pause.fill" : "play.fill")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .tint(.orange)
                    .disabled(recorder.state != .active || state.isComplete)
                    .accessibilityLabel(state.isClockRunning
                        ? String(localized: "run.simulation.clock.pause", defaultValue: "Pause simulated time")
                        : String(localized: "run.simulation.clock.play", defaultValue: "Advance simulated time"))
                }

                HStack(spacing: 8) {
                    Button {
                        recorder.adjustRunSimulationSpeed(byKilometersPerHour: -1)
                        onControlUsed("speed", recorder.runSimulationSpeedBucket)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .accessibilityLabel(String(localized: "run.simulation.speed.decrease", defaultValue: "Decrease simulated speed"))

                    Text(speedText(state.speedKilometersPerHour))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .frame(minWidth: 66)

                    Button {
                        recorder.adjustRunSimulationSpeed(byKilometersPerHour: 1)
                        onControlUsed("speed", recorder.runSimulationSpeedBucket)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(String(localized: "run.simulation.speed.increase", defaultValue: "Increase simulated speed"))

                    Spacer(minLength: 4)

                    Button {
                        recorder.advanceRunSimulation(by: 60)
                        onControlUsed("time_advance", "1m")
                    } label: {
                        Text(String(localized: "run.simulation.advance.one_minute", defaultValue: "+1m"))
                    }
                    .disabled(recorder.state != .active || state.isComplete)

                    Button {
                        recorder.advanceRunSimulation(by: 300)
                        onControlUsed("time_advance", "5m")
                    } label: {
                        Text(String(localized: "run.simulation.advance.five_minutes", defaultValue: "+5m"))
                    }
                    .disabled(recorder.state != .active || state.isComplete)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.orange.opacity(0.5), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
            .accessibilityElement(children: .contain)
        }
    }

    private func speedText(_ speed: Double) -> String {
        String(
            format: String(localized: "run.simulation.speed.format", defaultValue: "%.0f km/h"),
            locale: .autoupdatingCurrent,
            speed
        )
    }
}
#endif
