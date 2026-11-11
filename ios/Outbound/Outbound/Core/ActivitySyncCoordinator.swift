import Combine
import Foundation
import UIKit

/// App-lifetime synchronization and read-model reconciliation. Screens observe stores;
/// opening or closing a screen never determines whether saved work is reconciled.
@MainActor
final class ActivitySyncCoordinator: ObservableObject {
  private var subscriptions = Set<AnyCancellable>()
  private var task: Task<Void, Never>?
  private var taskID: UUID?
  private var retryTask: Task<Void, Never>?
  private weak var activities: ActivityStore?
  private weak var planning: TrainingPlanStore?
  private weak var checkIn: DailyCheckInStore?
  private weak var connectivity: ConnectivityStore?
  private weak var goals: GoalStore?
  private weak var personalization: PersonalizationStore?
  private weak var scheduler: WorkoutNotificationScheduler?
  private var context: ActivityAccountContext?
  private var needsPass = false
  private var configured = false
  private var isActivating = false
  private var retryDelay: UInt64 = 2

  func configure(
    activities: ActivityStore, planning: TrainingPlanStore,
    checkIn: DailyCheckInStore, connectivity: ConnectivityStore,
    preferences: WorkoutReminderPreferences, scheduler: WorkoutNotificationScheduler,
    goals: GoalStore? = nil, personalization: PersonalizationStore? = nil
  ) {
    guard !configured else { return }
    configured = true
    self.activities = activities
    self.planning = planning
    self.checkIn = checkIn
    self.connectivity = connectivity
    self.goals = goals
    self.personalization = personalization
    self.scheduler = scheduler
    activities.synchronizationRequested = { [weak self] in self?.requestSync() }
    activities.$repositorySnapshot
      .sink { [weak self, weak planning] snapshot in
        let rows = snapshot.activities
        let projection = snapshot.projection
        guard let self, self.context == ActivityAccountBoundary.current else { return }
        planning?.applyRepositoryProjection(projection, activities: rows)
        self.goals?.updateStatistics(activities.accountStatistics, activities: rows)
        activities.planningCalendarTimeZone = planning?.activePlan?.calendar?.timeZone
        if rows.contains(where: { $0.sync?.isSynced != true && !projection.blockedActivityIDs.contains($0.id) }) || projection.reconciliation != nil {
          self.requestSync()
        }
      }.store(in: &subscriptions)
    activities.$accountStatistics.sink { [weak self, weak activities] statistics in
      guard let self, self.context == ActivityAccountBoundary.current else { return }
      self.goals?.updateStatistics(statistics, activities: activities?.repositorySnapshot.activities ?? [])
    }.store(in: &subscriptions)
    planning.$acceptedCommandGeneration.dropFirst().sink { [weak self] _ in self?.requestSync() }.store(in: &subscriptions)
    checkIn.$todayEntry.dropFirst().sink { [weak self] _ in self?.refreshPlanningInputs() }.store(
      in: &subscriptions)
    connectivity.$isOffline.removeDuplicates().sink { [weak self] offline in
      if !offline { Task { @MainActor [weak self] in self?.requestSync() } }
    }.store(in: &subscriptions)
    NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
      .sink { [weak self] _ in
        self?.requestSync()
        self?.refreshPlanningInputs()
      }.store(in: &subscriptions)
    for name in [Notification.Name.NSCalendarDayChanged, UIApplication.significantTimeChangeNotification] {
      NotificationCenter.default.publisher(for: name).sink { [weak self] _ in
        guard let self, self.context == ActivityAccountBoundary.current,
              let activities = self.activities else { return }
        self.planning?.applyRepositoryProjection(activities.repositorySnapshot.projection, activities: activities.repositorySnapshot.activities)
        self.requestSync()
      }.store(in: &subscriptions)
    }
    Publishers.CombineLatest(activities.$repositorySnapshot, planning.$scheduledWorkouts)
      .sink { [weak self] snapshot, workouts in
        let rows = snapshot.activities
        guard let self, self.context == ActivityAccountBoundary.current else { return }
        let context = ActivityAccountBoundary.current
        Task {
          guard context == ActivityAccountBoundary.current else { return }
          await scheduler.reschedule(
            preferences: preferences, activities: rows, workouts: workouts,
            reason: "repository_changed")
        }
      }.store(in: &subscriptions)
  }

