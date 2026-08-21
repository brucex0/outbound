import CoreLocation
import Combine
import Foundation

struct RouteCoordinate: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?

    init(latitude: Double, longitude: Double, altitude: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }

    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct PreparedRoute: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let points: [RouteCoordinate]
    let source: Source

    enum Source: String, Codable, Hashable { case community, imported }
}

struct CommunityRoute: Codable, Identifiable, Hashable {
    struct Geometry: Codable, Hashable {
        let type: String
        let coordinates: [[Double]]
    }
    struct Owner: Codable, Hashable {
        let id: String
        let username: String
        let displayName: String
        let avatarUrl: String?
    }

    let id: String
    let name: String
    let description: String?
    let activityType: String
    let visibility: String
    let geometry: Geometry
    let distanceM: Double
    let elevationGainM: Double?
    let routeShape: String
    let bookmarkCount: Int
    let completionCount: Int
    var isBookmarked: Bool
    let isOwnedByCurrentUser: Bool
    let owner: Owner
    let distanceFromSearchM: Double?

    var prepared: PreparedRoute {
        PreparedRoute(
            id: id,
            name: name,
            points: geometry.coordinates.compactMap { value in
                guard value.count >= 2 else { return nil }
                return RouteCoordinate(latitude: value[1], longitude: value[0], altitude: value.count > 2 ? value[2] : nil)
            },
            source: .community
        )
    }
}

struct CommunityRouteListResponse: Decodable { let routes: [CommunityRoute] }
struct PublishCommunityRouteRequest: Encodable { let name: String }
struct RouteBookmarkResponse: Decodable { let ok: Bool; let bookmarked: Bool }

@MainActor
final class CommunityRouteStore: ObservableObject {
    @Published private(set) var imported: [PreparedRoute] = []
    @Published private(set) var discovered: [CommunityRoute] = []
    @Published private(set) var mine: [CommunityRoute] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var pendingLaunch: PreparedRoute?

    private let importedRoutesURL: URL

    init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = applicationSupport.appendingPathComponent("Plainstride", isDirectory: true)
        importedRoutesURL = directory.appendingPathComponent("imported-routes.json")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: importedRoutesURL.path) {
                imported = try JSONDecoder().decode([PreparedRoute].self, from: Data(contentsOf: importedRoutesURL))
            }
        } catch {
            errorMessage = String(localized: "Imported routes could not be loaded.")
        }
    }

    func refreshDiscovery(query: String = "") async {
        isLoading = true
        defer { isLoading = false }
        do {
            discovered = try await APIClient.shared.fetchCommunityRoutes(query: query).routes
        } catch {
            errorMessage = String(localized: "Routes could not be loaded. Try again.")
        }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { await refreshDiscovery(); return }
        isLoading = true
        defer { isLoading = false }
        do {
            let named = try await APIClient.shared.fetchCommunityRoutes(query: trimmed).routes
            let placemarks = try? await CLGeocoder().geocodeAddressString(trimmed)
            let nearby: [CommunityRoute]
            if let location = placemarks?.first?.location {
                nearby = (try? await APIClient.shared.fetchNearbyRoutes(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                ).routes) ?? []
            } else {
                nearby = []
            }
            discovered = (named + nearby).reduce(into: []) { result, route in
                if !result.contains(where: { $0.id == route.id }) { result.append(route) }
            }
        } catch {
            errorMessage = String(localized: "Routes could not be loaded. Try again.")
        }
    }

    func refreshMine() async {
        do { mine = try await APIClient.shared.fetchMyRoutes().routes }
        catch { errorMessage = String(localized: "Your routes could not be loaded.") }
    }

    func refreshNearby(location: CLLocation) async {
        isLoading = true
        defer { isLoading = false }
        do {
            discovered = try await APIClient.shared.fetchNearbyRoutes(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude).routes
        } catch {
            errorMessage = String(localized: "Nearby routes could not be loaded.")
        }
    }

    func publish(activity: SavedActivity, name: String) async -> CommunityRoute? {
        do {
            let route = try await APIClient.shared.publishRoute(activityID: activity.id.uuidString, name: name)
            mine.removeAll { $0.id == route.id }
            mine.insert(route, at: 0)
            return route
        } catch {
            errorMessage = String(localized: "Route could not be published. Try again.")
            return nil
        }
    }

    func toggleBookmark(_ route: CommunityRoute) async {
        do {
            _ = try await APIClient.shared.setRouteBookmark(id: route.id, bookmarked: !route.isBookmarked)
            discovered = discovered.map { item in
                guard item.id == route.id else { return item }
                var updated = item; updated.isBookmarked.toggle(); return updated
            }
            await refreshMine()
        } catch {
            errorMessage = String(localized: "Route could not be saved. Try again.")
        }
    }

    func saveImported(_ route: PreparedRoute) {
        imported.removeAll { $0.id == route.id }
        imported.insert(route, at: 0)
        persistImportedRoutes()
    }

    func deleteImported(_ route: PreparedRoute) {
        imported.removeAll { $0.id == route.id }
        persistImportedRoutes()
    }

    func launch(_ route: PreparedRoute) { pendingLaunch = route }
    func consumeLaunch() { pendingLaunch = nil }

    private func persistImportedRoutes() {
        do {
            let data = try JSONEncoder().encode(imported)
            try data.write(to: importedRoutesURL, options: .atomic)
        } catch {
            errorMessage = String(localized: "Imported routes could not be saved.")
        }
    }
}

