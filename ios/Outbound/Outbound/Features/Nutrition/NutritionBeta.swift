import Combine
import CryptoKit
import Foundation
import OSLog
import SwiftUI

/// Qualitative-only beta: no eligibility, dietary needs, or nutrient intake is inferred.
enum NutritionText {
    static func value(_ key: String) -> String { String(localized: String.LocalizationValue(key), table: "Nutrition") }
}

enum NutritionPhase: String, Codable, CaseIterable, Identifiable {
    case before, during, after
    var id: String { rawValue }
    var title: String { NutritionText.value("phase.\(rawValue)") }
}

struct NutritionWorkoutContext: Identifiable {
    var id: String { linkage }
    var sport: SportType? = nil
    let linkage: String
    let title: String
    let date: Date
    let durationSeconds: Int?
    let isEndurance: Bool
    let phase: NutritionPhase

    static func planned(intent: SessionIntent, date: Date, planID: String?, calendar: Calendar) -> Self {
        let receipt = intent.workoutReference?.performedWorkoutReference
        let linkage = receipt.map { "plan:\($0.planVersionId):\($0.plannedWorkoutId)" }
            ?? "planned:\(planID ?? "daily"):\(intent.id):\(dayKey(date, calendar: calendar))"
        return .init(linkage: linkage, title: intent.title, date: date,
                     durationSeconds: intent.targetDurationSeconds ?? intent.estimatedDurationSeconds,
                     isEndurance: [.run, .bike, .swim].contains(intent.sport), phase: .before).withSport(intent.sport)
    }

    func withSport(_ sport: SportType?) -> Self { var copy = self; copy.sport = sport; return copy }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = formatter.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func scheduled(_ workout: TrainingPlanWorkout, display: TrainingPlanWorkout, calendar: Calendar) -> Self {
        .init(linkage: "scheduled:\(workout.id):\(workout.scheduledDateKey ?? "unscheduled")", title: BuiltinWorkoutText.localized(display.title),
              date: workout.scheduledDateKey.flatMap { PlanningCalendarContext.logicalDate($0, calendar: calendar) } ?? workout.scheduledDate ?? Date(), durationSeconds: display.durationSeconds,
              isEndurance: ["run", "bike", "swim"].contains(display.modality ?? ""), phase: .before).withSport(display.modality.flatMap(SportType.init(rawValue:)))
    }

    static func completed(_ activity: SavedActivity) -> Self {
        let linkage = activity.performedWorkoutReference.map { "plan:\($0.planVersionId):\($0.plannedWorkoutId)" } ?? "activity:\(activity.id.uuidString)"
        return .init(linkage: linkage, title: activity.title, date: activity.startedAt,
                     durationSeconds: activity.durationSecs, isEndurance: [.running, .cycling, .swimming].contains(activity.activityType), phase: .after).withSport(SportType(activityType: activity.activityType))
    }
}

/// v1 selects editorial advice; no clinical validation or numeric prescription is implied.
enum NutritionAdvice {
    static let ruleVersion = "qualitative-v1"
    static func keys(for context: NutritionWorkoutContext) -> [String] {
        guard context.isEndurance, let seconds = context.durationSeconds, seconds > 0 else {
            return [context.phase == .before ? "advice.general.before" : "advice.general.after"]
        }
        if context.phase == .after { return ["advice.recovery", "advice.recovery.timing"] }
        if seconds >= 90 * 60 { return ["advice.before", "advice.long"] }
        return ["advice.before", seconds < 45 * 60 ? "advice.short" : "advice.medium"]
    }
    static let sources: [(title: String, url: String, applicability: String)] = [
        ("source.victoria", "https://www.getactive.vic.gov.au/resources/what-to-eat-before-and-after-exercise/", "source.victoria.scope"),
        ("source.ais", "https://www.ausport.gov.au/ais/nutrition/supplements/group_a/sports-foods2/sports-drink/how-and-when-do-i-use-it", "source.ais.scope"),
        ("source.joint", "https://www.dietitians.ca/DietitiansOfCanada/media/Documents/Resources/noap-position-paper.pdf", "source.joint.scope"),
        ("source.issn", "https://doi.org/10.1186/s12970-017-0189-4", "source.issn.scope")
    ]
}

