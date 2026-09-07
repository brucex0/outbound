import Combine
import Foundation
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class WorkoutReminderPreferences: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: enabledKey) }
    }

    @Published var reminderHour: Int {
        didSet { defaults.set(reminderHour, forKey: hourKey) }
    }

    @Published var reminderMinute: Int {
        didSet { defaults.set(reminderMinute, forKey: minuteKey) }
    }

    private let defaults: UserDefaults
    private let enabledKey = "workout_reminders_enabled_v1"
    private let hourKey = "workout_reminders_hour_v1"
    private let minuteKey = "workout_reminders_minute_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: enabledKey) as? Bool ?? false
        reminderHour = defaults.object(forKey: hourKey) as? Int ?? 8
        reminderMinute = defaults.object(forKey: minuteKey) as? Int ?? 0
    }

    func setTime(_ date: Date, calendar: Calendar = .current) {
        reminderHour = calendar.component(.hour, from: date)
        reminderMinute = calendar.component(.minute, from: date)
    }
}

struct ScheduledWorkoutReminder: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let workoutID: String
    let date: Date
    let title: String
    let durationSeconds: Int
    let sport: TrainingPlanSport
    let source: String

    init(
        id: String,
        workoutID: String,
        date: Date,
        title: String,
        durationSeconds: Int,
        sport: TrainingPlanSport,
        source: String
    ) {
        self.id = id
        self.workoutID = workoutID
        self.date = date
        self.title = title
        self.durationSeconds = durationSeconds
        self.sport = sport
        self.source = source
    }
}

@MainActor
final class WorkoutNotificationScheduler: ObservableObject {
    static let shared = WorkoutNotificationScheduler()
    static let notificationType = "local_workout_reminder"
    private static let scheduleKey = "workout_notification_schedule_v1"
    private static let identifierPrefix = "plainstride.workout."
    private static let horizonDays = 14

