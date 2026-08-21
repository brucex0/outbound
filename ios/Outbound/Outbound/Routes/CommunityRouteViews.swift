import CoreLocation
import Combine
import MapKit
import SwiftUI
import UniformTypeIdentifiers

enum CommunityRouteLibraryMode { case discover, mine }

struct CommunityRouteLibraryView: View {
    @EnvironmentObject private var store: CommunityRouteStore
    @StateObject private var locator = RouteDiscoveryLocator()
    @State private var query = ""
    @State private var importsFile = false
    @State private var importedRoute: PreparedRoute?
    let mode: CommunityRouteLibraryMode

    init(mode: CommunityRouteLibraryMode = .discover) { self.mode = mode }

    private var routes: [CommunityRoute] { mode == .mine ? store.mine : store.discovered }

    var body: some View {
        List {
            if mode == .discover {
                Section {
                    Button { locator.requestLocation() } label: { Label("Find routes near me", systemImage: "location.fill") }
                    Button { importsFile = true } label: { Label("Import GPX or GeoJSON", systemImage: "square.and.arrow.down") }
                }
            }
            Section(mode == .mine ? String(localized: "Saved and published") : String(localized: "Community routes")) {
                if store.isLoading && routes.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                else if routes.isEmpty { ContentUnavailableView(mode == .mine ? "No saved routes" : "No routes found", systemImage: "map", description: Text(mode == .mine ? "Publish a route from one of your activities or save a community route." : "Try another search or import a route to follow.")) }
                else { ForEach(routes) { route in NavigationLink { CommunityRouteDetailView(route: route) } label: { CommunityRouteRow(route: route) } } }
            }
        }
        .navigationTitle(mode == .mine ? "My Routes" : "Explore Routes")
        .searchable(text: $query, prompt: "Route or location")
        .onSubmit(of: .search) { Task { await store.search(query) } }
        .task { if mode == .mine { await store.refreshMine() } else { await store.refreshDiscovery() } }
        .onChange(of: locator.location) { _, location in guard let location else { return }; Task { await store.refreshNearby(location: location) } }
        .fileImporter(isPresented: $importsFile, allowedContentTypes: [.xml, .json, .data]) { result in
            do {
                let url = try result.get(); guard url.startAccessingSecurityScopedResource() else { throw RouteImportError.invalid }; defer { url.stopAccessingSecurityScopedResource() }
                importedRoute = try RouteFileImporter.parse(data: Data(contentsOf: url), filename: url.lastPathComponent)
            } catch { store.errorMessage = error.localizedDescription }
        }
        .navigationDestination(item: $importedRoute) { route in PreparedRoutePreview(route: route) }
        .overlay(alignment: .top) { if let message = store.errorMessage { RouteToast(message: message).onTapGesture { store.errorMessage = nil } } }
    }
}

private struct CommunityRouteRow: View {
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    let route: CommunityRoute
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: route.routeShape == "loop" ? "arrow.triangle.2.circlepath" : "point.topleft.down.to.point.bottomright.curvepath")
                .foregroundStyle(.orange).frame(width: 34, height: 34).background(.orange.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(route.name).font(.headline)
                Text("\(measurementPreferences.unitSystem.distanceString(meters: route.distanceM, fractionDigits: 1)) · by \(route.owner.displayName)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if route.isBookmarked { Image(systemName: "bookmark.fill").foregroundStyle(.orange) }
        }
    }
}

struct CommunityRouteDetailView: View {
    @EnvironmentObject private var store: CommunityRouteStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    let route: CommunityRoute
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RoutePreviewMap(points: route.prepared.points).frame(height: 310).clipShape(RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 6) {
                    Text(route.name).font(.title2.bold())
                    Text("Created by \(route.owner.displayName)").foregroundStyle(.secondary)
                    HStack {
                        Label(measurementPreferences.unitSystem.distanceString(meters: route.distanceM, fractionDigits: 1), systemImage: "arrow.left.and.right")
                        if let elevation = route.elevationGainM { Label(measurementPreferences.unitSystem.elevationString(meters: elevation), systemImage: "mountain.2") }
                    }.font(.subheadline.weight(.semibold))
                    Text("\(route.bookmarkCount) saves · \(route.completionCount) completions").font(.caption).foregroundStyle(.secondary)
                    if let description = route.description { Text(description).padding(.top, 4) }
                }
                Button { store.launch(route.prepared) } label: { Label("Start Route", systemImage: "figure.run").frame(maxWidth: .infinity, minHeight: 48) }.buttonStyle(.borderedProminent).tint(.orange)
                Button { Task { await store.toggleBookmark(route) } } label: { Label(route.isBookmarked ? "Remove from My Routes" : "Save to My Routes", systemImage: route.isBookmarked ? "bookmark.slash" : "bookmark") }.buttonStyle(.bordered).frame(maxWidth: .infinity)
            }.padding()
        }.navigationBarTitleDisplayMode(.inline)
    }
}

private struct PreparedRoutePreview: View {
    @EnvironmentObject private var store: CommunityRouteStore
    let route: PreparedRoute
    var body: some View {
        VStack(spacing: 20) {
            RoutePreviewMap(points: route.points).clipShape(RoundedRectangle(cornerRadius: 18))
            VStack(spacing: 5) { Text(route.name).font(.title2.bold()); Text("Imported routes stay private on this device until you complete and save your own activity.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            Button { store.launch(route) } label: { Label("Use for Activity", systemImage: "figure.run").frame(maxWidth: .infinity, minHeight: 48) }.buttonStyle(.borderedProminent).tint(.orange)
        }.padding().navigationTitle("Import Route").navigationBarTitleDisplayMode(.inline)
    }
}

struct RoutePreviewMap: View {
    let points: [RouteCoordinate]
    @State private var position: MapCameraPosition = .automatic
    var body: some View {
        Map(position: $position) { if points.count > 1 { MapPolyline(coordinates: points.map(\.locationCoordinate)).stroke(.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)) } }
            .mapStyle(.standard(elevation: .realistic)).onAppear { position = .rect(mapRect) }
    }
    private var mapRect: MKMapRect { points.reduce(MKMapRect.null) { partial, point in let mapPoint = MKMapPoint(point.locationCoordinate); return partial.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 1, height: 1)) }.insetBy(dx: -2000, dy: -2000) }
}

private struct RouteToast: View { let message: String; var body: some View { Label(message, systemImage: "exclamationmark.circle.fill").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 10).background(.regularMaterial, in: Capsule()).shadow(radius: 8).padding(.top, 8) } }

final class RouteDiscoveryLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    private let manager = CLLocationManager()
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyKilometer }
    func requestLocation() { if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }; manager.requestLocation() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { location = locations.last }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