enum NutritionMeal: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var title: String { NutritionText.value("meal.\(rawValue)") }
    static func suggested(at date: Date, calendar: Calendar) -> Self {
        switch calendar.component(.hour, from: date) { case 5..<11: .breakfast; case 11..<15: .lunch; case 17..<22: .dinner; default: .snack }
    }
}

struct NutritionFoodLog: Codable, Identifiable {
    var id = UUID()
    var linkage: String?
    var workoutTitle: String?
    var workoutDate: Date?
    var phase: NutritionPhase?
    var consumedAt: Date
    var description: String
    var note: String
    // Additive optional fields preserve existing version-1 actual food records.
    var meal: NutritionMeal? = nil
    var portion: String? = nil
    var workoutSport: SportType? = nil
    var workoutDuration: Int? = nil
    var workoutIsEndurance: Bool? = nil

    var context: NutritionWorkoutContext? {
        guard let linkage, let workoutTitle, let workoutDate else { return nil }
        return NutritionWorkoutContext(sport: workoutSport, linkage: linkage, title: workoutTitle, date: workoutDate,
            durationSeconds: workoutDuration, isEndurance: workoutIsEndurance ?? false, phase: phase ?? .before)
    }
    mutating func associate(_ context: NutritionWorkoutContext?) {
        linkage = context?.linkage; workoutTitle = context?.title; workoutDate = context?.date
        phase = context?.phase; workoutSport = context?.sport; workoutDuration = context?.durationSeconds
        workoutIsEndurance = context?.isEndurance
    }
}

/// A fixed account snapshot prevents stale presentations from reading/writing another account.
@MainActor
final class NutritionLogStore: ObservableObject {
    @Published private(set) var entries: [NutritionFoodLog] = []
    @Published private(set) var failed = false
    private let account: ActivityAccountContext
    @Published private(set) var loaded = false
    private static let logger = Logger(subsystem: "plainstride.outbound", category: "NutritionLogStore")

    init(account: ActivityAccountContext) {
        self.account = account
        do {
            try ActivityAccountBoundary.validate(account)
            let url = try Self.fileURL(account: account)
            if FileManager.default.fileExists(atPath: url.path) {
                entries = try JSONDecoder().decode([NutritionFoodLog].self, from: Data(contentsOf: url))
            }
            loaded = true
        } catch { report(error, operation: "load") }
    }