    @Published private(set) var pendingReminderCount = 0
    @Published private(set) var pendingReminder: ScheduledWorkoutReminder?

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let calendar: Calendar
    private var analyticsManager: AnalyticsManager?
    private var currentAccountID: String?
    private var cachedWorkouts: [ScheduledWorkoutReminder] = []

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.center = center
        self.defaults = defaults
        self.calendar = calendar
        cachedWorkouts = Self.decode([ScheduledWorkoutReminder].self, from: defaults.data(forKey: Self.scheduleKey)) ?? []
    }

    func configure(analyticsManager: AnalyticsManager?, accountID: String?) {
        self.analyticsManager = analyticsManager
        if currentAccountID != accountID || accountID == nil {
            currentAccountID = accountID
            Task { await cancelAll(reason: "account_changed") }
        }
    }

    func requestPermissionAndEnable(
        preferences: WorkoutReminderPreferences,
        activities: [SavedActivity]
    ) async -> Bool {
        let settings = await center.notificationSettings()
        let status: UNAuthorizationStatus
        if settings.authorizationStatus == .notDetermined {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                status = granted ? .authorized : .denied
            } catch {
                status = .denied
            }
        } else {
            status = settings.authorizationStatus
        }

        let enabled = status == .authorized || status == .provisional
        preferences.isEnabled = enabled
        track(.workoutReminderSettingChanged, properties: [
            .selectionType: .string(enabled ? "enabled" : "disabled")
        ])
        track(.workoutReminderPermissionResult, properties: [
            .result: .string(enabled ? "authorized" : "denied")
        ])
        if enabled {
            await reschedule(preferences: preferences, activities: activities, reason: "setting_enabled")
        }
        return enabled
    }

    func disable(preferences: WorkoutReminderPreferences) async {
        preferences.isEnabled = false
        track(.workoutReminderSettingChanged, properties: [.selectionType: .string("disabled")])
        await cancelAll(reason: "setting_disabled")
    }

    func reschedule(
        preferences: WorkoutReminderPreferences,
        activities: [SavedActivity],
        workouts: [ScheduledWorkoutReminder]? = nil,
        reason: String
    ) async {
        guard preferences.isEnabled else {
            await cancelAll(reason: "setting_disabled")
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let resolvedWorkouts = deduplicated((workouts ?? cachedWorkouts)
            .filter { reminder in
                reminder.date >= Date()
                    && reminder.date < calendar.date(byAdding: .day, value: Self.horizonDays, to: Date())!
                    && !isCompleted(reminder, activities: activities)
                    && reminder.durationSeconds > 0
            }
            .sorted { $0.date < $1.date })

        let identifiers = Set(resolvedWorkouts.map(Self.identifier(for:)))
        let existingIdentifiers = await pendingWorkoutIdentifiers()
        let obsolete = existingIdentifiers.filter { !identifiers.contains($0) }
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(obsolete))
        }

        var scheduled = 0
        for reminder in resolvedWorkouts {
            let fireDate = reminder.dateWithPreferredTime(preferences: preferences, calendar: calendar)
            guard fireDate > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "workout.reminder.title", defaultValue: "Your planned workout")
            content.body = Self.body(for: reminder)
            content.sound = .default
            content.userInfo = [
                "type": Self.notificationType,
                "destination": "today",
                "workoutID": reminder.workoutID,
                "reminderID": reminder.id,
                "source": reminder.source
            ]
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                repeats: false
            )
            do {
                try await center.add(UNNotificationRequest(
                    identifier: Self.identifier(for: reminder),
                    content: content,
                    trigger: trigger
                ))
                scheduled += 1
            } catch {
                continue
            }
        }

        cachedWorkouts = resolvedWorkouts
        persistSchedule()
        pendingReminderCount = scheduled
        track(.workoutReminderScheduleChanged, properties: [
            .result: .string(scheduled > 0 ? "scheduled" : "empty"),
            .sourceType: .string(reason)
        ])
    }

    func updateCachedWorkouts(_ workouts: [ScheduledWorkoutReminder]) {
        cachedWorkouts = deduplicated(workouts)
        persistSchedule()
    }

    func reminderTimeChanged(preferences: WorkoutReminderPreferences, activities: [SavedActivity]) async {
        track(.workoutReminderSettingChanged, properties: [.selectionType: .string("time_changed")])
        await reschedule(preferences: preferences, activities: activities, reason: "setting_changed")
    }

    func cancelForActivity(_ activity: SavedActivity, reason: String = "activity_saved") async {
        let day = calendar.startOfDay(for: activity.startedAt)
        let matches = cachedWorkouts.filter { calendar.isDate($0.date, inSameDayAs: day) }
        guard !matches.isEmpty else { return }
        let identifiers = matches.map(Self.identifier(for:))
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        cachedWorkouts.removeAll { calendar.isDate($0.date, inSameDayAs: day) }
        persistSchedule()
        pendingReminderCount = max(0, pendingReminderCount - identifiers.count)
        track(.workoutReminderScheduleChanged, properties: [
            .result: .string("cancelled"),
            .sourceType: .string(reason)
        ])
    }

    func cancelAll(reason: String) async {
        let identifiers = await pendingWorkoutIdentifiers()
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(identifiers))
        }
        cachedWorkouts = []
        pendingReminder = nil
        persistSchedule()
        pendingReminderCount = 0
        track(.workoutReminderScheduleChanged, properties: [
            .result: .string("cancelled"),
            .sourceType: .string(reason)
        ])
    }

    func handleNotification(userInfo: [AnyHashable: Any]) -> ScheduledWorkoutReminder? {
        guard userInfo["type"] as? String == Self.notificationType,
              let reminderID = userInfo["reminderID"] as? String else { return nil }
        let reminder = cachedWorkouts.first { $0.id == reminderID }
        pendingReminder = reminder
        track(.workoutReminderOpened, properties: [.destination: .string("today")])
        return reminder
    }

    func consumePendingReminder() {
        pendingReminder = nil
    }

    func notificationIdentifier(for reminderID: String) -> String {
        Self.identifier(for: reminderID)
    }

    private func deduplicated(_ workouts: [ScheduledWorkoutReminder]) -> [ScheduledWorkoutReminder] {
        var seenDays = Set<String>()
        return workouts.filter { workout in
            let day = calendar.startOfDay(for: workout.date).description
            return seenDays.insert(day).inserted
        }
    }

    private func pendingWorkoutIdentifiers() async -> Set<String> {
        let requests = await center.pendingNotificationRequests()
        return Set(requests.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) })
    }

    private func isCompleted(_ reminder: ScheduledWorkoutReminder, activities: [SavedActivity]) -> Bool {
        activities.contains { activity in
            calendar.isDate(activity.startedAt, inSameDayAs: reminder.date)
                && activity.durationSecs > 0
        }
    }

    private func persistSchedule() {
        guard let data = try? JSONEncoder().encode(cachedWorkouts) else { return }
        defaults.set(data, forKey: Self.scheduleKey)
    }

    private func track(_ name: ProductEventName, properties: [ProductPropertyKey: AnalyticsValue] = [:]) {
        guard let analyticsManager else { return }
        Task { await analyticsManager.track(.init(name, properties: properties)) }
    }

    private static func identifier(for reminder: ScheduledWorkoutReminder) -> String {
        identifier(for: reminder.id)
    }

    private static func identifier(for reminderID: String) -> String {
        "\(identifierPrefix)\(reminderID)"
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func body(for reminder: ScheduledWorkoutReminder) -> String {
        let duration = max(1, Int(ceil(Double(reminder.durationSeconds) / 60.0)))
        let durationText = String(format: String(localized: "workout.reminder.duration", defaultValue: "%d minutes"), duration)
        return String(format: String(localized: "workout.reminder.body", defaultValue: "%@ planned today. Start whenever you’re ready."), durationText)
    }
}

