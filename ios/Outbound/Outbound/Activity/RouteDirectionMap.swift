import MapKit
import SwiftUI

/// Screen-sized direction marks projected from the same directed geometry as
/// the selected route. This wrapper never owns the map's camera or gestures.
struct RouteDirectionMap<Content: View>: View {
    @Environment(\.analyticsManager) private var analyticsManager
    private let samples: [RouteDirectionSample]
    private let endpoints: [CLLocationCoordinate2D]
    private let color: Color
    private let onCameraChange: () -> Void
    private let content: () -> Content
    @State private var cameraRevision = 0

    init(coordinates: [CLLocationCoordinate2D], color: Color, onCameraChange: @escaping () -> Void = {}, @ViewBuilder content: @escaping () -> Content) {
        samples = RouteDirectionSample.make(coordinates)
        endpoints = [coordinates.first, coordinates.last].compactMap { $0 }
        self.color = color
        self.onCameraChange = onCameraChange
        self.content = content
    }

    var body: some View {
        MapReader { proxy in
            content()
                .overlay {
                    Canvas { context, size in
                        // MapProxy changes without changing its identity. Invalidate
                        // this drawing for every camera frame, including rotation.
                        let _ = cameraRevision
                        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 12)
                        let pins = endpoints.compactMap { proxy.convert($0, to: .local) }
                        var drawn: [CGPoint] = []
                        for sample in samples {
                            guard drawn.count < 12,
                                  let tip = proxy.convert(sample.tip, to: .local),
                                  let behind = proxy.convert(sample.behind, to: .local),
                                  tip.x.isFinite, tip.y.isFinite, behind.x.isFinite, behind.y.isFinite,
                                  bounds.contains(tip),
                                  pins.allSatisfy({ hypot(tip.x - $0.x, tip.y - $0.y) > 30 }),
                                  drawn.allSatisfy({ hypot(tip.x - $0.x, tip.y - $0.y) > 70 }) else { continue }
                            let dx = tip.x - behind.x
                            let dy = tip.y - behind.y
                            let length = hypot(dx, dy)
                            guard length > 0.1 else { continue }
                            let ux = dx / length
                            let uy = dy / length
                            var arrow = Path()
                            arrow.move(to: CGPoint(x: tip.x - ux * 9 - uy * 5, y: tip.y - uy * 9 + ux * 5))
                            arrow.addLine(to: tip)
                            arrow.addLine(to: CGPoint(x: tip.x - ux * 9 + uy * 5, y: tip.y - uy * 9 - ux * 5))
                            context.stroke(arrow, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                            context.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            drawn.append(tip)
                        }
                    }
                    .clipped()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .onMapCameraChange(frequency: .continuous) { _ in
                    if !samples.isEmpty { cameraRevision &+= 1 }
                    onCameraChange()
                }
        }
        .task(id: !samples.isEmpty) {
            guard !samples.isEmpty else { return }
            await analyticsManager?.track(.init(.featureExposed, properties: [.feature: .string("route_direction_arrows")]))
        }
    }
}

private struct RouteDirectionSample {
    let tip: CLLocationCoordinate2D
    let behind: CLLocationCoordinate2D

    static func make(_ coordinates: [CLLocationCoordinate2D]) -> [Self] {
        guard coordinates.count > 1,
              coordinates.allSatisfy({ CLLocationCoordinate2DIsValid($0) }) else { return [] }
        let points = coordinates.map(MKMapPoint.init)
        let worldWidth = MKMapRect.world.width
        // Unwrap each segment across the date line before interpolating it.
        let segments = zip(points, points.dropFirst()).compactMap { start, end -> (start: MKMapPoint, dx: Double, dy: Double, length: Double)? in
            var dx = end.x - start.x
            if dx > worldWidth / 2 { dx -= worldWidth }
            if dx < -worldWidth / 2 { dx += worldWidth }
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length.isFinite, length > 0.01 else { return nil }
            return (start, dx, dy, length)
        }
        let total = segments.reduce(0) { $0 + $1.length }
        guard total.isFinite, total > 0 else { return [] }
        var result: [Self] = []
        var index = 0
        var traversed = 0.0
        // A bounded pool allows the live close-up to find marks between the
        // sparse overview marks without projecting the entire route each frame.
        for sampleIndex in 1...128 {
            let distance = total * Double(sampleIndex) / 129
            while index < segments.count - 1, traversed + segments[index].length < distance {
                traversed += segments[index].length
                index += 1
            }
            let segment = segments[index]
            let fraction = min(1, max(0, (distance - traversed) / segment.length))
            // Keep both projected points on this segment, so bends do not
            // average into a heading that cuts across the route.
            let behindFraction = max(0, fraction - 0.25)
            guard fraction - behindFraction > 0.0001 else { continue }
            func coordinate(_ fraction: Double) -> CLLocationCoordinate2D {
                let x = (segment.start.x + segment.dx * fraction + worldWidth).truncatingRemainder(dividingBy: worldWidth)
                return MKMapPoint(x: x, y: segment.start.y + segment.dy * fraction).coordinate
            }
            result.append(Self(tip: coordinate(fraction), behind: coordinate(behindFraction)))
        }
        return result
    }
}