  #if DEBUG
  func stopRepositoryFixture() {
    guard ProcessInfo.processInfo.arguments.contains("-OutboundDebugActivityRepository") else { return }
    task?.cancel(); task = nil
    retryTask?.cancel(); retryTask = nil
    subscriptions.removeAll()
  }
  #endif

  func activateAccount() async {
    let next = ActivityAccountBoundary.current
    guard next != context else { return }
    task?.cancel()
    task = nil
    retryTask?.cancel()
    retryTask = nil
    context = next
    isActivating = true
    defer { isActivating = false }
    retryDelay = 2
    needsPass = false
    planning?.activateAccount()
    goals?.activateAccount()
    personalization?.activateAccount()
    let userID = next.owner.hasPrefix("account:") ? String(next.owner.dropFirst("account:".count)) : nil
    await scheduler?.configure(analyticsManager: nil, accountID: userID)
    guard next == ActivityAccountBoundary.current else { return }
    await ActivityAccountBoundary.$operation.withValue(next) { await activities?.activateAccount() }
    guard next == ActivityAccountBoundary.current else { return }
    await planning?.loadDurableAccountState()
    guard next == ActivityAccountBoundary.current else { return }
    isActivating = false
    refreshPlanningInputs()
    requestSync()
  }

  private func refreshPlanningInputs() {
    guard context == ActivityAccountBoundary.current, let activities, let planning else { return }
    planning.refresh(
      activities: activities.activities, readiness: checkIn?.readiness,
      phase: DailyMotivationEngine.phase(for: activities.activities))
  }

  func requestSync() {
    guard configured, !isActivating, context == ActivityAccountBoundary.current,
      context?.owner.hasPrefix("account:") == true
    else { return }
    needsPass = true
    guard task == nil, connectivity?.isOffline != true else { return }
    retryTask?.cancel()
    retryTask = nil
    let context = ActivityAccountBoundary.current
    let id = UUID()
    taskID = id
    task = Task {
      defer {
        if taskID == id { task = nil; taskID = nil }
      }
      await ActivityAccountBoundary.$operation.withValue(context) {
        // Changes during this pass request at most one additional pass. Failed reads
        // keep their durable cursor and use a bounded backoff instead of a busy loop.
        needsPass = false
        await activities?.syncPendingActivitiesIfNeeded()
        guard context == ActivityAccountBoundary.current, !Task.isCancelled else { return }
        var planningRevision: Int?
        do {
          planningRevision = try await planning?.reconcileRepository()
        } catch is CancellationError { return } catch {
          ActivityDiagnosticLog.error(
            .sync,
            "Planning reconciliation failed error=\(ActivityDiagnosticLog.errorCategory(error))")
        }
        let statisticsGeneration = activities?.statisticsReadGeneration
        await activities?.refreshAccountStatistics()
        let statisticsRevision = activities?.statisticsReadGeneration != statisticsGeneration ? activities?.accountStatistics?.revision : nil
        await activities?.finishReconciliation(planning: planningRevision, statistics: statisticsRevision)
        await personalization?.refresh()
        guard context == ActivityAccountBoundary.current, !Task.isCancelled else { return }
        if taskID == id { task = nil; taskID = nil }
        if activities?.retryablePendingActivityCount ?? 0 > 0
          || activities?.repositoryProjection.reconciliation != nil
        {
          scheduleRetry(context: context)
        } else {
          retryDelay = 2
          if needsPass { requestSync() }
        }
      }
    }
  }

  private func scheduleRetry(context: ActivityAccountContext) {
    let delay = retryDelay
    retryDelay = min(60, retryDelay * 2)
    retryTask = Task {
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      guard context == ActivityAccountBoundary.current else { return }
      retryTask = nil
      requestSync()
    }
  }
}