    func save(_ entry: NutritionFoodLog) -> Bool {
        var updated = entries
        if let index = updated.firstIndex(where: { $0.id == entry.id }) { updated[index] = entry }
        else { updated.append(entry) }
        return persist(updated)
    }
    func delete(_ entry: NutritionFoodLog) -> Bool { persist(entries.filter { $0.id != entry.id }) }
    func reload() {
        do {
            try ActivityAccountBoundary.validate(account)
            let url = try Self.fileURL(account: account)
            entries = FileManager.default.fileExists(atPath: url.path) ? try JSONDecoder().decode([NutritionFoodLog].self, from: Data(contentsOf: url)) : []
            loaded = true
            failed = false
        } catch {
            loaded = false
            report(error, operation: "reload")
        }
    }
    private func persist(_ updated: [NutritionFoodLog]) -> Bool {
        do {
            try ActivityAccountBoundary.validate(account)
            guard loaded, account.owner != "guest" else { return false }
            let url = try Self.fileURL(account: account)
            try JSONEncoder().encode(updated).write(to: url, options: [.atomic, .completeFileProtection])
            entries = updated
            failed = false
            return true
        } catch { report(error, operation: "persist"); return false }
    }
    static func deleteAccountData(_ account: ActivityAccountContext) throws {
        try ActivityAccountBoundary.validate(account)
        do {
            let url = try fileURL(account: account)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        } catch {
            logger.error("Nutrition local account deletion failed; code=\((error as NSError).code, privacy: .public)")
            throw error
        }
    }
    private static func fileURL(account: ActivityAccountContext) throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var folder = root.appendingPathComponent("NutritionLogs-v1", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let digest = SHA256.hash(data: Data(account.owner.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(digest).appendingPathExtension("json")
    }
    private func report(_ error: Error, operation: String) {
        if error is CancellationError { return }
        failed = true
        // Only the numeric error code is safe; paths, food and account information are excluded.
        Self.logger.error("Nutrition local \(operation, privacy: .public) failed; code=\((error as NSError).code, privacy: .public)")
    }
}

/// Scene-owned, independent of entry/button identity and responsive layout candidates.
@MainActor
final class NutritionPresentationCoordinator: ObservableObject {
    let sheet = StableSheetPresenter()
    private var accountObservation: AnyCancellable?

    func present(context: NutritionWorkoutContext?, calendar: Calendar, opensJournal: Bool, guidanceFirst: Bool,
                 authStore: AuthStore, analytics: AnalyticsManager?) {
        guard let userID = authStore.user?.id else { return }
        let account = ActivityAccountBoundary.current
        let date = opensJournal ? Date() : context?.date ?? Date()
        var openingDismissal: StableSheetDismissal?
        let opened = sheet.present(diagnosticName: "nutrition_sheet", onDismiss: {
            self.accountObservation = nil
        }) { dismiss in
            openingDismissal = dismiss
            return NutritionJournalView(context: context, date: date, calendar: calendar, account: account,
                                 workoutOrigin: !opensJournal, guidanceFirst: guidanceFirst,
                                 onClose: { dismiss() })
                .environment(\.analyticsManager, analytics)
        }
        guard opened, let openingDismissal else { return }
        // The presenter's onDismiss callback retains this coordinator until cleanup.
        // This subscription survives removal of the originating card or scene content.
        accountObservation = authStore.$user.map { $0?.id }.removeDuplicates().sink { currentID in
            guard currentID != userID else { return }
            Task { @MainActor in openingDismissal() }
        }
    }
}

private struct NutritionPresentationRoot<Content: View>: View {
    @StateObject private var coordinator = NutritionPresentationCoordinator()
    let content: Content
    var body: some View {
        content
            .environmentObject(coordinator)
            .background {
                StableSheetPresentationHost(presenter: coordinator.sheet).frame(width: 0, height: 0)
            }
    }
}

extension View {
    /// Apply at the scene root, including debug detail routes and previews.
    func nutritionPresentationRoot() -> some View { NutritionPresentationRoot(content: self) }
}

struct NutritionBetaEntry: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var planStore: TrainingPlanStore
    @EnvironmentObject private var coordinator: NutritionPresentationCoordinator
    @Environment(\.outboundTheme) private var theme
    @Environment(\.analyticsManager) private var analyticsManager
    var context: NutritionWorkoutContext? = nil
    var opensJournal = false
    var opensGuidance = false
    var actionPresentation: OutboundSecondaryActionPresentation = .bordered
    private var calendar: Calendar { planStore.nutritionCalendar }

    var body: some View {
        if authStore.user?.id != nil {
            entryButton
            .tint(theme.accentColor)
            .onAppear { Task { await analyticsManager?.track(.init(.nutritionBetaExposed)) } }
        }
    }
    @ViewBuilder private var entryButton: some View {
        if opensJournal {
            Button(action: open) {
                OutboundCard {
                    HStack(spacing: OutboundSpacing.standard) {
                        Image(systemName: "fork.knife").foregroundStyle(theme.accentColor).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact / 2) {
                            Text(NutritionText.value("title")).font(.headline).foregroundStyle(.primary)
                            Text(NutritionText.value("entry_subtitle")).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }
            }.buttonStyle(.plain)
        } else {
            Button(action: open) {
                if actionPresentation == .cardText {
                    Text(NutritionText.value(opensGuidance ? "title" : "food_fueling"))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label(NutritionText.value(opensGuidance ? "title" : "food_fueling"), systemImage: "fork.knife")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.outboundSecondaryActionStyle(actionPresentation)
        }
    }
    private func open() {
        coordinator.present(context: context, calendar: calendar, opensJournal: opensJournal,
                            guidanceFirst: opensGuidance, authStore: authStore, analytics: analyticsManager)
    }
}

private enum NutritionJournalScope: String { case day, history, workout }

private struct NutritionJournalView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @StateObject private var store: NutritionLogStore
    @State private var date: Date
    @State private var editor: NutritionFoodLog?
    @State private var guidance: NutritionWorkoutContext?
    @State private var guidanceDraft: NutritionFoodLog?
    @State private var pendingDeletion: NutritionFoodLog?
    @State private var scope: NutritionJournalScope
    @State private var showsRootGuidance: Bool
    @State private var toast: String?
    let context: NutritionWorkoutContext?
    let calendar: Calendar
    let workoutOrigin: Bool
    let onClose: () -> Void

    init(context: NutritionWorkoutContext?, date: Date, calendar: Calendar, account: ActivityAccountContext, workoutOrigin: Bool, guidanceFirst: Bool = false, onClose: @escaping () -> Void) {
        self.context = context; self.calendar = calendar; self.workoutOrigin = workoutOrigin
        self.onClose = onClose
        _date = State(initialValue: min(date, Date()))
        _showsRootGuidance = State(initialValue: guidanceFirst && context != nil)
        _scope = State(initialValue: guidanceFirst && context != nil ? .workout : .day)
        _store = StateObject(wrappedValue: NutritionLogStore(account: account))
    }
    private var entries: [NutritionFoodLog] {
        store.entries.filter { entry in
            switch scope {
            case .day: calendar.isDate(entry.consumedAt, inSameDayAs: date)
            case .history: true
            case .workout: context.map { entry.linkage == $0.linkage } ?? false
            }
        }.sorted { $0.consumedAt > $1.consumedAt }
    }
    private var recent: [NutritionFoodLog] {
        var seen = Set<String>()
        return Array(store.entries.sorted { $0.consumedAt > $1.consumedAt }.filter {
            seen.insert($0.description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted
        }.prefix(5))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                if showsRootGuidance, let context {
                    VStack(alignment: .leading, spacing: OutboundSpacing.section) {
                        destinationHeader("guidance")
                        Button {
                            scope = .workout
                            showsRootGuidance = false
                            track(.nutritionHistoryViewed)
                        } label: { Label(NutritionText.value("journal"), systemImage: "book.closed") }
                            .nutritionSecondary()
                        NutritionGuidanceView(context: context, canLog: store.loaded) { linked, phase in
                            var entry = draft()
                            entry.associate(linked); entry.phase = phase
                            editor = entry
                        }
                    }.padding(OutboundSpacing.screen)
                } else {
                    diaryContent
                }
            }
            .background(OutboundPalette.background)
            .navigationTitle(NutritionText.value(showsRootGuidance ? "guidance" : "title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(NutritionText.value("done"), action: onClose) } }
            .sheet(item: $guidance, onDismiss: {
                if let draft = guidanceDraft { editor = draft; guidanceDraft = nil }
            }) { context in
                NavigationStack {
                    ScrollView { NutritionGuidanceView(context: context, canLog: store.loaded) { linked, phase in
                        var entry = draft()
                        entry.associate(linked); entry.phase = phase
                        guidanceDraft = entry; guidance = nil
                    }.padding(OutboundSpacing.screen) }
                        .background(OutboundPalette.background)
                        .navigationTitle(NutritionText.value("guidance"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(NutritionText.value("done")) { guidance = nil } } }
                }
                .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
            }
            .sheet(item: $editor) { entry in
                NutritionLogEditor(entry: entry, availableContext: context, calendar: calendar) { updated in
                    let success = store.save(updated)
                    if success { track(.nutritionLogSaved) }
                    return success
                }.environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
            }
            .confirmationDialog(NutritionText.value("delete_confirm"), isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
                Button(NutritionText.value("delete"), role: .destructive) {
                    if let entry = pendingDeletion {
                        if store.delete(entry) { track(.nutritionLogDeleted) } else { toast = NutritionText.value("storage_error") }
                    }
                    pendingDeletion = nil
                }
                Button(NutritionText.value("cancel"), role: .cancel) { pendingDeletion = nil }
            }
            .overlay(alignment: .top) { NutritionToast(message: toast) }
            .task(id: toast) { if toast != nil { try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { toast = nil } } }
            .task(id: showsRootGuidance) { if !showsRootGuidance { track(.nutritionJournalViewed) } }
        }.environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
    }
    private func destinationHeader(_ key: String) -> some View {
        HStack(alignment: .top) {
            Text(NutritionText.value(key)).font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)
            OutboundCornerRibbon(title: NutritionText.value("beta")).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(NutritionText.value(key)), \(NutritionText.value("beta"))")
        .accessibilityAddTraits(.isHeader)
    }
    private var diaryContent: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.section) {
            destinationHeader("journal")
            DatePicker(NutritionText.value("diary_date"), selection: $date, in: ...Date(), displayedComponents: .date)
                .onChange(of: date) { _, _ in scope = .day; track(.nutritionJournalDateChanged) }
            Text(NutritionText.value("privacy")).font(.footnote).foregroundStyle(.secondary)
            if let context {
                Button { guidance = context } label: {
                    OutboundCard {
                        HStack(spacing: OutboundSpacing.standard) {
                            Image(systemName: "fork.knife").accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: OutboundSpacing.compact / 2) {
                                Text(NutritionText.value("guidance")).font(.headline)
                                Text(context.title).font(.subheadline)
                                Text(context.date, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }
                }.buttonStyle(.plain)
            }
            OutboundPrimaryButton(title: NutritionText.value("add"), systemImage: "plus", expands: false) {
                editor = draft()
            }.disabled(!store.loaded)
            Picker(NutritionText.value("diary_scope"), selection: $scope) {
                Text(NutritionText.value("selected_date")).tag(NutritionJournalScope.day)
                Text(NutritionText.value("all_logs")).tag(NutritionJournalScope.history)
                if context != nil { Text(NutritionText.value("linked_logs")).tag(NutritionJournalScope.workout) }
            }.onChange(of: scope) { _, shown in if shown != .day { track(.nutritionHistoryViewed) } }
            if !store.loaded {
                Text(NutritionText.value("storage_error")).foregroundStyle(.secondary)
                Button(NutritionText.value("retry")) { store.reload() }.nutritionSecondary()
            }
            if scope != .day {
                // All-date history remains independent of mutable workouts and plans.
                let days = Set(entries.map { calendar.startOfDay(for: $0.consumedAt) }).sorted(by: >)
                if days.isEmpty { Text(NutritionText.value("meal.empty")).foregroundStyle(.secondary) }
                ForEach(days, id: \.self) { day in
                    Text(day, format: .dateTime.year().month().day()).font(.title3.bold())
                    ForEach(entries.filter { calendar.isDate($0.consumedAt, inSameDayAs: day) }) { entry in logCard(entry) }
                }
            } else {
                ForEach(NutritionMeal.allCases) { meal in
                    VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                        Text(meal.title).font(.title3.bold())
                        let meals = entries.filter { ($0.meal ?? NutritionMeal.suggested(at: $0.consumedAt, calendar: calendar)) == meal }
                        if meals.isEmpty { Text(NutritionText.value("meal.empty")).font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(meals) { entry in logCard(entry) }
                    }
                }
            }
            if !recent.isEmpty {
                Text(NutritionText.value("recent")).font(.title3.bold())
                Text(NutritionText.value("repeat_hint")).font(.footnote).foregroundStyle(.secondary)
                ForEach(recent) { entry in
                    Button {
                        var copy = draft()
                        copy.description = entry.description; copy.portion = entry.portion
                        editor = copy; track(.nutritionFoodRepeated)
                    } label: { Label(entry.description, systemImage: "arrow.counterclockwise") }.nutritionSecondary().disabled(!store.loaded)
                }
            }
        }.padding(OutboundSpacing.screen)
    }
    private func draft(meal: NutritionMeal? = nil) -> NutritionFoodLog {
        let now = Date()
        let time = calendar.dateComponents([.hour, .minute], from: now)
        let consumed = min(calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0, of: date) ?? date, now)
        var entry = NutritionFoodLog(consumedAt: consumed, description: "", note: "", meal: meal ?? .suggested(at: consumed, calendar: calendar))
        if workoutOrigin { entry.associate(context) }
        return entry
    }
    private func logCard(_ entry: NutritionFoodLog) -> some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
            HStack(alignment: .top, spacing: OutboundSpacing.standard) {
                VStack(alignment: .leading, spacing: OutboundSpacing.compact / 2) {
                    Text(entry.description).font(.headline)
                    if let portion = entry.portion, !portion.isEmpty { Text(portion).font(.subheadline).foregroundStyle(.secondary) }
                    Text(entry.consumedAt, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    Button(NutritionText.value("edit")) { editor = entry }
                    Button(NutritionText.value("delete"), role: .destructive) { pendingDeletion = entry }
                } label: {
                    Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(NutritionText.value("record_actions"))
                .disabled(!store.loaded)
            }
            if !entry.note.isEmpty { Text(entry.note).font(.subheadline) }
            if let linked = entry.context {
                Button { guidance = linked } label: {
                    HStack(alignment: .top, spacing: OutboundSpacing.compact) {
                        Image(systemName: "link").accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact / 2) {
                            Text(linked.title)
                            Text(linked.date, format: .dateTime.year().month().day())
                            if let phase = entry.phase { Text(phase.title) }
                        }.fixedSize(horizontal: false, vertical: true)
                    }.font(.caption)
                }
                .nutritionSecondary()
                .accessibilityHint(NutritionText.value("guidance"))
            }
        }
        .padding(.vertical, OutboundSpacing.compact)
    }
    private func track(_ name: ProductEventName) { Task { await analyticsManager?.track(.init(name)) } }
}

private struct NutritionContextSummary: View {
    let context: NutritionWorkoutContext
    var body: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
            Text(context.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(context.date, format: .dateTime.year().month().day()).font(.subheadline).foregroundStyle(.secondary)
            if let sport = context.sport { Label(sport.displayName, systemImage: sport.systemImage).font(.subheadline) }
            if let duration = context.durationSeconds, duration > 0 {
                Text(Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .wide))).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct NutritionGuidanceView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsSources = false
    @State private var expandedPhases: Set<String> = []
    let context: NutritionWorkoutContext
    var canLog = true
    let onLog: (NutritionWorkoutContext, NutritionPhase) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.section) {
            NutritionContextSummary(context: context)
            Text(NutritionText.value("advice_not_logs")).font(.footnote).foregroundStyle(.secondary)
            ForEach(NutritionPhase.allCases) { phase in
                let presentation = NutritionAdvicePresentation.selected(for: phase, context: context)
                OutboundCard {
                    VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                        Text(phase.title).font(.title3.bold())
                        adviceContent(presentation)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: OutboundSpacing.standard) {
                                explanationButton(phase).fixedSize(horizontal: true, vertical: false)
                                Spacer(minLength: OutboundSpacing.compact)
                                logButton(phase).fixedSize(horizontal: true, vertical: false)
                            }
                            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                explanationButton(phase)
                                logButton(phase)
                            }
                        }
                        if expandedPhases.contains(phase.rawValue) {
                            ForEach(detailKeys(phase), id: \.self) { key in
                                Text(NutritionText.value(key)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            Text(NutritionText.value("limitation")).font(.footnote).foregroundStyle(.secondary)
            DisclosureGroup(isExpanded: $showsSources) {
                VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                    Text(NutritionText.value("rationale"))
                    Text(NutritionText.value(context.isEndurance && (context.durationSeconds ?? 0) > 0 ? "context.known" : "context.general"))
                    ForEach(NutritionAdvice.sources, id: \.url) { source in
                        if let url = URL(string: source.url) {
                            Link(NutritionText.value(source.title), destination: url).frame(minHeight: 44, alignment: .leading)
                            Text(NutritionText.value(source.applicability)).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Text(NutritionText.value("version")).font(.caption).foregroundStyle(.secondary)
                }.padding(.top, OutboundSpacing.standard)
            } label: { Text(NutritionText.value("sources")) }
                .onChange(of: showsSources) { _, expanded in if expanded { track(.nutritionAdviceExplained) } }
        }.task { track(.nutritionAdviceViewed) }
    }
    @ViewBuilder private func adviceContent(_ presentation: NutritionAdvicePresentation) -> some View {
        if let asset = presentation.photoAsset {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: OutboundSpacing.compact))
                : AnyLayout(HStackLayout(alignment: .top, spacing: OutboundSpacing.standard))
            layout {
                actionText(presentation).frame(maxWidth: .infinity, alignment: .leading)
                Image(asset)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
            }
        } else { actionText(presentation).frame(maxWidth: .infinity, alignment: .leading) }
    }
    private func actionText(_ presentation: NutritionAdvicePresentation) -> some View {
        Text(NutritionText.value(presentation.actionKey)).font(.body).fixedSize(horizontal: false, vertical: true)
    }
    private func explanationButton(_ phase: NutritionPhase) -> some View {
        Button {
            if expandedPhases.remove(phase.rawValue) == nil {
                expandedPhases.insert(phase.rawValue)
                track(.nutritionAdviceExplained)
            }
        } label: {
            HStack(spacing: OutboundSpacing.compact / 2) {
                Text(NutritionText.value("why")).fixedSize(horizontal: false, vertical: true)
                Image(systemName: expandedPhases.contains(phase.rawValue) ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
            .font(.subheadline)
            .outboundTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityValue(NutritionText.value(expandedPhases.contains(phase.rawValue) ? "expanded" : "collapsed"))
    }
    private func logButton(_ phase: NutritionPhase) -> some View {
        OutboundPrimaryButton(title: NutritionText.value("log"), expands: false, compact: true) { onLog(context, phase) }
            .accessibilityLabel(NutritionText.value("add"))
            .disabled(!canLog)
    }
    private var supported: Bool { context.isEndurance && (context.durationSeconds ?? 0) > 0 }
    private func detailKeys(_ phase: NutritionPhase) -> [String] {
        if phase == .during { return [supported ? "advice.during" : "advice.general.during"] }
        let copy = NutritionWorkoutContext(sport: context.sport, linkage: context.linkage, title: context.title, date: context.date, durationSeconds: context.durationSeconds, isEndurance: context.isEndurance, phase: phase)
        return NutritionAdvice.keys(for: copy)
    }
    private func track(_ name: ProductEventName) { Task { await analyticsManager?.track(.init(name)) } }
}

private struct NutritionLogEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analyticsManager
    @State var entry: NutritionFoodLog
    @State private var toast: String?
    let availableContext: NutritionWorkoutContext?
    let calendar: Calendar
    let onSave: (NutritionFoodLog) -> Bool
    private var valid: Bool { !entry.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && entry.consumedAt <= Date() }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(NutritionText.value("description"), text: $entry.description, axis: .vertical).lineLimit(2...5)
                    TextField(NutritionText.value("portion"), text: Binding(get: { entry.portion ?? "" }, set: { entry.portion = $0 }))
                    TextField(NutritionText.value("note"), text: $entry.note, axis: .vertical).lineLimit(2...4)
                    DatePicker(NutritionText.value("consumed_at"), selection: $entry.consumedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    Picker(NutritionText.value("meal"), selection: Binding(get: { entry.meal ?? .suggested(at: entry.consumedAt, calendar: calendar) }, set: { entry.meal = $0 })) {
                        ForEach(NutritionMeal.allCases) { meal in Text(meal.title).tag(meal) }
                    }
                } footer: { Text(NutritionText.value("actual_only")) }
                Section {
                    if let linked = entry.context {
                        NutritionContextSummary(context: linked)
                        Picker(NutritionText.value("phase"), selection: Binding(get: { entry.phase ?? .before }, set: { entry.phase = $0 })) {
                            ForEach(NutritionPhase.allCases) { phase in Text(phase.title).tag(phase) }
                        }
                        Button(NutritionText.value("unlink")) { entry.associate(nil); trackAssociation() }.nutritionSecondary()
                    } else {
                        Text(NutritionText.value("unlinked")).foregroundStyle(.secondary)
                        if let availableContext {
                            NutritionContextSummary(context: availableContext)
                            Button(NutritionText.value("link")) { entry.associate(availableContext); trackAssociation() }.nutritionSecondary()
                        }
                    }
                } footer: { Text(NutritionText.value("association_hint")) }
            }
            .navigationTitle(NutritionText.value("log_title"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(NutritionText.value("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NutritionText.value("save")) {
                        entry.description = entry.description.trimmingCharacters(in: .whitespacesAndNewlines)
                        if onSave(entry) { dismiss() } else { toast = NutritionText.value("storage_error") }
                    }.disabled(!valid)
                }
            }
            .overlay(alignment: .top) { NutritionToast(message: toast) }
            .task(id: toast) { if toast != nil { try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { toast = nil } } }
        }
    }
    private func trackAssociation() { Task { await analyticsManager?.track(.init(.nutritionAssociationChanged)) } }
}

private struct NutritionToast: View {
    let message: String?
    var body: some View {
        if let message {
            Text(message).font(.subheadline).padding(OutboundSpacing.standard)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
                .padding(OutboundSpacing.screen).accessibilityAddTraits(.updatesFrequently)
        }
    }
}

private extension View {
    func nutritionSecondary() -> some View {
        buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control)).frame(minHeight: 44)
    }
}