struct WorkoutReminderSettingsView: View {
    @EnvironmentObject private var preferences: WorkoutReminderPreferences
    @EnvironmentObject private var scheduler: WorkoutNotificationScheduler
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var pushNotifications: PushNotificationCoordinator
    @State private var selectedTime = Date()

    var body: some View {
        Form {
            Section {
                Toggle(
                    String(localized: "workout.reminders.toggle", defaultValue: "Workout reminders"),
                    isOn: Binding(
                        get: { preferences.isEnabled },
                        set: { enabled in
                            Task {
                                if enabled {
                                    _ = await scheduler.requestPermissionAndEnable(
                                        preferences: preferences,
                                        activities: activityStore.activities
                                    )
                                    await pushNotifications.activate()
                                } else {
                                    await scheduler.disable(preferences: preferences)
                                }
                            }
                        }
                    )
                )
                DatePicker(
                    String(localized: "workout.reminders.time", defaultValue: "Reminder time"),
                    selection: $selectedTime,
                    displayedComponents: .hourAndMinute
                )
                .disabled(!preferences.isEnabled)
                .onChange(of: selectedTime) { _, value in
                    preferences.setTime(value)
                    Task {
                        await scheduler.reminderTimeChanged(
                            preferences: preferences,
                            activities: activityStore.activities
                        )
                    }
                }
            } header: {
                Text(String(localized: "workout.reminders.section", defaultValue: "Planned workouts"))
            } footer: {
                Text(String(localized: "workout.reminders.help", defaultValue: "Only planned workout days get a reminder. Rest days stay quiet."))
            }
        }
        .navigationTitle(String(localized: "workout.reminders.title", defaultValue: "Workout reminders"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            var components = DateComponents()
            components.hour = preferences.reminderHour
            components.minute = preferences.reminderMinute
            selectedTime = Calendar.current.date(from: components) ?? Date()
        }
    }
}

private extension ScheduledWorkoutReminder {
    func dateWithPreferredTime(preferences: WorkoutReminderPreferences, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.date(bySettingHour: preferences.reminderHour, minute: preferences.reminderMinute, second: 0, of: day) ?? date
    }
}
