import CoreLocation
import HealthKit
import OSLog

/// The local journal survives an unavailable phone and process recovery. Apple
/// Health carries the completed route to iPhone independently of workout mirroring.
@MainActor
final class WatchRouteRecorder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let log = Logger(subsystem: "plainstride.outbound.watchkitapp", category: "route")
    private var journal: Journal?
    private var recording = false
    private var saving = false
    private var persistedPointCount = 0
    private var lastCheckpoint = Date.distantPast
    var permissionDenied: Bool { manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted }
    private let directory = URL.documentsDirectory.appending(path: "WorkoutRoutes", directoryHint: .isDirectory)

    private struct Point: Codable {
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let accuracy: Double
        let verticalAccuracy: Double
        let date: Date
        var location: CLLocation {
            CLLocation(coordinate: .init(latitude: latitude, longitude: longitude), altitude: altitude,
                       horizontalAccuracy: accuracy, verticalAccuracy: verticalAccuracy, timestamp: date)
        }
    }
    private struct Journal: Codable {
        let sessionID: UUID
        var healthSessionID: UUID? = nil
        var workoutID: UUID?
        var points: [Point]
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.allowsBackgroundLocationUpdates = true
    }

    func begin(sessionID: UUID, outdoor: Bool) {
        manager.stopUpdatingLocation()
        recording = false
        journal = nil
        persistedPointCount = 0
        guard outdoor else { return }
        let url = file(sessionID)
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                journal = try readJournal(at: url)
            } else {
                // Phone-first mirroring adopts the phone session UUID after GPS
                // starts. Locate the original journal through that durable alias.
                let files = FileManager.default.fileExists(atPath: directory.path)
                    ? try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) : []
                let alias = try files.filter { $0.pathExtension == "json" }.first { url in
                    try JSONDecoder().decode(Journal.self, from: Data(contentsOf: url)).healthSessionID == sessionID
                }
                journal = try alias.map { try readJournal(at: $0) } ?? Journal(sessionID: sessionID, points: [])
            }
        } catch {
            log.error("Route journal recovery failed code=\((error as NSError).code)")
            return // Never overwrite a journal that failed to decode.
        }
        persistedPointCount = journal?.points.count ?? 0
        lastCheckpoint = .distantPast
        recording = true
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func adoptWorkoutSessionID(_ id: UUID) {
        journal?.healthSessionID = id
        persist()
    }

    func pause() { recording = false; manager.stopUpdatingLocation(); persist() }
    func resume() {
        guard journal != nil else { return }
        recording = true
        manager.startUpdatingLocation()
    }
    func stop() { pause() }

    func finish(workout: HKWorkout, healthStore: HKHealthStore) async {
        stop()
        guard var value = journal else { return }
        value.workoutID = workout.uuid
        journal = value
        persist()
        await save(value, workout: workout, healthStore: healthStore)
    }

    func retryPending(healthStore: HKHealthStore) async {
        guard !saving else { return }
        do {
            guard FileManager.default.fileExists(atPath: directory.path) else { return }
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                let value = try readJournal(at: url)
                let predicate = value.workoutID.map { HKQuery.predicateForObject(with: $0) }
                    ?? HKQuery.predicateForObjects(withMetadataKey: "ai.plainstride.session_uuid", allowedValues: [(value.healthSessionID ?? value.sessionID).uuidString])
                let workout: HKWorkout? = try await withCheckedThrowingContinuation { continuation in
                    healthStore.execute(HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: samples?.first as? HKWorkout) }
                    })
                }
                if let workout { await save(value, workout: workout, healthStore: healthStore) }
            }
        } catch { log.error("Pending route retry failed code=\((error as NSError).code)") }
    }

    private func save(_ value: Journal, workout: HKWorkout, healthStore: HKHealthStore) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            if value.points.count > 1 {
                // A previous finish may have succeeded just before termination.
                let exists: Bool = try await withCheckedThrowingContinuation { continuation in
                    healthStore.execute(HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout), limit: 1, sortDescriptors: nil) { _, samples, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: !(samples ?? []).isEmpty) }
                    })
                }
                if !exists {
                    let route = HKWorkoutRouteBuilder(healthStore: healthStore, device: .local())
                    try await route.insertRouteData(value.points.map(\.location))
                    _ = try await route.finishRoute(with: workout, metadata: nil)
                }
            }
            let pointsURL = pointFile(value.sessionID)
            if FileManager.default.fileExists(atPath: pointsURL.path) { try FileManager.default.removeItem(at: pointsURL) }
            try FileManager.default.removeItem(at: file(value.sessionID))
            if journal?.sessionID == value.sessionID { journal = nil }
        } catch {
            log.error("Route Health save failed code=\((error as NSError).code)")
            // Retain the durable journal and retry on the next launch.
        }
    }

    private func file(_ id: UUID) -> URL { directory.appending(path: id.uuidString + ".json") }
    private func pointFile(_ id: UUID) -> URL { directory.appending(path: id.uuidString + ".points") }

    private func readJournal(at url: URL) throws -> Journal {
        var value = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: url))
        let pointsURL = pointFile(value.sessionID)
        if FileManager.default.fileExists(atPath: pointsURL.path) {
            let data = try Data(contentsOf: pointsURL)
            // An interrupted append can leave a partial last line. Only complete
            // records are durable; trim the tail before the next append.
            let end = data.lastIndex(of: 10).map { $0 + 1 } ?? 0
            for line in data.prefix(end).split(separator: 10) {
                let point = try JSONDecoder().decode(Point.self, from: Data(line))
                if value.points.last.map({ point.date > $0.date }) ?? true { value.points.append(point) }
            }
            if end < data.count {
                let handle = try FileHandle(forWritingTo: pointsURL)
                defer { try? handle.close() } // Close failure cannot affect already read route data.
                try handle.truncate(atOffset: UInt64(end))
            }
        }
        return value
    }

    private func persist() {
        guard let journal else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Keep metadata small; append only new points instead of rewriting a
            // growing route every ten seconds during a long run.
            var header = journal
            header.points = []
            try JSONEncoder().encode(header).write(to: file(journal.sessionID), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            guard journal.points.count > persistedPointCount else { return }
            let url = pointFile(journal.sessionID)
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() } // synchronize below is the durability boundary.
            let offset = try handle.seekToEnd()
            do {
                var batch = Data()
                for point in journal.points.dropFirst(persistedPointCount) {
                    batch.append(try JSONEncoder().encode(point))
                    batch.append(10)
                }
                try handle.write(contentsOf: batch)
                try handle.synchronize()
                persistedPointCount = journal.points.count
            } catch {
                // Avoid duplicate/partial records if this process retries the append.
                do { try handle.truncate(atOffset: offset) }
                catch { log.error("Route append rollback failed code=\((error as NSError).code)") }
                throw error
            }
        } catch { log.error("Route checkpoint failed code=\((error as NSError).code)") }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard recording, journal != nil else { return }
            for point in locations where point.horizontalAccuracy >= 0 && point.horizontalAccuracy <= 50 && abs(point.timestamp.timeIntervalSinceNow) < 30 {
                guard journal?.points.last.map({ point.timestamp > $0.date }) ?? true else { continue }
                journal?.points.append(Point(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude,
                    altitude: point.altitude, accuracy: point.horizontalAccuracy, verticalAccuracy: point.verticalAccuracy, date: point.timestamp))
            }
            if Date().timeIntervalSince(lastCheckpoint) >= 10 {
                persist()
                lastCheckpoint = Date()
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A temporary lack of a GPS fix is expected; the next fix continues the route.
        guard (error as? CLError)?.code != .locationUnknown else { return }
        let code = (error as NSError).code
        Task { @MainActor in log.error("Watch GPS failed code=\(code)") }
    }
}
