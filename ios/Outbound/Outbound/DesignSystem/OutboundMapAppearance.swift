import MapKit
import SwiftUI

/// Basemap appearance is independent of the selected app appearance.
/// Scope this to the map leaf, before adding surrounding controls or overlays.
enum OutboundMapAppearance {
    static func apply(to mapView: MKMapView) {
        mapView.overrideUserInterfaceStyle = .light
    }

    nonisolated static func apply(to options: MKMapSnapshotter.Options) {
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
    }
}

extension View {
    func outboundMapAppearance() -> some View {
        environment(\.colorScheme, .light)
    }
}
