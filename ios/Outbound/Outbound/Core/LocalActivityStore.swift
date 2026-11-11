import CoreLocation
import Foundation
import UIKit

actor ActivityPersistence {
    static let shared = ActivityPersistence()

    nonisolated static func imageURL(for photo: SavedPhoto) -> URL {
        LocalActivityStore.imageURL(for: photo)
    }

    func save(
        summary: ActivitySummary,
        photos: [(UIImage, PhotoMetadata)],
        activityType: ActivityType,
        title: String,
        guideNudge: String,
        reflection: FinishReflection?,
        goal: ActivityGoal?,
        energyKilocalories: Int?,
        source: ActivitySourceMetadata,
        gear: ActivityGearAttachment?,
        manualEdits: ActivityManualEdits?,
        indoor: ActivityIndoorMetadata?,
        cadence: ActivityCadenceSummary?,
        heartRateZones: ActivityHeartRateZoneSummary?,
        recordingSession: ActivityRecordingSessionMetadata?,
        activityEventID: String?,
        followedRoute: FollowedRouteMetadata?,
        recognitionBadgeIDs: [RecognitionBadgeID],
        companionType: ActivityCompanionType?,
        sessionEffortRating: Int? = nil,
        performedWorkoutReference: PerformedWorkoutReference? = nil,
        plannedWorkoutCompletionQuality: String? = nil
    ) throws -> SavedActivity {
        try LocalActivityStore.save(
            summary: summary,
            photos: photos,
            activityType: activityType,
            title: title,
            guideNudge: guideNudge,
            reflection: reflection,
            goal: goal,
            energyKilocalories: energyKilocalories,
            source: source,
            gear: gear,
            manualEdits: manualEdits,
            indoor: indoor,
            cadence: cadence,
            heartRateZones: heartRateZones,
            recordingSession: recordingSession,
            activityEventID: activityEventID,
            followedRoute: followedRoute,
            recognitionBadgeIDs: recognitionBadgeIDs,
            companionType: companionType,
            sessionEffortRating: sessionEffortRating, performedWorkoutReference: performedWorkoutReference, plannedWorkoutCompletionQuality: plannedWorkoutCompletionQuality
        )
    }

    #if DEBUG
    func failNextPlanningWriteForRepositoryFixture() {
        guard ProcessInfo.processInfo.arguments.contains("-OutboundDebugActivityRepository") else { return }
        LocalActivityStore.failNextPlanningFixtureWrite = true
    }
    func failNextWriteForRepositoryFixture() {
        guard ProcessInfo.processInfo.arguments.contains("-OutboundDebugActivityRepository") else { return }
        LocalActivityStore.failNextFixtureWrite = true
    }
    #endif

    func snapshot() throws -> ActivityRepositorySnapshot {
        try ActivityRepositorySnapshot(activities: LocalActivityStore.load().sorted { $0.startedAt > $1.startedAt }, projection: LocalActivityStore.projection())
    }

    func reject(_ id: UUID, generation: UInt64, category: String) throws {
        try LocalActivityStore.reject(id, generation: generation, category: category)
    }

    func retryRejected() throws { try LocalActivityStore.retryRejected() }
    func invalidateReadModels() throws { try LocalActivityStore.invalidateReadModels() }
    func statisticsSnapshot() throws -> Data? { try LocalActivityStore.statisticsSnapshot() }
    func storeStatisticsSnapshot(_ data: Data, revision: Int, ticket: UInt64) throws -> Bool {
        try LocalActivityStore.storeStatisticsSnapshot(data, revision: revision, ticket: ticket)
    }
    func planningSnapshot() throws -> Data? { try LocalActivityStore.planningSnapshot() }
    @discardableResult
    func storePlanningSnapshot(_ data: Data, revision: Int?, invalidateStatistics: Bool = false) throws -> ActivityReadModelSnapshot {
        try LocalActivityStore.storePlanningSnapshot(data, revision: revision, invalidateStatistics: invalidateStatistics)
    }
    func statisticsReadTicket() throws -> UInt64 { try LocalActivityStore.statisticsReadTicket() }

    func retainAcceptance(_ receipt: ActivityReconciliationReceipt) throws {
        try LocalActivityStore.retainAcceptance(receipt)
    }

    func projection() throws -> ActivityRepositoryProjection {
        try LocalActivityStore.projection()
    }

    func uploadSnapshot(for id: UUID) throws -> ActivityUploadSnapshot? { try LocalActivityStore.uploadSnapshot(for: id) }
    func updateSyncState(_ state: SavedActivitySyncState, for id: UUID, expectedGeneration: UInt64) throws {
        try LocalActivityStore.updateSyncState(state, for: id, expectedGeneration: expectedGeneration)
    }
    func applyRemoteBaseline(_ activity: SavedActivity, expectedGeneration: UInt64?) throws -> Bool {
        try LocalActivityStore.applyRemoteBaseline(activity, expectedGeneration: expectedGeneration)
    }
    func mergePhotoMetadata(_ photos: [SavedPhoto], for id: UUID, appendIfGeneration: UInt64? = nil) throws {
        try LocalActivityStore.mergePhotoMetadata(photos, for: id, appendIfGeneration: appendIfGeneration)
    }
    func generation(for id: UUID) throws -> UInt64? {
        try LocalActivityStore.generation(for: id)
    }

    func acknowledge(_ activity: SavedActivity, generation: UInt64, receipt: ActivityReconciliationReceipt) throws -> SavedActivity? {
        try LocalActivityStore.acknowledge(activity, generation: generation, receipt: receipt)
    }

    func finishReconciliation(planning: Int?, statistics: Int?, statisticsTicket: UInt64?) throws {
        try LocalActivityStore.finishReconciliation(planning: planning, statistics: statistics, statisticsTicket: statisticsTicket)
    }

    func adoptCanonical(_ canonical: SavedActivity, replacing source: SavedActivity, generation: UInt64, canonicalGeneration: UInt64?, receipt: ActivityReconciliationReceipt) throws -> SavedActivity? {
        try LocalActivityStore.adoptCanonical(canonical, replacing: source, generation: generation, canonicalGeneration: canonicalGeneration, receipt: receipt)
    }

    func verifiedLegacyActivity(serverID: String, clientID: UUID) throws -> SavedActivity? {
        try LocalActivityStore.verifiedLegacyActivity(serverID: serverID, clientID: clientID)
    }

    func copyPhotos(_ photos: [SavedPhoto], into activityID: UUID) throws -> [SavedPhoto] {
        try LocalActivityStore.copyPhotos(photos, into: activityID)
    }

    func load() throws -> [SavedActivity] {
        try LocalActivityStore.load()
    }

    func delete(_ activity: SavedActivity) throws {
        try LocalActivityStore.delete(activity)
    }

    func preserveOriginalElevationRoute(_ route: SavedRoute, for activityID: UUID) throws {
        try LocalActivityStore.preserveOriginalElevationRoute(route, for: activityID)
    }

    func replace(_ activity: SavedActivity, mutation: Bool = true) throws {
        try LocalActivityStore.replace(activity, mutation: mutation)
    }

    func replaceOrInsert(_ activity: SavedActivity) throws {
        try LocalActivityStore.replaceOrInsert(activity)
    }

    func deleteAll() throws {
        try LocalActivityStore.deleteAll()
    }

    func exportRoute(for activity: SavedActivity, format: RouteExportFormat) throws -> URL {
        try RouteFileExporter.export(activity: activity, format: format)
    }

    func uploadData(for photo: SavedPhoto) throws -> Data {
        try LocalActivityStore.uploadData(for: photo)
    }

    func saveDownloadedPhoto(_ data: Data, remote: RemoteActivityPhoto, activityID: UUID) throws -> SavedPhoto {
        try LocalActivityStore.saveDownloadedPhoto(data, remote: remote, activityID: activityID)
    }

    func updatePhotos(
        for activity: SavedActivity,
        keeping photos: [SavedPhoto],
        adding captures: [(UIImage, PhotoMetadata)],
        photoOrder: [Int]? = nil
    ) throws -> SavedActivity {
        try LocalActivityStore.updatePhotos(for: activity, keeping: photos, adding: captures, photoOrder: photoOrder)
    }
}

