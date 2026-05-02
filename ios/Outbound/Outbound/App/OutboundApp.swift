import SwiftUI

@main
struct OutboundApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var authStore = AuthStore()
    @StateObject private var coachStore = CoachStore()
    @StateObject private var coachCatalogStore = CoachCatalogStore()
    @StateObject private var activityStore = ActivityStore()
    @StateObject private var goalStore = GoalStore()
    @StateObject private var healthAuthorizationStore = HealthAuthorizationStore()
    @StateObject private var healthImportStore = HealthImportStore()
    @StateObject private var dailyCheckInStore = DailyCheckInStore()
    @StateObject private var musicStore = MusicStore()

    init() {
        FirebaseBootstrap.configureIfAvailable()
    }

    var body: some Scene {
        WindowGroup {
            if authStore.isAuthenticated {
                MainTabView()
                    .environmentObject(authStore)
                    .environmentObject(coachStore)
                    .environmentObject(coachCatalogStore)
                    .environmentObject(activityStore)
                    .environmentObject(goalStore)
                    .environmentObject(healthAuthorizationStore)
                    .environmentObject(healthImportStore)
                    .environmentObject(dailyCheckInStore)
                    .environmentObject(musicStore)
                    .task {
                        await coachStore.syncIfNeeded()
                        await healthAuthorizationStore.refresh()
                        await healthImportStore.refreshRecentWorkouts()
                        await musicStore.refresh()
                    }
                    .onOpenURL { url in
                        _ = authStore.handleOpenURL(url)
                    }
            } else {
                AuthView()
                    .environmentObject(authStore)
                    .onOpenURL { url in
                        _ = authStore.handleOpenURL(url)
                    }
            }
        }
    }
}

enum DailyReadiness: String, Codable, CaseIterable, Identifiable {
    case lowEnergy = "Low energy"
    case okay = "Okay"
    case ready = "Ready"
    case stressed = "Stressed"

    var id: String { rawValue }

    var summaryLabel: String { "Today: \(rawValue)" }
}

struct DailyCheckInEntry: Codable, Equatable {
    let dayStamp: Date
    let readiness: DailyReadiness
}

@MainActor
final class DailyCheckInStore: ObservableObject {
    @Published private(set) var todayEntry: DailyCheckInEntry?

    private let defaults: UserDefaults
    private let entryKey = "daily_check_in_entry_v1"
    private let calendar: Calendar

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.calendar = calendar

        if let data = defaults.data(forKey: entryKey),
           let decoded = try? JSONDecoder().decode(DailyCheckInEntry.self, from: data),
           calendar.isDateInToday(decoded.dayStamp) {
            todayEntry = decoded
        } else {
            todayEntry = nil
        }
    }

    var readiness: DailyReadiness? {
        todayEntry?.readiness
    }

    func select(_ readiness: DailyReadiness, now: Date = Date()) {
        let entry = DailyCheckInEntry(
            dayStamp: calendar.startOfDay(for: now),
            readiness: readiness
        )
        todayEntry = entry

        guard let data = try? JSONEncoder().encode(entry) else { return }
        defaults.set(data, forKey: entryKey)
    }

    func refresh(now: Date = Date()) {
        guard let entry = todayEntry else { return }
        if !calendar.isDate(entry.dayStamp, inSameDayAs: now) {
            todayEntry = nil
            defaults.removeObject(forKey: entryKey)
        }
    }
}
