import CoreLocation
import Combine
import Foundation

nonisolated struct RouteCoordinate: Codable, Hashable {
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

nonisolated enum RouteDirection: String, Codable, CaseIterable, Hashable {
    case forward
    case reverse
}

nonisolated struct PreparedRoute: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let points: [RouteCoordinate]
    let source: Source
    let activityType: ActivityType?
    let routeShape: String?
    let direction: RouteDirection

    nonisolated enum Source: String, Codable, Hashable { case community, imported }

    init(
        id: String,
        name: String,
        points: [RouteCoordinate],
        source: Source,
        activityType: ActivityType? = nil,
        routeShape: String? = nil,
        direction: RouteDirection = .forward
    ) {
        self.id = id
        self.name = name
        self.points = points
        self.source = source
        self.activityType = activityType
        self.routeShape = routeShape
        self.direction = direction
    }

    var directedPoints: [RouteCoordinate] {
        direction == .forward ? points : Array(points.reversed())
    }

    var isLoop: Bool { routeShape == "loop" }

    var hasValidCanonicalGeometry: Bool {
        let maximumCount = source == .imported ? RouteFileImporter.maximumPointCount : 100_000
        guard (2...maximumCount).contains(points.count) else { return false }
        return points.allSatisfy { point in
            point.latitude.isFinite
                && point.longitude.isFinite
                && abs(point.latitude) <= 90
                && abs(point.longitude) <= 180
                && (point.altitude?.isFinite ?? true)
        }
    }

    var isUsableForGuidance: Bool {
        guard hasValidCanonicalGeometry else { return false }
        return RouteWorkingGeometry.isRepresentableForNavigation(points)
    }

    func withDirection(_ direction: RouteDirection) -> PreparedRoute {
        PreparedRoute(
            id: id,
            name: name,
            points: points,
            source: source,
            activityType: activityType,
            routeShape: routeShape,
            direction: direction
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, points, source, activityType, routeShape, direction
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        points = try container.decode([RouteCoordinate].self, forKey: .points)
        source = try container.decode(Source.self, forKey: .source)
        activityType = try container.decodeIfPresent(ActivityType.self, forKey: .activityType)
        routeShape = try container.decodeIfPresent(String.self, forKey: .routeShape)
        direction = try container.decodeIfPresent(RouteDirection.self, forKey: .direction) ?? .forward
    }
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
    let geometry: Geometry?
    let distanceM: Double
    let elevationGainM: Double?
    let routeShape: String
    let bookmarkCount: Int
    let completionCount: Int
    var isBookmarked: Bool
    let isOwnedByCurrentUser: Bool
    let owner: Owner
    let distanceFromSearchM: Double?

    var prepared: PreparedRoute? {
        guard let geometry,
              geometry.type == "LineString",
              (2...100_000).contains(geometry.coordinates.count)
        else { return nil }
        var points: [RouteCoordinate] = []
        points.reserveCapacity(geometry.coordinates.count)
        for value in geometry.coordinates {
            guard (2...3).contains(value.count),
                  value[0].isFinite,
                  value[1].isFinite,
                  abs(value[0]) <= 180,
                  abs(value[1]) <= 90,
                  value.count < 3 || value[2].isFinite
            else { return nil }
            points.append(RouteCoordinate(
                latitude: value[1],
                longitude: value[0],
                altitude: value.count == 3 ? value[2] : nil
            ))
        }
        let route = PreparedRoute(
            id: id,
            name: name,
            points: points,
            source: .community,
            activityType: ActivityType(rawValue: activityType),
            routeShape: routeShape
        )
        return route.isUsableForGuidance ? route : nil
    }
}

struct CommunityRouteListResponse: Decodable { let routes: [CommunityRoute] }
struct PublishCommunityRouteRequest: Encodable { let name: String }
struct RouteBookmarkResponse: Decodable { let ok: Bool; let bookmarked: Bool }
struct CommunityRouteMutationResponse: Decodable { let ok: Bool }

@MainActor
final class CommunityRouteStore: ObservableObject {
    @Published private(set) var imported: [PreparedRoute] = []
    @Published private(set) var discovered: [CommunityRoute] = []
    @Published private(set) var mine: [CommunityRoute] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var pendingLaunch: PreparedRoute?

    private let importedRoutesURL: URL
    private let communityRouteCacheURL: URL
    private let communityRouteCacheOrderURL: URL
    private var cachedCommunityRoutes: [String: PreparedRoute] = [:]
    private var cachedCommunityRouteOrder: [String] = []
    private let maximumCachedCommunityRoutes = 20
    private let maximumCachedCommunityPointCount = 100_000
    private let maximumImportedRoutes = 100
    private let maximumImportedPointCount = 250_000

    init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = applicationSupport.appendingPathComponent("Plainstride", isDirectory: true)
        importedRoutesURL = directory.appendingPathComponent("imported-routes.json")
        communityRouteCacheURL = directory.appendingPathComponent("community-route-cache.json")
        communityRouteCacheOrderURL = directory.appendingPathComponent("community-route-cache-order.json")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: importedRoutesURL.path) {
                let decoded = try JSONDecoder().decode(
                    [PreparedRoute].self,
                    from: Data(contentsOf: importedRoutesURL)
                )
                var retained: [PreparedRoute] = []
                var retainedIDs: Set<String> = []
                var pointCount = 0
                for route in decoded where route.source == .imported && route.isUsableForGuidance {
                    guard retained.count < maximumImportedRoutes,
                          !retainedIDs.contains(route.id),
                          pointCount <= maximumImportedPointCount - route.points.count
                    else { continue }
                    retained.append(route)
                    retainedIDs.insert(route.id)
                    pointCount += route.points.count
                }
                imported = retained
                if retained != decoded {
                    try JSONEncoder().encode(retained).write(to: importedRoutesURL, options: .atomic)
                }
            }
            if fileManager.fileExists(atPath: communityRouteCacheURL.path) {
                let cached = try JSONDecoder().decode([PreparedRoute].self, from: Data(contentsOf: communityRouteCacheURL))
                let valid = cached.filter { $0.source == .community && $0.isUsableForGuidance }
                cachedCommunityRoutes = valid.reduce(into: [:]) { routes, route in
                    routes[route.id] = route
                }

                let persistedOrder: [String]
                if fileManager.fileExists(atPath: communityRouteCacheOrderURL.path),
                   let decodedOrder = try? JSONDecoder().decode(
                       [String].self,
                       from: Data(contentsOf: communityRouteCacheOrderURL)
                   ) {
                    persistedOrder = decodedOrder
                } else {
                    persistedOrder = valid.map(\.id)
                }

                var orderedIDs: [String] = []
                var seenIDs: Set<String> = []
                for id in persistedOrder where cachedCommunityRoutes[id] != nil && seenIDs.insert(id).inserted {
                    orderedIDs.append(id)
                }
                for id in valid.map(\.id) where seenIDs.insert(id).inserted {
                    orderedIDs.append(id)
                }
                cachedCommunityRouteOrder = orderedIDs
                trimCommunityRouteCacheToLimits()

                let retained = cachedCommunityRouteOrder.compactMap { cachedCommunityRoutes[$0] }
                cachedCommunityRoutes = Dictionary(uniqueKeysWithValues: retained.map { ($0.id, $0) })
                if retained != cached {
                    try JSONEncoder().encode(retained).write(to: communityRouteCacheURL, options: .atomic)
                }
                try JSONEncoder().encode(cachedCommunityRouteOrder)
                    .write(to: communityRouteCacheOrderURL, options: .atomic)
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

    func publish(activityID: String, name: String) async -> CommunityRoute? {
        do {
            let route = try await APIClient.shared.publishRoute(activityID: activityID, name: name)
            if let prepared = route.prepared { cacheCommunityRoute(prepared) }
            mine.removeAll { $0.id == route.id }
            mine.insert(route, at: 0)
            return route
        } catch {
            errorMessage = String(localized: "Route could not be published. Try again.")
            return nil
        }
    }

    func setBookmarked(_ route: CommunityRoute, bookmarked: Bool) async -> Bool? {
        do {
            let response = try await APIClient.shared.setRouteBookmark(id: route.id, bookmarked: bookmarked)
            discovered = discovered.map { item in
                guard item.id == route.id else { return item }
                var updated = item
                updated.isBookmarked = response.bookmarked
                return updated
            }
            if response.bookmarked {
                var updated = route
                updated.isBookmarked = true
                mine.removeAll { $0.id == route.id }
                mine.insert(updated, at: 0)
                await refreshMine()
            } else {
                mine = mine.compactMap { item in
                    guard item.id == route.id else { return item }
                    guard item.isOwnedByCurrentUser else { return nil }
                    var updated = item
                    updated.isBookmarked = false
                    return updated
                }
            }
            return response.bookmarked
        } catch {
            errorMessage = String(localized: "Route could not be saved. Try again.")
            return nil
        }
    }

    func removePublishedRoute(_ route: CommunityRoute) async -> Bool {
        guard route.isOwnedByCurrentUser else { return false }
        do {
            let response = try await APIClient.shared.removePublishedRoute(id: route.id)
            guard response.ok else { return false }
            mine.removeAll { $0.id == route.id }
            discovered.removeAll { $0.id == route.id }
            removeCachedCommunityRoute(id: route.id)
            return true
        } catch {
            errorMessage = String(
                localized: "route.library.remove_published.error",
                defaultValue: "Published route could not be removed. Try again."
            )
            return false
        }
    }

    @discardableResult
    func saveImported(_ route: PreparedRoute) -> Bool {
        guard route.source == .imported, route.isUsableForGuidance else {
            errorMessage = RouteImportError.invalid.localizedDescription
            return false
        }
        var updated = imported.filter { $0.id != route.id }
        updated.insert(route, at: 0)
        guard updated.count <= maximumImportedRoutes,
              updated.reduce(0, { $0 + $1.points.count }) <= maximumImportedPointCount
        else {
            errorMessage = RouteImportError.storageLimit.localizedDescription
            return false
        }
        guard persistImportedRoutes(updated) else { return false }
        imported = updated
        return true
    }

    func deleteImported(_ route: PreparedRoute) {
        let updated = imported.filter { $0.id != route.id }
        guard persistImportedRoutes(updated) else { return }
        imported = updated
    }

    func prepare(_ route: CommunityRoute) async -> PreparedRoute? {
        if let prepared = route.prepared {
            cacheCommunityRoute(prepared)
            return prepared
        }
        if let cached = cachedCommunityRoutes[route.id], cached.isUsableForGuidance {
            cacheCommunityRoute(cached)
            return cached
        }
        do {
            let detail = try await APIClient.shared.fetchCommunityRoute(id: route.id)
            guard let prepared = detail.prepared, prepared.isUsableForGuidance else {
                throw RouteImportError.invalid
            }
            cacheCommunityRoute(prepared)
            return prepared
        } catch {
            errorMessage = String(localized: "Route details could not be loaded. Try again while online.")
            return nil
        }
    }

    func cachedPreparedRoute(id: String) -> PreparedRoute? {
        guard let route = cachedCommunityRoutes[id] else { return nil }
        touchCachedCommunityRoute(id: id)
        persistCommunityRouteCacheOrder()
        return route
    }

    func launch(_ route: PreparedRoute) { pendingLaunch = route }
    func consumeLaunch() { pendingLaunch = nil }

    private func persistImportedRoutes(_ routes: [PreparedRoute]) -> Bool {
        do {
            let data = try JSONEncoder().encode(routes)
            try data.write(to: importedRoutesURL, options: .atomic)
            return true
        } catch {
            errorMessage = String(localized: "Imported routes could not be saved.")
            return false
        }
    }

    private func cacheCommunityRoute(_ route: PreparedRoute) {
        guard route.source == .community, route.isUsableForGuidance else { return }
        let geometryChanged = cachedCommunityRoutes[route.id] != route
        cachedCommunityRoutes[route.id] = route
        touchCachedCommunityRoute(id: route.id)
        let didEvict = trimCommunityRouteCacheToLimits()
        let retained = cachedCommunityRouteOrder.compactMap { cachedCommunityRoutes[$0] }
        cachedCommunityRoutes = Dictionary(uniqueKeysWithValues: retained.map { ($0.id, $0) })
        guard geometryChanged || didEvict else {
            persistCommunityRouteCacheOrder()
            return
        }
        do {
            try JSONEncoder().encode(retained).write(to: communityRouteCacheURL, options: .atomic)
            try JSONEncoder().encode(cachedCommunityRouteOrder)
                .write(to: communityRouteCacheOrderURL, options: .atomic)
        } catch {
            errorMessage = String(localized: "Route details could not be saved for offline use.")
        }
    }

    private func touchCachedCommunityRoute(id: String) {
        cachedCommunityRouteOrder.removeAll { $0 == id }
        cachedCommunityRouteOrder.append(id)
    }

    @discardableResult
    private func trimCommunityRouteCacheToLimits() -> Bool {
        var didEvict = false
        var pointCount = cachedCommunityRouteOrder.reduce(0) {
            $0 + (cachedCommunityRoutes[$1]?.points.count ?? 0)
        }
        while cachedCommunityRouteOrder.count > maximumCachedCommunityRoutes
            || pointCount > maximumCachedCommunityPointCount {
            guard let evictedID = cachedCommunityRouteOrder.first else { break }
            cachedCommunityRouteOrder.removeFirst()
            if let evicted = cachedCommunityRoutes.removeValue(forKey: evictedID) {
                pointCount -= evicted.points.count
            }
            didEvict = true
        }
        return didEvict
    }

    private func persistCommunityRouteCacheOrder() {
        do {
            try JSONEncoder().encode(cachedCommunityRouteOrder)
                .write(to: communityRouteCacheOrderURL, options: .atomic)
        } catch {
            errorMessage = String(localized: "Route details could not be saved for offline use.")
        }
    }

    private func removeCachedCommunityRoute(id: String) {
        cachedCommunityRoutes.removeValue(forKey: id)
        cachedCommunityRouteOrder.removeAll { $0 == id }
        let retained = cachedCommunityRouteOrder.compactMap { cachedCommunityRoutes[$0] }
        do {
            try JSONEncoder().encode(retained).write(to: communityRouteCacheURL, options: .atomic)
            try JSONEncoder().encode(cachedCommunityRouteOrder)
                .write(to: communityRouteCacheOrderURL, options: .atomic)
        } catch {
            errorMessage = String(localized: "Route details could not be saved for offline use.")
        }
    }
}

enum RouteImportError: LocalizedError {
    case unsupported
    case invalid
    case tooLarge
    case storageLimit
    var errorDescription: String? {
        switch self {
        case .unsupported: String(localized: "Choose a GPX or GeoJSON route file.")
        case .invalid: String(localized: "This file does not contain a valid route.")
        case .tooLarge: String(localized: "This route file is too large. Choose a file with no more than 50,000 points.")
        case .storageLimit:
            String(
                localized: "route.import.error.storage_limit",
                defaultValue: "Imported route storage is full. Delete a route and try again."
            )
        }
    }
}

enum RouteFileImporter {
    static let maximumFileBytes = 12 * 1_024 * 1_024
    static let maximumPointCount = 50_000

    static func parse(data: Data, filename: String) throws -> PreparedRoute {
        guard data.count <= maximumFileBytes else { throw RouteImportError.tooLarge }
        let ext = (filename as NSString).pathExtension.lowercased()
        let points: [RouteCoordinate]
        if ext == "gpx" { points = try GPXRouteParser.parse(data, maximumPointCount: maximumPointCount) }
        else if ext == "geojson" || ext == "json" { points = try geoJSONPoints(data) }
        else { throw RouteImportError.unsupported }
        guard points.count >= 2, points.count <= maximumPointCount else { throw RouteImportError.invalid }
        let route = PreparedRoute(id: UUID().uuidString, name: (filename as NSString).deletingPathExtension, points: points, source: .imported)
        guard route.isUsableForGuidance else { throw RouteImportError.invalid }
        return route
    }

    private static func geoJSONPoints(_ data: Data) throws -> [RouteCoordinate] {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let geometry = (object?["type"] as? String) == "Feature" ? object?["geometry"] as? [String: Any] : object
        guard geometry?["type"] as? String == "LineString", let coordinates = geometry?["coordinates"] as? [[Any]] else { throw RouteImportError.invalid }
        guard coordinates.count <= maximumPointCount else { throw RouteImportError.tooLarge }
        return try coordinates.map { value in
            guard value.count >= 2,
                  let longitude = finiteDouble(value[0]),
                  let latitude = finiteDouble(value[1]),
                  abs(latitude) <= 90,
                  abs(longitude) <= 180
            else { throw RouteImportError.invalid }
            let altitude = value.count > 2 ? finiteDouble(value[2]) : nil
            if value.count > 2, altitude == nil { throw RouteImportError.invalid }
            return RouteCoordinate(latitude: latitude, longitude: longitude, altitude: altitude)
        }
    }

    private static func finiteDouble(_ value: Any) -> Double? {
        let number: Double?
        if let value = value as? Double { number = value }
        else if let value = value as? NSNumber { number = value.doubleValue }
        else { number = nil }
        return number?.isFinite == true ? number : nil
    }
}

private final class GPXRouteParser: NSObject, XMLParserDelegate {
    private var points: [RouteCoordinate] = []
    private var pending: (Double, Double)?
    private var text = ""
    private var elevation: Double?
    private var maximumPointCount = 0
    private var exceededPointLimit = false
    private var invalidCoordinate = false

    static func parse(_ data: Data, maximumPointCount: Int) throws -> [RouteCoordinate] {
        let delegate = GPXRouteParser()
        delegate.maximumPointCount = maximumPointCount
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        let parsed = parser.parse()
        if delegate.exceededPointLimit { throw RouteImportError.tooLarge }
        guard parsed, !delegate.invalidCoordinate else { throw RouteImportError.invalid }
        return delegate.points
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        text = ""
        guard ["trkpt", "rtept"].contains(elementName) else { return }
        pending = nil
        elevation = nil
        guard let lat = attributeDict["lat"].flatMap(Double.init),
              let lon = attributeDict["lon"].flatMap(Double.init),
              lat.isFinite,
              lon.isFinite,
              abs(lat) <= 90,
              abs(lon) <= 180
        else {
            invalidCoordinate = true
            parser.abortParsing()
            return
        }
        pending = (lat, lon)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "ele" {
            let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
            elevation = value?.isFinite == true ? value : nil
        }
        if ["trkpt", "rtept"].contains(elementName), let pending {
            guard points.count < maximumPointCount else {
                exceededPointLimit = true
                parser.abortParsing()
                return
            }
            points.append(RouteCoordinate(latitude: pending.0, longitude: pending.1, altitude: elevation))
            self.pending = nil
        }
    }
}
