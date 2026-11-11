import Foundation

/// A request's account identity survives actor suspension, retries and a same-account relogin.
nonisolated struct ActivityAccountContext: Equatable, Sendable {
  let owner: String
  let epoch: UInt64
}

nonisolated enum ActivityAccountBoundary {
  private final class State: @unchecked Sendable {
    let lock = NSLock()
    var value = ActivityAccountContext(owner: "guest", epoch: 0)
  }
  private static let state = State()
  @TaskLocal static var operation: ActivityAccountContext?

  static var current: ActivityAccountContext {
    state.lock.lock()
    defer { state.lock.unlock() }
    return state.value
  }
  static var context: ActivityAccountContext { operation ?? current }
  static func activate(_ userID: String?) {
    state.lock.lock()
    defer { state.lock.unlock() }
    let owner = userID.map { "account:\($0)" } ?? "guest"
    guard state.value.owner != owner else { return }
    state.value = .init(owner: owner, epoch: state.value.epoch &+ 1)
  }
  static func validate(_ context: ActivityAccountContext? = nil) throws {
    guard (context ?? self.context) == current else { throw CancellationError() }
  }
  static func withAccount<T>(_ body: () async throws -> T) async rethrows -> T {
    try await $operation.withValue(context, operation: body)
  }
}

nonisolated struct ActivityCompletionAssociation: Codable, Equatable, Sendable {
  let activityId: String
  let plannedWorkoutId: String
  let planVersionId: String
  let status: String
  let prescribedDurationSeconds: Int
}

nonisolated struct ActivityReconciliationReceipt: Codable, Equatable, Sendable {
  let planningRevision: Int
  let statisticsRevision: Int
  let completion: ActivityCompletionAssociation?
  var requiresStatisticsRead: Bool? = nil
}

nonisolated struct ActivityRepositoryRecord: Codable {
  var owner: String
  var generation: UInt64
  var activity: SavedActivity
  var rejection: String? = nil
}

/// The activity, exact receipt, ownership and outbox are published with one atomic file rename.
/// Confirmed associations live beyond local history deletion because backend deletion retains them.
nonisolated struct ActivityReadModelSnapshot: Codable {
    let revision: Int?
    let data: Data
}

nonisolated struct ActivityRepositoryManifest: Codable {
  var schemaVersion = 1
  var records: [ActivityRepositoryRecord] = []
  var reconciliation: [String: ActivityReconciliationReceipt] = [:]
  var confirmedCompletions: [String: [ActivityCompletionAssociation]] = [:]
  var readInvalidationGenerations: [String: UInt64]? = nil
  var planningSnapshots: [String: ActivityReadModelSnapshot]? = nil
  var statisticsSnapshots: [String: ActivityReadModelSnapshot]? = nil
}

nonisolated struct ActivityRepositoryProjection: Equatable {
  var pendingWorkoutIDs: Set<String> = []
  var conflictedWorkoutIDs: Set<String> = []
  var blockedActivityIDs: Set<UUID> = []
  var confirmedCompletions: [ActivityCompletionAssociation] = []
  var reconciliation: ActivityReconciliationReceipt?
}

nonisolated struct ActivityRepositorySnapshot {
  var activities: [SavedActivity] = []
  var projection = ActivityRepositoryProjection()
}

nonisolated struct ActivityUploadSnapshot {
    let activity: SavedActivity
    let generation: UInt64
}