enum RouteImportError: LocalizedError {
    case unsupported
    case invalid
    var errorDescription: String? {
        switch self {
        case .unsupported: String(localized: "Choose a GPX or GeoJSON route file.")
        case .invalid: String(localized: "This file does not contain a valid route.")
        }
    }
}

enum RouteFileImporter {
    static func parse(data: Data, filename: String) throws -> PreparedRoute {
        let ext = (filename as NSString).pathExtension.lowercased()
        let points: [RouteCoordinate]
        if ext == "gpx" { points = GPXRouteParser.parse(data) }
        else if ext == "geojson" || ext == "json" { points = try geoJSONPoints(data) }
        else { throw RouteImportError.unsupported }
        guard points.count >= 2 else { throw RouteImportError.invalid }
        return PreparedRoute(id: UUID().uuidString, name: (filename as NSString).deletingPathExtension, points: points, source: .imported)
    }

    private static func geoJSONPoints(_ data: Data) throws -> [RouteCoordinate] {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let geometry = (object?["type"] as? String) == "Feature" ? object?["geometry"] as? [String: Any] : object
        guard geometry?["type"] as? String == "LineString", let coordinates = geometry?["coordinates"] as? [[Any]] else { throw RouteImportError.invalid }
        return coordinates.compactMap { value in
            guard value.count >= 2, let longitude = value[0] as? Double, let latitude = value[1] as? Double, abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
            return RouteCoordinate(latitude: latitude, longitude: longitude, altitude: value.count > 2 ? value[2] as? Double : nil)
        }
    }
}

private final class GPXRouteParser: NSObject, XMLParserDelegate {
    private var points: [RouteCoordinate] = []
    private var pending: (Double, Double)?
    private var text = ""
    private var elevation: Double?

    static func parse(_ data: Data) -> [RouteCoordinate] {
        let delegate = GPXRouteParser(); let parser = XMLParser(data: data); parser.delegate = delegate
        return parser.parse() ? delegate.points : []
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        text = ""
        if ["trkpt", "rtept"].contains(elementName), let lat = attributeDict["lat"].flatMap(Double.init), let lon = attributeDict["lon"].flatMap(Double.init), abs(lat) <= 90, abs(lon) <= 180 { pending = (lat, lon); elevation = nil }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "ele" { elevation = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if ["trkpt", "rtept"].contains(elementName), let pending { points.append(RouteCoordinate(latitude: pending.0, longitude: pending.1, altitude: elevation)); self.pending = nil }
    }
}