private nonisolated enum LocalActivityStore {
    private static let manifestFileName = "activities.json"
    #if DEBUG
    nonisolated(unsafe) static var failNextFixtureWrite = false
    nonisolated(unsafe) static var failNextPlanningFixtureWrite = false
    #endif

    @discardableResult
    static func save(
        summary: ActivitySummary,
        photos: [(UIImage, PhotoMetadata)],
        activityType: ActivityType = .running,
        title: String,
        guideNudge: String,
        reflection: FinishReflection?,
        goal: ActivityGoal?,
        energyKilocalories: Int? = nil,
        source: ActivitySourceMetadata = .outboundRecorded,
        gear: ActivityGearAttachment? = nil,
        manualEdits: ActivityManualEdits? = nil,
        indoor: ActivityIndoorMetadata? = nil,
        cadence: ActivityCadenceSummary? = nil,
        heartRateZones: ActivityHeartRateZoneSummary? = nil,
        recordingSession: ActivityRecordingSessionMetadata? = nil,
        activityEventID: String? = nil,
        followedRoute: FollowedRouteMetadata? = nil,
        recognitionBadgeIDs: [RecognitionBadgeID] = [],
        companionType: ActivityCompanionType? = nil,
        sessionEffortRating: Int? = nil,
        performedWorkoutReference: PerformedWorkoutReference? = nil,
        plannedWorkoutCompletionQuality: String? = nil
    ) throws -> SavedActivity {
        let activityId = UUID()
        let activityDirectory = try directory(for: activityId)
        let photoDirectory = activityDirectory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)

        let savedPhotos = try photos.enumerated().compactMap { index, capture -> SavedPhoto? in
            let fileName = String(format: "photo-%02d.jpg", index + 1)
            let photoURL = photoDirectory.appendingPathComponent(fileName)
            guard let data = capture.0.jpegData(compressionQuality: 0.9) else { return nil }
            try data.write(to: photoURL, options: .atomic)
            return SavedPhoto(metadata: capture.1, relativePath: "\(activityId.uuidString)/photos/\(fileName)")
        }

        let route = SavedRoute(
            points: SavedRoutePoint.simplified(from: summary.trackSegments),
            elevationMetadata: summary.elevationMetadata
        )
        if let original = summary.originalElevationRoute
            ?? (summary.elevationMetadata == nil ? SavedRoute.original(from: summary.trackSegments) : nil) {
            try preserveOriginalElevationRoute(original, for: activityId)
        }
        try saveRoute(route, for: activityId)

        let activity = SavedActivity(
            id: activityId,
            activityType: activityType,
            title: title,
            guideNudge: guideNudge,
            reflection: reflection,
            sessionEffortRating: sessionEffortRating, performedWorkoutReference: performedWorkoutReference, plannedWorkoutCompletionQuality: plannedWorkoutCompletionQuality,
            createdAt: Date(),
            startedAt: summary.startedAt,
            endedAt: summary.endedAt,
            durationSecs: summary.durationSecs,
            distanceM: summary.distanceM,
            avgPace: activityType.plausibleAveragePace(
                durationSeconds: Double(summary.durationSecs),
                distanceMeters: summary.distanceM
            ),
            elevationGainM: summary.elevationGainM,
            walkingStepCount: summary.walkingStepCount,
            healthMetrics: summary.healthMetrics,
            goal: goal,
            energyKilocalories: energyKilocalories,
            companionType: companionType,
            source: source,
            gear: gear,
            manualEdits: manualEdits,
            indoor: indoor,
            cadence: cadence ?? summary.cadence,
            heartRateZones: heartRateZones,
            recordingSession: recordingSession,
            activityEventID: activityEventID,
            followedRoute: followedRoute,
            recognitionBadgeIDs: recognitionBadgeIDs,
            route: route,
            photos: savedPhotos,
            sync: SavedActivitySyncState(
                clientActivityId: activityId.uuidString,
                serverActivityId: nil,
                lastAttemptAt: nil,
                syncedAt: nil,
                lastError: nil,
                localUpdatedAt: Date()
            )
        )

        var activities = try load()
        activities.insert(activity, at: 0)
        try saveManifest(activities)
        return activity
    }

    static func copyPhotos(_ photos: [SavedPhoto], into activityID: UUID) throws -> [SavedPhoto] {
        let target = try directory(for: activityID).appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return try photos.map { photo in
            let fileName = "reconciled-\(photo.id.uuidString).jpg"
            let sourceURL = imageURL(for: photo)
            let destination = target.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: sourceURL, to: destination) }
            } else if photo.remotePhotoId == nil {
                throw CocoaError(.fileNoSuchFile)
            }
            return SavedPhoto(id: photo.id, takenAt: photo.takenAt, paceAtShot: photo.paceAtShot, hrAtShot: photo.hrAtShot, distAtShot: photo.distAtShot,
                              coordinate: photo.coordinate, captureContext: photo.captureContext, relativePath: "\(activityID.uuidString)/photos/\(fileName)",
                              remotePhotoId: photo.remotePhotoId, remoteUploadedAt: photo.remoteUploadedAt, remoteThumbnailURL: photo.remoteThumbnailURL, isImported: photo.isImported)
        }
    }

    static func load() throws -> [SavedActivity] {
        try ActivityAccountBoundary.validate()
        let manifestActivities = try readManifest().records
            .filter { $0.owner == ActivityAccountBoundary.context.owner }.map(\.activity)
        return try manifestActivities.map { activity in
            guard activity.route == nil else {
                try? saveRoute(activity.route!, for: activity.id)
                return activity.withRoute(try loadRoute(for: activity.id))
            }
            return activity.withRoute(try loadRoute(for: activity.id))
        }
    }

    static func delete(_ activity: SavedActivity) throws {
        var activities = try load()
        activities.removeAll { $0.id == activity.id }
        try saveManifest(activities)
        removeMediaIfUnreferenced(activity.id, manifest: try readManifest())
    }

    static func replace(_ activity: SavedActivity, mutation: Bool = true) throws {
        var manifest = try readManifest()
        guard let index = manifest.records.firstIndex(where: { $0.owner == ActivityAccountBoundary.context.owner && $0.activity.id == activity.id }) else { return }
        let nextGeneration = manifest.records[index].generation + (mutation ? 1 : 0)
        let journal = mutation ? try prepareCanonicalJournal(sourceID: activity.id, targetID: activity.id, generation: nextGeneration) : nil
        if mutation { try saveRoute(activity.route, for: activity.id) }
        manifest.records[index].activity = activity.withRoute(nil)
        manifest.records[index].generation = nextGeneration
        if mutation { manifest.records[index].rejection = nil }
        try writeManifest(manifest)
        if let journal { try FileManager.default.removeItem(at: journal) }
    }

    static func updatePhotos(
        for activity: SavedActivity,
        keeping photos: [SavedPhoto],
        adding captures: [(UIImage, PhotoMetadata)],
        photoOrder: [Int]? = nil
    ) throws -> SavedActivity {
        let baselineIDs = Set(activity.photos.map(\.id))
        guard let current = try load().first(where: { $0.id == activity.id }) else { throw CocoaError(.fileNoSuchFile) }
        let currentByID = Dictionary(current.photos.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let concurrent = current.photos.filter { candidate in !baselineIDs.contains(candidate.id) && !photos.contains(where: { $0.id == candidate.id }) }
        let photos = photos.map { currentByID[$0.id] ?? $0 }
        let activity = current
        let photoDirectory = try directory(for: activity.id).appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
        let addedPhotos = try captures.compactMap { capture -> SavedPhoto? in
            let id = UUID()
            let fileName = "photo-\(id.uuidString).jpg"
            guard let data = capture.0.jpegData(compressionQuality: 0.9) else { return nil }
            try data.write(to: photoDirectory.appendingPathComponent(fileName), options: .atomic)
            return SavedPhoto(
                id: id,
                takenAt: capture.1.takenAt,
                paceAtShot: capture.1.paceAtShot,
                hrAtShot: capture.1.hrAtShot,
                distAtShot: capture.1.distAtShot,
                coordinate: capture.1.coordinate.map { SavedCoordinate(coordinate: $0) },
                captureContext: capture.1.captureContext,
                relativePath: "\(activity.id.uuidString)/photos/\(fileName)",
                remotePhotoId: nil,
                remoteUploadedAt: nil,
                isImported: capture.1.isImported
            )
        }
        let combinedPhotos = photos + addedPhotos
        let orderedPhotos: [SavedPhoto]
        if let photoOrder {
            guard photoOrder.count == combinedPhotos.count,
                  Set(photoOrder) == Set(combinedPhotos.indices) else {
                throw CocoaError(.fileWriteUnknown)
            }
            orderedPhotos = photoOrder.map { combinedPhotos[$0] }
        } else {
            orderedPhotos = combinedPhotos
        }
        let updated = SavedActivity(
            id: activity.id,
            activityType: activity.activityType,
            title: activity.title,
            guideNudge: activity.guideNudge,
            reflection: activity.reflection,
            sessionEffortRating: activity.sessionEffortRating, performedWorkoutReference: activity.performedWorkoutReference, plannedWorkoutCompletionQuality: activity.plannedWorkoutCompletionQuality,
            createdAt: activity.createdAt,
            startedAt: activity.startedAt,
            endedAt: activity.endedAt,
            durationSecs: activity.durationSecs,
            distanceM: activity.distanceM,
            avgPace: activity.avgPace,
            elevationGainM: activity.elevationGainM,
            walkingStepCount: activity.walkingStepCount,
            healthMetrics: activity.healthMetrics,
            goal: activity.goal,
            companionType: activity.companionType,
            source: activity.source,
            gear: activity.gear,
            manualEdits: activity.manualEdits,
            indoor: activity.indoor,
            cadence: activity.cadence,
            heartRateZones: activity.heartRateZones,
            recordingSession: activity.recordingSession,
            activityEventID: activity.activityEventID,
            followedRoute: activity.followedRoute,
            recognitionBadgeIDs: activity.recognitionBadgeIDs,
            route: activity.route,
            photos: orderedPhotos + concurrent,
            sync: SavedActivitySyncState(
                clientActivityId: activity.sync?.clientActivityId ?? activity.id.uuidString,
                serverActivityId: activity.sync?.serverActivityId,
                lastAttemptAt: activity.sync?.lastAttemptAt,
                syncedAt: nil,
                lastError: nil,
                localUpdatedAt: Date()
            )
        )
        try replace(updated)
        return updated
    }

    static func replaceOrInsert(_ activity: SavedActivity) throws {
        var manifest = try readManifest()
        let owner = ActivityAccountBoundary.context.owner
        let index = manifest.records.firstIndex { $0.owner == owner && $0.activity.id == activity.id }
        let generation = (index.map { manifest.records[$0].generation } ?? 0) + 1
        let journal = try prepareCanonicalJournal(sourceID: activity.id, targetID: activity.id, generation: generation)
        try saveRoute(activity.route, for: activity.id)
        let record = ActivityRepositoryRecord(owner: owner, generation: generation, activity: activity.withRoute(nil))
        if let index { manifest.records[index] = record } else { manifest.records.append(record) }
        try writeManifest(manifest)
        try FileManager.default.removeItem(at: journal)
    }

    static func deleteAll() throws {
        try ActivityAccountBoundary.validate()
        let owner = ActivityAccountBoundary.context.owner
        var manifest = try readManifest()
        let removed = manifest.records.filter { $0.owner == owner }.map(\.activity)
        manifest.records.removeAll { $0.owner == owner }
        manifest.reconciliation.removeValue(forKey: owner)
        manifest.confirmedCompletions.removeValue(forKey: owner)
        manifest.readInvalidationGenerations?.removeValue(forKey: owner)
        manifest.planningSnapshots?.removeValue(forKey: owner)
        manifest.statisticsSnapshots?.removeValue(forKey: owner)
        try writeManifest(manifest)
        for activity in removed { removeMediaIfUnreferenced(activity.id, manifest: manifest) }
    }

    static func imageURL(for photo: SavedPhoto) -> URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("Outbound/Activities", isDirectory: true)
            .appendingPathComponent(photo.relativePath)
    }

    static func uploadData(for photo: SavedPhoto) throws -> Data {
        let data = try Data(contentsOf: imageURL(for: photo))
        let maximumBytes = 5 * 1024 * 1024
        if data.count <= maximumBytes { return data }
        guard let image = UIImage(data: data) else { throw ActivityPhotoPersistenceError.invalidImage }
        for quality in [0.75, 0.6, 0.45, 0.3] {
            if let compressed = image.jpegData(compressionQuality: quality), compressed.count <= maximumBytes {
                return compressed
            }
        }
        throw ActivityPhotoPersistenceError.imageTooLarge
    }

    static func saveDownloadedPhoto(_ data: Data, remote: RemoteActivityPhoto, activityID: UUID) throws -> SavedPhoto {
        guard !data.isEmpty, UIImage(data: data) != nil else { throw ActivityPhotoPersistenceError.invalidImage }
        let photoDirectory = try directory(for: activityID).appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
        let fileName = "photo-\(remote.clientPhotoId).jpg"
        try data.write(to: photoDirectory.appendingPathComponent(fileName), options: .atomic)
        return SavedPhoto(
            id: UUID(uuidString: remote.clientPhotoId) ?? UUID(),
            takenAt: remote.takenAt,
            paceAtShot: remote.paceAtShot,
            hrAtShot: remote.hrAtShot,
            distAtShot: remote.distAtShot ?? 0,
            coordinate: remote.latitude.flatMap { latitude in
                remote.longitude.map { SavedCoordinate(latitude: latitude, longitude: $0) }
            },
            captureContext: remote.captureContext.flatMap(PhotoCaptureContext.init(rawValue:)) ?? .active,
            relativePath: "\(activityID.uuidString)/photos/\(fileName)",
            remotePhotoId: remote.id,
            remoteUploadedAt: remote.updatedAt,
            remoteThumbnailURL: remote.thumbnailUrl?.absoluteString
        )
    }

    private static let routeFileName = "route.bin"
    private static let routeMetadataFileName = "route.meta.json"

    // Local-only source data: never sync/share it or replace it with corrected terrain.
    static func preserveOriginalElevationRoute(_ route: SavedRoute, for activityID: UUID) throws {
        guard route.points.count >= 2 else { return }
        let url = try directory(for: activityID).appendingPathComponent("route.original.bin")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try RouteSidecarCodec.encode(route.points).write(to: url, options: .atomic)
    }

    private static func saveRoute(_ route: SavedRoute?, for activityID: UUID) throws {
        let directory = try self.directory(for: activityID)
        let url = directory.appendingPathComponent(routeFileName)
        let metadataURL = directory.appendingPathComponent(routeMetadataFileName)
        guard let route, route.points.count >= 2 else {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: metadataURL)
            return
        }
        let encodedRoute = RouteSidecarCodec.encode(route.points)
        if (try? Data(contentsOf: url)) != encodedRoute {
            try encodedRoute.write(to: url, options: .atomic)
        }
        let metadata = try JSONEncoder().encode(route.elevationMetadata)
        if (try? Data(contentsOf: metadataURL)) != metadata {
            try metadata.write(to: metadataURL, options: .atomic)
        }
    }

    private static func loadRoute(for activityID: UUID) throws -> SavedRoute? {
        let directory = try activitiesDirectory().appendingPathComponent(activityID.uuidString)
        let url = directory.appendingPathComponent(routeFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let points = try RouteSidecarCodec.decode(data)
        let metadataURL = directory.appendingPathComponent(routeMetadataFileName)
        let metadata = FileManager.default.fileExists(atPath: metadataURL.path)
            ? try JSONDecoder().decode(ActivityElevationMetadata?.self, from: Data(contentsOf: metadataURL))
            : nil
        return SavedRoute(points: points, elevationMetadata: metadata)
    }

    private static func readManifest() throws -> ActivityRepositoryManifest {
        try ActivityAccountBoundary.validate()
        try recoverCanonicalJournals()
        return try readManifestWithoutRecovery()
    }

    private static func readManifestWithoutRecovery() throws -> ActivityRepositoryManifest {
        let url = try manifestURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let data = try Data(contentsOf: url)
        if let manifest = try? decoder.decode(ActivityRepositoryManifest.self, from: data) { return manifest }
        // Ownership cannot be reconstructed from a global file. Retain originals until the
        // authenticated server verifies a matching canonical identity; never claim guest work.
        let legacy = try decoder.decode([SavedActivity].self, from: data)
        return ActivityRepositoryManifest(records: legacy.map { .init(owner: "legacy-unverified", generation: 1, activity: $0) })
    }

    private struct CanonicalJournal: Codable {
        let owner: String
        let sourceID: UUID
        let targetID: UUID
        let generation: UInt64
        let before: [String: Data]
    }
    private static let canonicalSidecars = ["route.bin", "route.meta.json", "route.original.bin"]

    private static func prepareCanonicalJournal(sourceID: UUID, targetID: UUID, generation: UInt64) throws -> URL {
        var before: [String: Data] = [:]
        let target = try directory(for: targetID)
        for name in canonicalSidecars {
            let url = target.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { before[name] = try Data(contentsOf: url) }
        }
        let journal = CanonicalJournal(owner: ActivityAccountBoundary.context.owner, sourceID: sourceID, targetID: targetID, generation: generation, before: before)
        let url = try activitiesDirectory().appendingPathComponent("canonical-journal-\(UUID().uuidString).json")
        try encoder.encode(journal).write(to: url, options: .atomic)
        return url
    }

    private static func recoverCanonicalJournals() throws {
        let root = try activitiesDirectory()
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) where url.lastPathComponent.hasPrefix("canonical-journal-") {
            let journal = try decoder.decode(CanonicalJournal.self, from: Data(contentsOf: url))
            let manifest = try readManifestWithoutRecovery()
            let target = manifest.records.first { $0.owner == journal.owner && $0.activity.id == journal.targetID }
            let committed = target?.generation == journal.generation && (journal.sourceID == journal.targetID || !manifest.records.contains { $0.owner == journal.owner && $0.activity.id == journal.sourceID })
            if !committed {
                let directory = try self.directory(for: journal.targetID)
                for name in canonicalSidecars {
                    let file = directory.appendingPathComponent(name)
                    if let data = journal.before[name] { try data.write(to: file, options: .atomic) }
                    else if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                }
            }
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func writeManifest(_ manifest: ActivityRepositoryManifest) throws {
        try ActivityAccountBoundary.validate()
        try Task.checkCancellation()
        #if DEBUG
        if failNextFixtureWrite {
            failNextFixtureWrite = false
            throw CocoaError(.fileWriteOutOfSpace)
        }
        #endif
        try encoder.encode(manifest).write(to: try manifestURL(), options: .atomic)
    }

    private static func saveManifest(_ activities: [SavedActivity], mutatedIDs: Set<UUID> = []) throws {
        try ActivityAccountBoundary.validate()
        let owner = ActivityAccountBoundary.context.owner
        var manifest = try readManifest()
        let old = Dictionary(uniqueKeysWithValues: manifest.records.filter { $0.owner == owner }.map { ($0.activity.id, $0) })
        manifest.records.removeAll { $0.owner == owner }
        manifest.records += activities.map { activity in
            let prior = old[activity.id]
            let changed = mutatedIDs.contains(activity.id)
            return ActivityRepositoryRecord(owner: owner, generation: (prior?.generation ?? 0) + (prior == nil || changed ? 1 : 0), activity: activity, rejection: changed ? nil : prior?.rejection)
        }
        try writeManifest(manifest)
    }

    static func projection() throws -> ActivityRepositoryProjection {
        try ActivityAccountBoundary.validate()
        let manifest = try readManifest(), owner = ActivityAccountBoundary.context.owner
        let pending = manifest.records.filter { $0.owner == owner && $0.activity.sync?.isSynced != true && $0.rejection == nil }
            .compactMap { $0.activity.performedWorkoutReference?.plannedWorkoutId }
        let rejected = manifest.records.filter { $0.owner == owner && $0.rejection != nil }
        return .init(pendingWorkoutIDs: Set(pending), conflictedWorkoutIDs: Set(rejected.compactMap { $0.activity.performedWorkoutReference?.plannedWorkoutId }),
            blockedActivityIDs: Set(rejected.map { $0.activity.id }), confirmedCompletions: manifest.confirmedCompletions[owner] ?? [], reconciliation: manifest.reconciliation[owner])
    }

    static func reject(_ id: UUID, generation: UInt64, category: String) throws {
        try ActivityAccountBoundary.validate()
        var manifest = try readManifest()
        guard let index = manifest.records.firstIndex(where: { $0.owner == ActivityAccountBoundary.context.owner && $0.activity.id == id }),
              manifest.records[index].generation == generation else { return }
        manifest.records[index].rejection = category
        try writeManifest(manifest)
    }

    static func retryRejected() throws {
        try ActivityAccountBoundary.validate()
        var manifest = try readManifest()
        for index in manifest.records.indices where manifest.records[index].owner == ActivityAccountBoundary.context.owner {
            manifest.records[index].rejection = nil
        }
        try writeManifest(manifest)
    }

    static func uploadSnapshot(for id: UUID) throws -> ActivityUploadSnapshot? {
        try ActivityAccountBoundary.validate()
        guard let record = try readManifest().records.first(where: { $0.owner == ActivityAccountBoundary.context.owner && $0.activity.id == id }) else { return nil }
        return .init(activity: record.activity.withRoute(try loadRoute(for: id)), generation: record.generation)
    }

    static func updateSyncState(_ state: SavedActivitySyncState, for id: UUID, expectedGeneration: UInt64) throws {
        var manifest = try readManifest()
        guard let index = manifest.records.firstIndex(where: { $0.owner == ActivityAccountBoundary.context.owner && $0.activity.id == id }),
              manifest.records[index].generation == expectedGeneration else { return }
        manifest.records[index].activity = manifest.records[index].activity.withSync(state)
        try writeManifest(manifest)
    }

    static func applyRemoteBaseline(_ activity: SavedActivity, expectedGeneration: UInt64?) throws -> Bool {
        var manifest = try readManifest()
        let owner = ActivityAccountBoundary.context.owner
        let index = manifest.records.firstIndex { $0.owner == owner && $0.activity.id == activity.id }
        if let index {
            guard manifest.records[index].generation == expectedGeneration,
                  manifest.records[index].activity.sync?.isSynced == true else { return false }
        } else if expectedGeneration != nil { return false }
        // Route preparation is journaled too: a remote baseline must not corrupt a
        // still-referenced sidecar if its manifest publication fails.
        let journal = try prepareCanonicalJournal(sourceID: activity.id, targetID: activity.id, generation: (index.map { manifest.records[$0].generation } ?? 0) + 1)
        try saveRoute(activity.route, for: activity.id)
        let baseline = index.map { activity.withPhotos(manifest.records[$0].activity.photos) } ?? activity
        let record = ActivityRepositoryRecord(owner: owner, generation: (index.map { manifest.records[$0].generation } ?? 0) + 1, activity: baseline.withRoute(nil))
        if let index { manifest.records[index] = record } else { manifest.records.append(record) }
        try writeManifest(manifest)
        try FileManager.default.removeItem(at: journal)
        return true
    }

    static func mergePhotoMetadata(_ photos: [SavedPhoto], for id: UUID, appendIfGeneration: UInt64?) throws {
        var manifest = try readManifest()
        guard let index = manifest.records.firstIndex(where: { $0.owner == ActivityAccountBoundary.context.owner && $0.activity.id == id }) else { return }
        let current = manifest.records[index].activity
        let incoming = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        var merged = current.photos.map { photo -> SavedPhoto in
            guard let remote = incoming[photo.id] else { return photo }
            return SavedPhoto(id: photo.id, takenAt: photo.takenAt, paceAtShot: photo.paceAtShot, hrAtShot: photo.hrAtShot,
                distAtShot: photo.distAtShot, coordinate: photo.coordinate, captureContext: photo.captureContext,
                relativePath: photo.relativePath, remotePhotoId: remote.remotePhotoId ?? photo.remotePhotoId,
                remoteUploadedAt: remote.remoteUploadedAt ?? photo.remoteUploadedAt,
                remoteThumbnailURL: remote.remoteThumbnailURL ?? photo.remoteThumbnailURL, isImported: photo.isImported)
        }
        if appendIfGeneration == manifest.records[index].generation {
            merged += photos.filter { candidate in !merged.contains(where: { $0.id == candidate.id }) }.sorted { $0.takenAt < $1.takenAt }
        }
        manifest.records[index].activity = current.withPhotos(merged)
        try writeManifest(manifest)
    }

    static func generation(for id: UUID) throws -> UInt64? {
        try ActivityAccountBoundary.validate()
        return try readManifest().records.first { $0.owner == ActivityAccountBoundary.context.owner && $0.activity.id == id }?.generation
    }

    private static func retain(_ receipt: ActivityReconciliationReceipt, in manifest: inout ActivityRepositoryManifest) {
        let owner = ActivityAccountBoundary.context.owner
        let old = manifest.reconciliation[owner]
        manifest.reconciliation[owner] = .init(planningRevision: max(old?.planningRevision ?? 0, receipt.planningRevision),
            statisticsRevision: max(old?.statisticsRevision ?? 0, receipt.statisticsRevision), completion: nil,
            requiresStatisticsRead: old?.requiresStatisticsRead == true || receipt.requiresStatisticsRead == true)
        if let completion = receipt.completion {
            var completions = manifest.confirmedCompletions[owner] ?? []
            completions.removeAll { $0.plannedWorkoutId == completion.plannedWorkoutId || $0.activityId == completion.activityId }
            completions.append(completion)
            manifest.confirmedCompletions[owner] = completions
        }
    }

    static func retainAcceptance(_ receipt: ActivityReconciliationReceipt) throws {
        try ActivityAccountBoundary.validate()
        var manifest = try readManifest()
        retain(receipt, in: &manifest)
        try writeManifest(manifest)
    }

    static func acknowledge(_ activity: SavedActivity, generation: UInt64, receipt: ActivityReconciliationReceipt) throws -> SavedActivity? {
        try ActivityAccountBoundary.validate()
        var manifest = try readManifest()
        retain(receipt, in: &manifest)
        let index = manifest.records.firstIndex { $0.owner == ActivityAccountBoundary.context.owner && $0.activity.id == activity.id }
        if let index, manifest.records[index].generation == generation {
            manifest.records[index].activity = manifest.records[index].activity.withSync(activity.sync)
            manifest.records[index].rejection = nil
        }
        try writeManifest(manifest)
        guard let index, manifest.records[index].generation == generation else { return nil }
        return activity
    }

    private static func invalidateStatistics(in manifest: inout ActivityRepositoryManifest) {
        let owner = ActivityAccountBoundary.context.owner
        var generations = manifest.readInvalidationGenerations ?? [:]
        generations[owner] = (generations[owner] ?? 0) &+ 1
        manifest.readInvalidationGenerations = generations
        retain(.init(planningRevision: 0, statisticsRevision: 0, completion: nil, requiresStatisticsRead: true), in: &manifest)
    }

    static func invalidateReadModels() throws {
        try ActivityAccountBoundary.validate()
        var manifest = try readManifest()
        invalidateStatistics(in: &manifest)
        try writeManifest(manifest)
    }

    static func statisticsSnapshot() throws -> Data? {
        try ActivityAccountBoundary.validate()
        return try readManifest().statisticsSnapshots?[ActivityAccountBoundary.context.owner]?.data
    }

    static func storeStatisticsSnapshot(_ data: Data, revision: Int, ticket: UInt64) throws -> Bool {
        try ActivityAccountBoundary.validate()
        let owner = ActivityAccountBoundary.context.owner
        var manifest = try readManifest()
        guard ticket == (manifest.readInvalidationGenerations?[owner] ?? 0) else { return false }
        var snapshots = manifest.statisticsSnapshots ?? [:]
        guard revision >= (snapshots[owner]?.revision ?? 0) else { return false }
        snapshots[owner] = .init(revision: revision, data: data)
        manifest.statisticsSnapshots = snapshots
        try writeManifest(manifest)
        return true
    }

    static func planningSnapshot() throws -> Data? {
        try ActivityAccountBoundary.validate()
        return try readManifest().planningSnapshots?[ActivityAccountBoundary.context.owner]?.data
    }

    static func storePlanningSnapshot(_ data: Data, revision: Int?, invalidateStatistics: Bool) throws -> ActivityReadModelSnapshot {
        try ActivityAccountBoundary.validate()
        let owner = ActivityAccountBoundary.context.owner
        var manifest = try readManifest()
        var snapshots = manifest.planningSnapshots ?? [:]
        let existing = snapshots[owner]
        let selected = existing.map { ($0.revision ?? -1) > (revision ?? -1) ? $0 : ActivityReadModelSnapshot(revision: revision, data: data) }
            ?? ActivityReadModelSnapshot(revision: revision, data: data)
        #if DEBUG
        if failNextPlanningFixtureWrite {
            failNextPlanningFixtureWrite = false
            throw CocoaError(.fileWriteOutOfSpace)
        }
        #endif
        snapshots[owner] = selected
        manifest.planningSnapshots = snapshots
        if invalidateStatistics { self.invalidateStatistics(in: &manifest) }
        try writeManifest(manifest)
        return selected
    }

    static func statisticsReadTicket() throws -> UInt64 {
        try ActivityAccountBoundary.validate()
        return try readManifest().readInvalidationGenerations?[ActivityAccountBoundary.context.owner] ?? 0
    }

    static func finishReconciliation(planning: Int?, statistics: Int?, statisticsTicket: UInt64?) throws {
        try ActivityAccountBoundary.validate()
        var manifest = try readManifest(), owner = ActivityAccountBoundary.context.owner
        guard let cursor = manifest.reconciliation[owner] else { return }
        let p = planning.map { $0 >= cursor.planningRevision } == true ? 0 : cursor.planningRevision
        let s = statistics.map { $0 >= cursor.statisticsRevision } == true ? 0 : cursor.statisticsRevision
        let needsStatisticsRead = cursor.requiresStatisticsRead == true
            && (statistics == nil || statisticsTicket != (manifest.readInvalidationGenerations?[owner] ?? 0))
        manifest.reconciliation[owner] = p == 0 && s == 0 && !needsStatisticsRead ? nil
            : .init(planningRevision: p, statisticsRevision: s, completion: nil, requiresStatisticsRead: needsStatisticsRead)
        try writeManifest(manifest)
    }

    static func verifiedLegacyActivity(serverID: String, clientID: UUID) throws -> SavedActivity? {
        try ActivityAccountBoundary.validate()
        guard ActivityAccountBoundary.context.owner.hasPrefix("account:") else { return nil }
        var manifest = try readManifest()
        guard let index = manifest.records.firstIndex(where: { $0.owner == "legacy-unverified" && $0.activity.id == clientID && $0.activity.sync?.serverActivityId == serverID }) else { return nil }
        manifest.records[index].owner = ActivityAccountBoundary.context.owner
        try writeManifest(manifest)
        return manifest.records[index].activity.withRoute(try loadRoute(for: clientID))
    }

    static func adoptCanonical(_ canonical: SavedActivity, replacing source: SavedActivity, generation: UInt64, canonicalGeneration: UInt64?, receipt: ActivityReconciliationReceipt) throws -> SavedActivity? {
        try ActivityAccountBoundary.validate()
        var manifest = try readManifest(), owner = ActivityAccountBoundary.context.owner
        retain(receipt, in: &manifest)
        let target = manifest.records.first { $0.owner == owner && $0.activity.id == canonical.id }
        guard let original = manifest.records.first(where: { $0.owner == owner && $0.activity.id == source.id }),
              original.generation == generation, target?.generation == canonicalGeneration,
              (target == nil || target?.activity.sync?.isSynced == true) else {
            try writeManifest(manifest)
            return nil
        }
        // Metadata-only photo updates do not change the user mutation generation.
        // Merge them from the current actor rows rather than dropping late cloud metadata.
        let copiedCurrentSource = try copyPhotos(original.activity.photos, into: canonical.id)
        var photos = canonical.photos
        for latest in (target?.activity.photos ?? []) + copiedCurrentSource {
            if let index = photos.firstIndex(where: { $0.id == latest.id }) {
                let prepared = photos[index]
                photos[index] = SavedPhoto(id: prepared.id, takenAt: prepared.takenAt, paceAtShot: prepared.paceAtShot,
                    hrAtShot: prepared.hrAtShot, distAtShot: prepared.distAtShot, coordinate: prepared.coordinate,
                    captureContext: prepared.captureContext, relativePath: prepared.relativePath,
                    remotePhotoId: latest.remotePhotoId ?? prepared.remotePhotoId, remoteUploadedAt: latest.remoteUploadedAt ?? prepared.remoteUploadedAt,
                    remoteThumbnailURL: latest.remoteThumbnailURL ?? prepared.remoteThumbnailURL, isImported: prepared.isImported)
            } else { photos.append(latest) }
        }
        let canonical = canonical.withPhotos(photos)
        // Prepare every referenced sidecar before atomically switching both identities.
        // Failed preparation leaves the source intact; orphaned prepared files are harmless.
        let journal = try prepareCanonicalJournal(sourceID: source.id, targetID: canonical.id, generation: generation)
        try saveRoute(canonical.route, for: canonical.id)
        let sourceDirectory = try directory(for: source.id)
        let targetDirectory = try directory(for: canonical.id)
        let originalRoute = sourceDirectory.appendingPathComponent("route.original.bin")
        let targetOriginal = targetDirectory.appendingPathComponent("route.original.bin")
        if FileManager.default.fileExists(atPath: originalRoute.path), !FileManager.default.fileExists(atPath: targetOriginal.path) {
            try FileManager.default.copyItem(at: originalRoute, to: targetOriginal)
        }
        manifest.records.removeAll { $0.owner == owner && ($0.activity.id == source.id || $0.activity.id == canonical.id) }
        manifest.records.append(.init(owner: owner, generation: generation, activity: canonical.withRoute(nil)))
        retain(receipt, in: &manifest)
        try writeManifest(manifest)
        try FileManager.default.removeItem(at: journal)
        removeMediaIfUnreferenced(source.id, manifest: manifest)
        return canonical
    }

    private static func removeMediaIfUnreferenced(_ id: UUID, manifest: ActivityRepositoryManifest) {
        guard !manifest.records.contains(where: { $0.activity.id == id }) else { return }
        do {
            let directory = try activitiesDirectory().appendingPathComponent(id.uuidString)
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        } catch {
            ActivityDiagnosticLog.error(.persistence, "Unreferenced activity media cleanup failed error=\(ActivityDiagnosticLog.errorCategory(error))")
        }
    }

    private static func directory(for activityId: UUID) throws -> URL {
        let url = try activitiesDirectory().appendingPathComponent(activityId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func manifestURL() throws -> URL {
        try activitiesDirectory().appendingPathComponent(manifestFileName)
    }

    private static func activitiesDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appendingPathComponent("Outbound/Activities", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

nonisolated extension SavedActivity {
    func withRoute(_ replacement: SavedRoute?) -> SavedActivity { copied(route: replacement, photos: photos, sync: sync) }
    func withSync(_ replacement: SavedActivitySyncState?) -> SavedActivity { copied(route: route, photos: photos, sync: replacement) }
    func withPhotos(_ replacement: [SavedPhoto]) -> SavedActivity { copied(route: route, photos: replacement, sync: sync) }
    private func copied(route replacement: SavedRoute?, photos: [SavedPhoto], sync: SavedActivitySyncState?) -> SavedActivity {
        SavedActivity(
            id: id, activityType: activityType, title: title, guideNudge: guideNudge,
            reflection: reflection, sessionEffortRating: sessionEffortRating, performedWorkoutReference: performedWorkoutReference, plannedWorkoutCompletionQuality: plannedWorkoutCompletionQuality, createdAt: createdAt, startedAt: startedAt, endedAt: endedAt,
            durationSecs: durationSecs, distanceM: distanceM, avgPace: avgPace,
            elevationGainM: elevationGainM, walkingStepCount: walkingStepCount,
            healthMetrics: healthMetrics, goal: goal, energyKilocalories: energyKilocalories,
            companionType: companionType, source: source, gear: gear, manualEdits: manualEdits,
            indoor: indoor, cadence: cadence, heartRateZones: heartRateZones,
            recordingSession: recordingSession, activityEventID: activityEventID,
            followedRoute: followedRoute, recognitionBadgeIDs: recognitionBadgeIDs,
            route: replacement, photos: photos, sync: sync
        )
    }
}

nonisolated struct FollowedRouteMetadata: Codable, Hashable {
    let source: PreparedRoute.Source
    let routeID: String
    let direction: RouteDirection
    let finalProgress: Double
    let arrived: Bool

    init(route: PreparedRoute, finalProgress: Double, arrived: Bool) {
        source = route.source
        routeID = route.id
        direction = route.direction
        self.finalProgress = min(1, max(0, finalProgress.isFinite ? finalProgress : 0))
        self.arrived = arrived
    }
}

nonisolated struct ActivityRecordingSessionMetadata: Codable, Hashable {
    enum Origin: String, Codable, Hashable {
        case iPhone = "iphone"
        case appleWatch = "apple_watch"
    }

    enum RecordingDevice: String, Codable, Hashable {
        case phoneOnly = "phone_only"
        case appleWatch = "apple_watch"
    }

    enum HealthKitOwnership: String, Codable, Hashable {
        case phoneWriteBack = "phone_write_back"
        case externalAppleWorkout = "external_apple_workout"
        case appleWatchPrimary = "apple_watch_primary"
    }

    let sessionUUID: UUID
    let origin: Origin
    let recordingDevice: RecordingDevice
    let healthKitOwnership: HealthKitOwnership
    let healthKitWorkoutExternalReference: String?
}

nonisolated struct ActivityClientExtras: Codable, Hashable {
    let sessionEffortRating: Int?
    let performedWorkoutReference: PerformedWorkoutReference?
    let plannedWorkoutCompletionQuality: String?
    let guideNudge: String
    let walkingStepCount: Int?
    let healthMetrics: ActivityHealthMetrics?
    let goal: ActivityGoal?
    let energyKilocalories: Int?
    let source: ActivitySourceMetadata
    let gear: ActivityGearAttachment?
    let manualEdits: ActivityManualEdits?
    let indoor: ActivityIndoorMetadata?
    let cadence: ActivityCadenceSummary?
    let heartRateZones: ActivityHeartRateZoneSummary?
    let recordingSession: ActivityRecordingSessionMetadata?
    let activityEventID: String?
    let followedRoute: FollowedRouteMetadata?
    let recognitionBadgeIDs: [RecognitionBadgeID]

    init(from activity: SavedActivity) {
        sessionEffortRating = activity.sessionEffortRating
        performedWorkoutReference = activity.performedWorkoutReference
        plannedWorkoutCompletionQuality = activity.plannedWorkoutCompletionQuality
        guideNudge = activity.guideNudge
        walkingStepCount = activity.walkingStepCount
        healthMetrics = activity.healthMetrics
        goal = activity.goal
        energyKilocalories = activity.energyKilocalories
        source = activity.source
        gear = activity.gear
        manualEdits = activity.manualEdits
        indoor = activity.indoor
        cadence = activity.cadence
        heartRateZones = activity.heartRateZones
        recordingSession = activity.recordingSession
        activityEventID = activity.activityEventID
        followedRoute = activity.followedRoute
        recognitionBadgeIDs = activity.recognitionBadgeIDs
    }
}

nonisolated struct SavedActivity: Codable, Identifiable, Hashable {
    static func == (lhs: SavedActivity, rhs: SavedActivity) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: UUID
    let activityType: ActivityType
    let title: String
    let guideNudge: String
    let reflection: FinishReflection?
    let sessionEffortRating: Int?
    let performedWorkoutReference: PerformedWorkoutReference?
    let plannedWorkoutCompletionQuality: String?
    let createdAt: Date
    let startedAt: Date
    let endedAt: Date
    let durationSecs: Int
    let distanceM: Double
    let avgPace: Double?
    let elevationGainM: Double?
    let walkingStepCount: Int?
    let healthMetrics: ActivityHealthMetrics?
    let goal: ActivityGoal?
    let energyKilocalories: Int?
    let companionType: ActivityCompanionType?
    let source: ActivitySourceMetadata
    let gear: ActivityGearAttachment?
    let manualEdits: ActivityManualEdits?
    let indoor: ActivityIndoorMetadata?
    let cadence: ActivityCadenceSummary?
    let heartRateZones: ActivityHeartRateZoneSummary?
    let recordingSession: ActivityRecordingSessionMetadata?
    let activityEventID: String?
    let followedRoute: FollowedRouteMetadata?
    let recognitionBadgeIDs: [RecognitionBadgeID]
    let route: SavedRoute?
    let photos: [SavedPhoto]
    let sync: SavedActivitySyncState?

    /// durationSecs is moving time; timestamps retain the complete outing.
    var elapsedDurationSecs: Int { max(durationSecs, Int(endedAt.timeIntervalSince(startedAt))) }

    var routePoints: [SavedRoutePoint] { route?.points ?? [] }
    var routeCoordinates: [CLLocationCoordinate2D] { routePoints.map(\.coordinate) }
    var routeCoordinateSegments: [[CLLocationCoordinate2D]] {
        guard !routePoints.isEmpty else { return [] }
        var result: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        for point in routePoints {
            if point.startsNewSegment, !current.isEmpty {
                result.append(current)
                current = []
            }
            current.append(point.coordinate)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
    var hasRoute: Bool { routePoints.count > 1 }

    // Backward-compatible decoder for activities saved before title/guideNudge existed
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        activityType = try c.decodeIfPresent(ActivityType.self, forKey: .activityType) ?? .running
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decode(Date.self, forKey: .endedAt)
        durationSecs = try c.decode(Int.self, forKey: .durationSecs)
        distanceM = try c.decode(Double.self, forKey: .distanceM)
        avgPace = try c.decodeIfPresent(Double.self, forKey: .avgPace)
        elevationGainM = try c.decodeIfPresent(Double.self, forKey: .elevationGainM)
            ?? c.decodeIfPresent(Double.self, forKey: .elevationM)
        walkingStepCount = try c.decodeIfPresent(Int.self, forKey: .walkingStepCount)
        if let decodedHealthMetrics = try c.decodeIfPresent(ActivityHealthMetrics.self, forKey: .healthMetrics) {
            healthMetrics = decodedHealthMetrics
        } else if let avgHeartRate = try c.decodeIfPresent(Int.self, forKey: .avgHeartRate) {
            healthMetrics = ActivityHealthMetrics(
                averageHeartRateBPM: avgHeartRate,
                maxHeartRateBPM: nil,
                heartRateSampleCount: 0
            )
        } else {
            healthMetrics = nil
        }
        goal = try c.decodeIfPresent(ActivityGoal.self, forKey: .goal)
        energyKilocalories = try c.decodeIfPresent(Int.self, forKey: .energyKilocalories)
        companionType = ActivityCompanionType(safeDecoding: try c.decodeIfPresent(String.self, forKey: .companionType))
        source = try c.decodeIfPresent(ActivitySourceMetadata.self, forKey: .source) ?? .outboundRecorded
        gear = try c.decodeIfPresent(ActivityGearAttachment.self, forKey: .gear)
        manualEdits = try c.decodeIfPresent(ActivityManualEdits.self, forKey: .manualEdits)
        indoor = try c.decodeIfPresent(ActivityIndoorMetadata.self, forKey: .indoor)
        cadence = try c.decodeIfPresent(ActivityCadenceSummary.self, forKey: .cadence)
        heartRateZones = try c.decodeIfPresent(ActivityHeartRateZoneSummary.self, forKey: .heartRateZones)
        recordingSession = try c.decodeIfPresent(ActivityRecordingSessionMetadata.self, forKey: .recordingSession)
        activityEventID = try c.decodeIfPresent(String.self, forKey: .activityEventID)
        followedRoute = try c.decodeIfPresent(FollowedRouteMetadata.self, forKey: .followedRoute)
        recognitionBadgeIDs = (try? c.decode([RecognitionBadgeID].self, forKey: .recognitionBadgeIDs)) ?? []
        if let savedRoute = try c.decodeIfPresent(SavedRoute.self, forKey: .route) {
            route = savedRoute
        } else {
            let legacyTrackPoints = (try? c.decode([SavedTrackPoint].self, forKey: .trackPoints)) ?? []
            route = legacyTrackPoints.isEmpty ? nil : SavedRoute(points: legacyTrackPoints.map(SavedRoutePoint.init))
        }
        photos = try c.decode([SavedPhoto].self, forKey: .photos)
        sync = try c.decodeIfPresent(SavedActivitySyncState.self, forKey: .sync)
        guideNudge = (try? c.decodeIfPresent(String.self, forKey: .guideNudge)) ?? ""
        reflection = try c.decodeIfPresent(FinishReflection.self, forKey: .reflection)
        sessionEffortRating = try c.decodeIfPresent(Int.self, forKey: .sessionEffortRating)
        performedWorkoutReference = try c.decodeIfPresent(PerformedWorkoutReference.self, forKey: .performedWorkoutReference)
        plannedWorkoutCompletionQuality = try c.decodeIfPresent(String.self, forKey: .plannedWorkoutCompletionQuality)
        let day = startedAt.formatted(.dateTime.weekday(.wide))
        title = ((try? c.decodeIfPresent(String.self, forKey: .title)) ?? nil) ?? "\(day) Run"
    }

    init(id: UUID, activityType: ActivityType = .running, title: String, guideNudge: String, reflection: FinishReflection?, sessionEffortRating: Int? = nil, performedWorkoutReference: PerformedWorkoutReference? = nil, plannedWorkoutCompletionQuality: String? = nil, createdAt: Date,
         startedAt: Date, endedAt: Date, durationSecs: Int, distanceM: Double,
         avgPace: Double?, elevationGainM: Double? = nil,
         walkingStepCount: Int? = nil,
         healthMetrics: ActivityHealthMetrics? = nil, goal: ActivityGoal? = nil,
         energyKilocalories: Int? = nil,
         companionType: ActivityCompanionType? = nil,
         source: ActivitySourceMetadata = .outboundRecorded,
         gear: ActivityGearAttachment? = nil,
         manualEdits: ActivityManualEdits? = nil,
         indoor: ActivityIndoorMetadata? = nil,
         cadence: ActivityCadenceSummary? = nil,
         heartRateZones: ActivityHeartRateZoneSummary? = nil,
         recordingSession: ActivityRecordingSessionMetadata? = nil,
         activityEventID: String? = nil,
         followedRoute: FollowedRouteMetadata? = nil,
         recognitionBadgeIDs: [RecognitionBadgeID] = [],
         route: SavedRoute?,
         photos: [SavedPhoto], sync: SavedActivitySyncState?) {
        self.id = id; self.activityType = activityType; self.title = title; self.guideNudge = guideNudge
        self.reflection = reflection
        self.sessionEffortRating = sessionEffortRating
        self.performedWorkoutReference = performedWorkoutReference
        self.plannedWorkoutCompletionQuality = plannedWorkoutCompletionQuality
        self.createdAt = createdAt; self.startedAt = startedAt; self.endedAt = endedAt
        self.durationSecs = durationSecs; self.distanceM = distanceM; self.avgPace = avgPace
        self.elevationGainM = elevationGainM; self.walkingStepCount = walkingStepCount
        self.healthMetrics = healthMetrics
        self.goal = goal
        self.energyKilocalories = energyKilocalories
        self.companionType = companionType
        self.source = source
        self.gear = gear
        self.manualEdits = manualEdits
        self.indoor = indoor
        self.cadence = cadence
        self.heartRateZones = heartRateZones
        self.recordingSession = recordingSession
        self.activityEventID = activityEventID
        self.followedRoute = followedRoute
        self.recognitionBadgeIDs = recognitionBadgeIDs
        self.route = route; self.photos = photos; self.sync = sync
    }

    enum CodingKeys: String, CodingKey {
        case id
        case activityType
        case title
        case guideNudge
        case reflection
        case sessionEffortRating
        case performedWorkoutReference
        case plannedWorkoutCompletionQuality
        case createdAt
        case startedAt
        case endedAt
        case durationSecs
        case distanceM
        case avgPace
        case elevationGainM
        case elevationM
        case walkingStepCount
        case healthMetrics
        case avgHeartRate
        case goal
        case energyKilocalories
        case companionType
        case source
        case gear
        case manualEdits
        case indoor
        case cadence
        case heartRateZones
        case recordingSession
        case activityEventID
        case followedRoute
        case recognitionBadgeIDs
        case route
        case trackPoints
        case photos
        case sync
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(activityType, forKey: .activityType)
        try c.encode(title, forKey: .title)
        try c.encode(guideNudge, forKey: .guideNudge)
        try c.encodeIfPresent(reflection, forKey: .reflection)
        try c.encodeIfPresent(sessionEffortRating, forKey: .sessionEffortRating)
        try c.encodeIfPresent(performedWorkoutReference, forKey: .performedWorkoutReference)
        try c.encodeIfPresent(plannedWorkoutCompletionQuality, forKey: .plannedWorkoutCompletionQuality)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(endedAt, forKey: .endedAt)
        try c.encode(durationSecs, forKey: .durationSecs)
        try c.encode(distanceM, forKey: .distanceM)
        try c.encodeIfPresent(avgPace, forKey: .avgPace)
        try c.encodeIfPresent(elevationGainM, forKey: .elevationGainM)
        try c.encodeIfPresent(walkingStepCount, forKey: .walkingStepCount)
        try c.encodeIfPresent(healthMetrics, forKey: .healthMetrics)
        try c.encodeIfPresent(goal, forKey: .goal)
        try c.encodeIfPresent(energyKilocalories, forKey: .energyKilocalories)
        try c.encodeIfPresent(companionType?.rawValue, forKey: .companionType)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(gear, forKey: .gear)
        try c.encodeIfPresent(manualEdits, forKey: .manualEdits)
        try c.encodeIfPresent(indoor, forKey: .indoor)
        try c.encodeIfPresent(cadence, forKey: .cadence)
        try c.encodeIfPresent(heartRateZones, forKey: .heartRateZones)
        try c.encodeIfPresent(recordingSession, forKey: .recordingSession)
        try c.encodeIfPresent(activityEventID, forKey: .activityEventID)
        try c.encodeIfPresent(followedRoute, forKey: .followedRoute)
        // Route points live in a sidecar file and are intentionally absent from activities.json.
        try c.encode(photos, forKey: .photos)
        try c.encodeIfPresent(sync, forKey: .sync)
    }
}

nonisolated extension SavedActivity {
    func withImportedHealth(health: ActivityHealthMetrics?, energy: Int?, route importedRoute: SavedRoute?, distance: Double? = nil) -> SavedActivity {
        let watchRouteIsMoreComplete = manualEdits == nil && recordingSession?.healthKitOwnership == .appleWatchPrimary &&
            importedRoute != nil && distance.map { distanceM < $0 * 0.8 } == true
        let replaceRoute = routePoints.isEmpty || watchRouteIsMoreComplete
        let resolvedDistance = watchRouteIsMoreComplete ? (distance ?? distanceM) : distanceM
        return SavedActivity(
            id: id,
            activityType: activityType,
            title: title,
            guideNudge: guideNudge,
            reflection: reflection,
            sessionEffortRating: sessionEffortRating, performedWorkoutReference: performedWorkoutReference, plannedWorkoutCompletionQuality: plannedWorkoutCompletionQuality,
            createdAt: createdAt,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSecs: durationSecs,
            distanceM: resolvedDistance,
            avgPace: watchRouteIsMoreComplete ? activityType.plausibleAveragePace(durationSeconds: Double(durationSecs), distanceMeters: resolvedDistance) : avgPace,
            elevationGainM: elevationGainM,
            walkingStepCount: walkingStepCount,
            healthMetrics: manualEdits == nil ? (health ?? healthMetrics) : healthMetrics,
            goal: goal,
            energyKilocalories: manualEdits == nil ? (energy ?? energyKilocalories) : energyKilocalories,
            companionType: companionType,
            source: source,
            gear: gear,
            manualEdits: manualEdits,
            indoor: indoor,
            cadence: cadence,
            heartRateZones: heartRateZones,
            recordingSession: recordingSession,
            activityEventID: activityEventID,
            followedRoute: followedRoute,
            recognitionBadgeIDs: recognitionBadgeIDs,
            route: replaceRoute ? (importedRoute ?? route) : route,
            photos: photos,
            sync: sync
        )
    }

    func withHealthKitWorkoutReference(_ externalReference: String) -> SavedActivity {
        guard let recordingSession else { return self }
        return SavedActivity(
            id: id,
            activityType: activityType,
            title: title,
            guideNudge: guideNudge,
            reflection: reflection,
            sessionEffortRating: sessionEffortRating, performedWorkoutReference: performedWorkoutReference, plannedWorkoutCompletionQuality: plannedWorkoutCompletionQuality,
            createdAt: createdAt,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSecs: durationSecs,
            distanceM: distanceM,
            avgPace: avgPace,
            elevationGainM: elevationGainM,
            walkingStepCount: walkingStepCount,
            healthMetrics: healthMetrics,
            goal: goal,
            energyKilocalories: energyKilocalories,
            companionType: companionType,
            source: source,
            gear: gear,
            manualEdits: manualEdits,
            indoor: indoor,
            cadence: cadence,
            heartRateZones: heartRateZones,
            recordingSession: ActivityRecordingSessionMetadata(
                sessionUUID: recordingSession.sessionUUID,
                origin: recordingSession.origin,
                recordingDevice: recordingSession.recordingDevice,
                healthKitOwnership: recordingSession.healthKitOwnership,
                healthKitWorkoutExternalReference: externalReference
            ),
            activityEventID: activityEventID,
            followedRoute: followedRoute,
            recognitionBadgeIDs: recognitionBadgeIDs,
            route: route,
            photos: photos,
            sync: sync
        )
    }
}

/// Stable values persisted locally and in `Activity.type` on the backend.
/// This is intentionally broader than the sports currently selectable in the recorder.
nonisolated enum ActivityType: String, Codable, CaseIterable, Hashable {
    case running
    case cycling
    case hiking
    case walking
    case swimming
    case strengthTraining = "strength"
    case mobility

    /// Plausible displayed pace bounds for this sport, in seconds per kilometer.
    /// These bounds suppress vehicle-speed GPS artifacts without changing the
    /// recorded route or distance data used for later inspection.
    var plausiblePaceSecondsPerKilometer: ClosedRange<Double>? {
        switch self {
        case .cycling: 35...3_600
        case .walking: 240...3_600
        case .hiking: 200...3_600
        case .running: 150...1_500
        case .swimming, .strengthTraining, .mobility: 150...3_600
        }
    }

    func plausibleAveragePace(durationSeconds: Double, distanceMeters: Double) -> Double? {
        guard durationSeconds.isFinite, durationSeconds > 0,
              distanceMeters.isFinite, distanceMeters > 0,
              let bounds = plausiblePaceSecondsPerKilometer
        else { return nil }
        let pace = durationSeconds / (distanceMeters / 1_000)
        return bounds.contains(pace) ? pace : nil
    }
}

nonisolated struct ActivitySourceMetadata: Codable, Hashable {
    enum Kind: String, Codable, Hashable {
        case outbound
        case appleHealth
        case garminViaHealth
        case manual
        case strava
        case importedFile
    }

    let kind: Kind
    let displayName: String
    let deviceName: String?
    let externalID: String?
    let importedAt: Date?

    nonisolated static let outboundRecorded = ActivitySourceMetadata(
        kind: .outbound,
        displayName: "Plainstride",
        deviceName: nil,
        externalID: nil,
        importedAt: nil
    )

    var isManual: Bool { kind == .manual }
}

nonisolated struct ActivityGearAttachment: Codable, Hashable {
    let shoeID: UUID
    let shoeName: String
}

nonisolated struct ActivityManualEdits: Codable, Hashable {
    let editedAt: Date
    let editedFields: [String]
}

nonisolated struct ActivityIndoorMetadata: Codable, Hashable {
    let isIndoor: Bool
    let mode: String?

    init(isIndoor: Bool, mode: String?) {
        self.isIndoor = isIndoor
        self.mode = mode
    }

    private enum CodingKeys: String, CodingKey { case isIndoor, indoor, mode }

    init(from decoder: Decoder) throws {
        // Server snapshots may contain a bare flag or the earlier `indoor` key.
        // Preserve that fact, then encode only the canonical metadata object.
        if let flag = try? decoder.singleValueContainer().decode(Bool.self) {
            isIndoor = flag
            mode = nil
        } else {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            isIndoor = try c.decodeIfPresent(Bool.self, forKey: .isIndoor)
                ?? c.decode(Bool.self, forKey: .indoor)
            mode = try c.decodeIfPresent(String.self, forKey: .mode)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(isIndoor, forKey: .isIndoor)
        try c.encodeIfPresent(mode, forKey: .mode)
    }
}

nonisolated struct ActivityCadenceSummary: Codable, Hashable {
    let averageStepsPerMinute: Int?
    let maxStepsPerMinute: Int?
    let samples: [ActivityCadenceSample]?

    init(averageStepsPerMinute: Int?, maxStepsPerMinute: Int?, samples: [ActivityCadenceSample]? = nil) {
        self.averageStepsPerMinute = averageStepsPerMinute
        self.maxStepsPerMinute = maxStepsPerMinute
        self.samples = samples
    }
}

nonisolated struct ActivityCadenceSample: Codable, Hashable {
    let elapsedSeconds: Int
    let stepsPerMinute: Int
    let segment: Int
}

nonisolated struct ActivityHeartRateZoneSummary: Codable, Hashable {
    let estimatedMaxHeartRate: Int
    let zones: [ActivityHeartRateZone]
}

nonisolated struct ActivityHeartRateZone: Codable, Hashable, Identifiable {
    let index: Int
    let lowerBoundBPM: Int
    let upperBoundBPM: Int?
    let seconds: Int

    var id: Int { index }
}

nonisolated struct SavedActivitySyncState: Codable, Hashable {
    let clientActivityId: String
    let serverActivityId: String?
    let lastAttemptAt: Date?
    let syncedAt: Date?
    let lastError: String?
    let localUpdatedAt: Date?

    var isSynced: Bool { syncedAt != nil }
}

nonisolated struct SavedRoute: Codable, Hashable {
    let points: [SavedRoutePoint]
    let elevationMetadata: ActivityElevationMetadata?

    static func original(from segments: [[CLLocation]]) -> SavedRoute {
        SavedRoute(points: segments.flatMap { segment in
            segment.enumerated().map {
                SavedRoutePoint(location: $0.element, startsNewSegment: $0.offset == 0)
            }
        })
    }

    init(points: [SavedRoutePoint], elevationMetadata: ActivityElevationMetadata? = nil) {
        self.points = points
        self.elevationMetadata = elevationMetadata
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            points = try container.decode([SavedRoutePoint].self, forKey: .points)
            elevationMetadata = try container.decodeIfPresent(ActivityElevationMetadata.self, forKey: .elevationMetadata)
        } else {
            var container = try decoder.unkeyedContainer()
            points = try container.decode([SavedRoutePoint].self)
            elevationMetadata = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(points, forKey: .points)
        try container.encodeIfPresent(elevationMetadata, forKey: .elevationMetadata)
    }

    private enum CodingKeys: String, CodingKey {
        case points
        case elevationMetadata
        case visibility
    }
}

nonisolated struct ActivityElevationMetadata: Codable, Hashable {
    let algorithmVersion: String
    let provider: String
    let attributionText: String
    let attributionURL: String
    let modified: Bool
}

nonisolated struct SavedRoutePoint: Codable, Hashable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let verticalAccuracy: Double?
    let startsNewSegment: Bool

    nonisolated init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double?,
        verticalAccuracy: Double?,
        startsNewSegment: Bool = false
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.verticalAccuracy = verticalAccuracy
        self.startsNewSegment = startsNewSegment
    }

    nonisolated init(location: CLLocation, startsNewSegment: Bool = false) {
        timestamp = location.timestamp
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        verticalAccuracy = location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil
        self.startsNewSegment = startsNewSegment
    }

    nonisolated init(trackPoint: SavedTrackPoint) {
        timestamp = trackPoint.timestamp
        latitude = trackPoint.latitude
        longitude = trackPoint.longitude
        altitude = trackPoint.altitude
        verticalAccuracy = nil
        startsNewSegment = false
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func simplified(from locations: [CLLocation]) -> [SavedRoutePoint] {
        simplifiedSegment(locations, startsNewSegment: true)
    }

    static func simplified(from segments: [[CLLocation]]) -> [SavedRoutePoint] {
        segments.flatMap { simplifiedSegment($0, startsNewSegment: true) }
    }

    private static func simplifiedSegment(
        _ locations: [CLLocation],
        startsNewSegment: Bool
    ) -> [SavedRoutePoint] {
        guard locations.count > 2 else {
            return locations.enumerated().map {
                SavedRoutePoint(location: $0.element, startsNewSegment: startsNewSegment && $0.offset == 0)
            }
        }

        var keptIndices = [0]
        var lastKeptIndex = 0

        for index in 1..<(locations.count - 1) {
            let current = locations[index]
            let lastKept = locations[lastKeptIndex]
            let next = locations[index + 1]

            let distanceFromLastKept = current.distance(from: lastKept)
            let secondsFromLastKept = current.timestamp.timeIntervalSince(lastKept.timestamp)
            let shouldKeepForDistance = distanceFromLastKept >= 10
            let shouldKeepForTime = secondsFromLastKept >= 15
            let shouldKeepForTurn = isMeaningfulTurn(previous: lastKept, current: current, next: next)

            if shouldKeepForDistance || shouldKeepForTime || shouldKeepForTurn {
                keptIndices.append(index)
                lastKeptIndex = index
            }
        }

        if keptIndices.last != locations.indices.last {
            keptIndices.append(locations.count - 1)
        }

        return keptIndices.enumerated().map {
            SavedRoutePoint(
                location: locations[$0.element],
                startsNewSegment: startsNewSegment && $0.offset == 0
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp, latitude, longitude, altitude, verticalAccuracy, startsNewSegment
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        altitude = try container.decodeIfPresent(Double.self, forKey: .altitude)
        verticalAccuracy = try container.decodeIfPresent(Double.self, forKey: .verticalAccuracy)
        startsNewSegment = try container.decodeIfPresent(Bool.self, forKey: .startsNewSegment) ?? false
    }

    private static func isMeaningfulTurn(previous: CLLocation, current: CLLocation, next: CLLocation) -> Bool {
        let incomingDistance = previous.distance(from: current)
        let outgoingDistance = current.distance(from: next)
        guard incomingDistance >= 5, outgoingDistance >= 5 else { return false }

        let incomingBearing = bearing(from: previous.coordinate, to: current.coordinate)
        let outgoingBearing = bearing(from: current.coordinate, to: next.coordinate)
        let delta = abs(incomingBearing - outgoingBearing).truncatingRemainder(dividingBy: 360)
        let normalizedDelta = delta > 180 ? 360 - delta : delta
        return normalizedDelta >= 20
    }

    private static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let startLat = start.latitude * .pi / 180
        let startLon = start.longitude * .pi / 180
        let endLat = end.latitude * .pi / 180
        let endLon = end.longitude * .pi / 180
        let deltaLon = endLon - startLon

        let y = sin(deltaLon) * cos(endLat)
        let x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(deltaLon)
        let angle = atan2(y, x) * 180 / .pi
        return angle >= 0 ? angle : angle + 360
    }
}

nonisolated struct SavedTrackPoint: Codable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let horizontalAccuracy: Double
    let speed: Double
}

nonisolated enum RouteExportFormat: String, CaseIterable, Identifiable {
    case gpx
    case geoJSON

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gpx: return "GPX"
        case .geoJSON: return "GeoJSON"
        }
    }

    var fileExtension: String {
        switch self {
        case .gpx: return "gpx"
        case .geoJSON: return "geojson"
        }
    }
}

nonisolated enum RouteFileExporter {
    static func export(activity: SavedActivity, format: RouteExportFormat) throws -> URL {
        guard activity.hasRoute else { throw RouteExportError.missingRoute }

        let fileName = sanitizedFileName(for: activity, format: format)
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let data: Data

        switch format {
        case .gpx:
            data = Data(gpxString(for: activity).utf8)
        case .geoJSON:
            data = try geoJSONData(for: activity)
        }

        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private static func gpxString(for activity: SavedActivity) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let routeSegments = Self.routePointSegments(activity.routePoints)
        let segments = routeSegments.map { segment -> String in
            let points = segment.map { point -> String in
                var lines = [
                    "      <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\">"
                ]
                if let altitude = point.altitude {
                    lines.append("        <ele>\(altitude)</ele>")
                }
                lines.append("        <time>\(formatter.string(from: point.timestamp))</time>")
                lines.append("      </trkpt>")
                return lines.joined(separator: "\n")
            }.joined(separator: "\n")
            return "    <trkseg>\n\(points)\n    </trkseg>"
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Plainstride" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(escapedXML(activity.title))</name>
            <time>\(formatter.string(from: activity.startedAt))</time>
          </metadata>
          <trk>
            <name>\(escapedXML(activity.title))</name>
        \(segments)
          </trk>
        </gpx>
        """
    }

    private static func geoJSONData(for activity: SavedActivity) throws -> Data {
        var properties: [String: Any] = [
            "id": activity.id.uuidString,
            "title": activity.title,
            "startedAt": iso8601String(activity.startedAt),
            "endedAt": iso8601String(activity.endedAt),
            "distanceM": activity.distanceM,
            "durationSecs": activity.durationSecs,
            "visibility": "private"
        ]
        if let elevationGainM = activity.elevationGainM {
            properties["elevationGainM"] = elevationGainM
        }
        if let averageHeartRate = activity.healthMetrics?.averageHeartRateBPM {
            properties["avgHeartRate"] = averageHeartRate
        }

        let coordinateSegments = routePointSegments(activity.routePoints).map { segment in
            segment.map { point in
                if let altitude = point.altitude {
                    return [point.longitude, point.latitude, altitude]
                }
                return [point.longitude, point.latitude]
            }
        }
        let geometry: [String: Any] = coordinateSegments.count > 1
            ? ["type": "MultiLineString", "coordinates": coordinateSegments]
            : ["type": "LineString", "coordinates": coordinateSegments.first ?? []]
        let payload: [String: Any] = [
            "type": "Feature",
            "properties": properties,
            "geometry": geometry
        ]

        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static func routePointSegments(_ points: [SavedRoutePoint]) -> [[SavedRoutePoint]] {
        guard !points.isEmpty else { return [] }
        var segments: [[SavedRoutePoint]] = []
        var current: [SavedRoutePoint] = []
        for point in points {
            if point.startsNewSegment, !current.isEmpty {
                segments.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    private static func sanitizedFileName(for activity: SavedActivity, format: RouteExportFormat) -> String {
        let rawTitle = activity.title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
        let fallback = "route-\(activity.id.uuidString.prefix(8))"
        let title = rawTitle.isEmpty ? fallback : rawTitle
        return "\(title).\(format.fileExtension)"
    }

    private static func escapedXML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

nonisolated enum RouteExportError: LocalizedError {
    case missingRoute

    var errorDescription: String? {
        switch self {
        case .missingRoute:
            return "This activity does not have enough route data to share yet."
        }
    }
}

nonisolated struct SavedPhoto: Codable, Identifiable {
    let id: UUID
    let takenAt: Date
    let paceAtShot: Double?
    let hrAtShot: Int?
    let distAtShot: Double
    let coordinate: SavedCoordinate?
    let captureContext: PhotoCaptureContext
    let isImported: Bool
    let relativePath: String
    let remotePhotoId: String?
    let remoteUploadedAt: Date?
    let remoteThumbnailURL: String?

    nonisolated init(metadata: PhotoMetadata, relativePath: String) {
        id = UUID()
        takenAt = metadata.takenAt
        paceAtShot = metadata.paceAtShot
        hrAtShot = metadata.hrAtShot
        distAtShot = metadata.distAtShot
        coordinate = metadata.coordinate.map { SavedCoordinate(coordinate: $0) }
        captureContext = metadata.captureContext
        isImported = metadata.isImported
        self.relativePath = relativePath
        remotePhotoId = nil
        remoteUploadedAt = nil
        remoteThumbnailURL = nil
    }

    nonisolated init(
        id: UUID, takenAt: Date, paceAtShot: Double?, hrAtShot: Int?, distAtShot: Double,
        coordinate: SavedCoordinate?, captureContext: PhotoCaptureContext, relativePath: String,
        remotePhotoId: String?, remoteUploadedAt: Date?, remoteThumbnailURL: String? = nil, isImported: Bool = false
    ) {
        self.id = id
        self.takenAt = takenAt
        self.paceAtShot = paceAtShot
        self.hrAtShot = hrAtShot
        self.distAtShot = distAtShot
        self.coordinate = coordinate
        self.captureContext = captureContext
        self.isImported = isImported
        self.relativePath = relativePath
        self.remotePhotoId = remotePhotoId
        self.remoteUploadedAt = remoteUploadedAt
        self.remoteThumbnailURL = remoteThumbnailURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        takenAt = try c.decode(Date.self, forKey: .takenAt)
        paceAtShot = try c.decodeIfPresent(Double.self, forKey: .paceAtShot)
        hrAtShot = try c.decodeIfPresent(Int.self, forKey: .hrAtShot)
        distAtShot = try c.decode(Double.self, forKey: .distAtShot)
        coordinate = try c.decodeIfPresent(SavedCoordinate.self, forKey: .coordinate)
        captureContext = (try? c.decode(PhotoCaptureContext.self, forKey: .captureContext)) ?? .active
        isImported = try c.decodeIfPresent(Bool.self, forKey: .isImported) ?? false
        relativePath = try c.decode(String.self, forKey: .relativePath)
        remotePhotoId = try c.decodeIfPresent(String.self, forKey: .remotePhotoId)
        remoteUploadedAt = try c.decodeIfPresent(Date.self, forKey: .remoteUploadedAt)
        remoteThumbnailURL = try c.decodeIfPresent(String.self, forKey: .remoteThumbnailURL)
    }
}

nonisolated struct SavedCoordinate: Codable {
    let latitude: Double
    let longitude: Double

    nonisolated init(coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    nonisolated init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

nonisolated enum ActivityPhotoPersistenceError: LocalizedError {
    case invalidImage
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImage: "The saved activity photo is not a valid image."
        case .imageTooLarge: "The activity photo could not be compressed below 5 MB."
        }
    }
}
