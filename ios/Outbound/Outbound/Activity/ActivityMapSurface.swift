import CoreLocation
import MapKit
import SwiftUI

/// Insets published by an activity host so map content and system attribution
/// remain visible above app-owned controls. The map itself does not know which
/// control produced the obstruction.
struct ActivityMapSafeZone: Equatable {
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0

    var edgeInsets: EdgeInsets {
        EdgeInsets(
            top: topInset,
            leading: leadingInset,
            bottom: bottomInset,
            trailing: trailingInset
        )
    }

    static let zero = ActivityMapSafeZone()
}

struct MapAttributionOcclusionHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ActivityLaunchFloatingContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func reportsMapAttributionOcclusionHeight() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MapAttributionOcclusionHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
    }

    func reportsActivityLaunchFloatingContentHeight() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ActivityLaunchFloatingContentHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
    }
}

/// Shared map host contract. Launch and live maps can provide different map
/// content while sharing safe-zone and attribution behavior.
struct ActivityMapSurface<Content: View>: View {
    let safeZone: ActivityMapSafeZone
    @ViewBuilder let content: () -> Content

    init(
        safeZone: ActivityMapSafeZone = .zero,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.safeZone = safeZone
        self.content = content
    }

    var body: some View {
        content()
            .safeAreaPadding(safeZone.edgeInsets)
    }
}

struct ActivityLaunchMap: View {
    @Environment(\.outboundTheme) private var theme
    @ObservedObject var locationManager: LocationManager
    let route: PreparedRoute?
    var safeZone: ActivityMapSafeZone = .zero

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    private var routeCoordinates: [CLLocationCoordinate2D] {
        guard let route else { return [] }
        return RouteWorkingGeometry.displayPoints(route.directedPoints).map(\.locationCoordinate)
    }

    private var routeCameraKey: String? {
        route.map { "\($0.id):\($0.direction.rawValue)" }
    }

    private var routeEndpointsOverlap: Bool {
        guard let start = routeCoordinates.first, let finish = routeCoordinates.last else { return false }
        return CLLocation(latitude: start.latitude, longitude: start.longitude)
            .distance(from: CLLocation(latitude: finish.latitude, longitude: finish.longitude)) <= 20
    }

    var body: some View {
        ActivityMapSurface(safeZone: safeZone) {
            Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
                if routeCoordinates.count > 1 {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(.white.opacity(0.9), lineWidth: 8)
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(theme.actionColor, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }

                if let start = routeCoordinates.first {
                    Annotation(
                        routeEndpointsOverlap
                            ? String(localized: "route.guidance.map.start_finish", defaultValue: "Route start and finish")
                            : String(localized: "route.guidance.map.start", defaultValue: "Route start"),
                        coordinate: start
                    ) {
                        Image(systemName: routeEndpointsOverlap ? "flag.checkered" : "figure.run")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(routeEndpointsOverlap ? theme.actionColor : Color.green, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(radius: 3)
                    }
                }

                if let finish = routeCoordinates.last, !routeEndpointsOverlap {
                    Annotation(String(localized: "route.guidance.map.finish", defaultValue: "Route finish"), coordinate: finish) {
                        Image(systemName: "flag.checkered")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(theme.actionColor, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(radius: 3)
                    }
                }

                UserAnnotation()
            }
            .onAppear { frameRouteIfNeeded() }
            .onChange(of: routeCameraKey) { _, _ in frameRouteIfNeeded() }
        }
    }

    private func frameRouteIfNeeded() {
        guard routeCoordinates.count > 1 else {
            position = .userLocation(fallback: .automatic)
            return
        }

        let rect = routeCoordinates.reduce(MKMapRect.null) { partial, coordinate in
            partial.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 1, height: 1)))
        }
        position = .rect(rect.insetBy(dx: -max(rect.width * 0.16, 400), dy: -max(rect.height * 0.16, 400)))
    }
}
