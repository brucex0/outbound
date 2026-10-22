import Foundation
import SwiftUI

struct AccountStatisticsSnapshot: Codable {
    let algorithmVersion: Int
    let revision: Int
    let computedAt: Date
    let timeZone: String
    let firstWeekday: Int
    let status: String
    let all: ProgressStatsSnapshot
    let sports: [String: ProgressStatsSnapshot]
    let lifetime: ProgressPeriodTotals
    let currentWeek: ProgressPeriodTotals
    let weekStart: Date
    let weekEnd: Date
    let gear: [String: GearTotals]
    let outboundActivityCount: Int
    struct GearTotals: Codable { let distanceMeters: Double; let lastUsedAt: Date? }
}

struct AccountStatisticsStatus: View {
    @ObservedObject var store: ActivityStore
    var body: some View {
        if AuthStore.currentUserId != nil {
            if store.accountStatistics == nil && store.statisticsIsLoading {
                ProgressView(String(localized: "statistics.loading", defaultValue: "Loading your statistics…"))
            } else if store.accountStatistics == nil {
                ContentUnavailableView {
                    Label(String(localized: "statistics.unavailable.title", defaultValue: "Statistics unavailable"), systemImage: "chart.bar")
                } description: {
                    Text(String(localized: "statistics.unavailable.message", defaultValue: "Connect to load your complete account statistics."))
                } actions: {
                    Button(String(localized: "common.retry", defaultValue: "Retry")) { Task { await store.refreshAccountStatistics() } }
                }
            } else if store.statisticsAreCached || store.pendingActivityCount > 0 {
                Text(store.pendingActivityCount > 0
                     ? String(localized: "statistics.pending", defaultValue: "Some activity changes are pending sync. Totals reflect the last complete server update.")
                     : String(localized: "statistics.cached", defaultValue: "Showing your last complete statistics update."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
