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
    case before, after
    var id: String { rawValue }
    var title: String { NutritionText.value("phase.\(rawValue)") }
}

struct NutritionWorkoutContext {
    let linkage: String
    let title: String
    let date: Date
    let durationSeconds: Int?
    let isEndurance: Bool
    let phase: NutritionPhase

    static func planned(intent: SessionIntent, date: Date, planID: String?) -> Self {
        let receipt = intent.workoutReference?.performedWorkoutReference
        let linkage = receipt.map { "plan:\($0.planVersionId):\($0.plannedWorkoutId)" }
            ?? "planned:\(planID ?? "daily"):\(intent.id):\(dayKey(date))"
        return .init(linkage: linkage, title: intent.title, date: date,
                     durationSeconds: intent.targetDurationSeconds ?? intent.estimatedDurationSeconds,
                     isEndurance: [.run, .bike, .swim].contains(intent.sport), phase: .before)
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = PlanningCalendarContext.accountCalendar()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = formatter.calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func scheduled(_ workout: TrainingPlanWorkout, display: TrainingPlanWorkout) -> Self {
        .init(linkage: "scheduled:\(workout.id):\(workout.scheduledDateKey ?? "unscheduled")", title: BuiltinWorkoutText.localized(display.title),
              date: workout.logicalScheduledDate ?? Date(), durationSeconds: display.durationSeconds,
              isEndurance: ["run", "bike", "swim"].contains(display.modality ?? ""), phase: .before)
    }

    static func completed(_ activity: SavedActivity) -> Self {
        let linkage = activity.performedWorkoutReference.map { "plan:\($0.planVersionId):\($0.plannedWorkoutId)" } ?? "activity:\(activity.id.uuidString)"
        return .init(linkage: linkage, title: activity.title, date: activity.startedAt,
                     durationSeconds: activity.durationSecs, isEndurance: [.running, .cycling, .swimming].contains(activity.activityType), phase: .after)
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

struct NutritionFoodLog: Codable, Identifiable {
    var id = UUID()
    let linkage: String
    let workoutTitle: String
    let workoutDate: Date
    var phase: NutritionPhase
    var consumedAt: Date
    var description: String
    var note: String
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

struct NutritionBetaEntry: View {
    @EnvironmentObject private var authStore: AuthStore
    @Environment(\.outboundTheme) private var theme
    @Environment(\.analyticsManager) private var analyticsManager
    private struct Presentation: Identifiable {
        let id = UUID()
        let context: NutritionWorkoutContext
        let account: ActivityAccountContext
    }
    @State private var presentation: Presentation?
    let context: NutritionWorkoutContext

    var body: some View {
        if authStore.user?.id != nil {
            Button { presentation = .init(context: context, account: ActivityAccountBoundary.current) } label: {
                HStack(spacing: OutboundSpacing.compact) {
                    Label(NutritionText.value("title"), systemImage: "fork.knife")
                        .fixedSize(horizontal: false, vertical: true)
                    OutboundCornerRibbon(title: NutritionText.value("beta"))
                        .hidden()
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(NutritionText.value("entry"))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))
            .tint(theme.accentColor)
            .overlay(alignment: .topTrailing) {
                OutboundCornerRibbon(title: NutritionText.value("beta"))
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            .frame(minHeight: 44)
            .sheet(item: $presentation) { item in
                NutritionBetaView(context: item.context, account: item.account)
            }
            .onChange(of: authStore.user?.id) { _, _ in presentation = nil }
            .onAppear {
                Task { await analyticsManager?.track(.init(.nutritionBetaExposed)) }
            }
        }
    }
}

private struct NutritionBetaView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analyticsManager
    @StateObject private var store: NutritionLogStore
    @State private var editor: NutritionFoodLog?
    @State private var pendingDeletion: NutritionFoodLog?
    @State private var showsAllLogs = false
    @State private var showsSources = false
    let context: NutritionWorkoutContext

    init(context: NutritionWorkoutContext, account: ActivityAccountContext) {
        self.context = context
        _store = StateObject(wrappedValue: NutritionLogStore(account: account))
    }
    private var visibleEntries: [NutritionFoodLog] {
        store.entries.filter { showsAllLogs || $0.linkage == context.linkage }.sorted { $0.consumedAt > $1.consumedAt }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OutboundSpacing.section) {
                    HStack(alignment: .top, spacing: OutboundSpacing.standard) {
                        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                            Text(context.title).font(.title2.weight(.bold))
                            Text(context.date, format: .dateTime.year().month().day()).foregroundStyle(.secondary)
                            Text(context.phase.title).font(.headline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        OutboundCornerRibbon(title: NutritionText.value("beta"))
                            .hidden()
                            .accessibilityHidden(true)
                    }
                    .overlay(alignment: .topTrailing) {
                        OutboundCornerRibbon(title: NutritionText.value("beta"))
                    }
                    OutboundCard {
                        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                            ForEach(NutritionAdvice.keys(for: context), id: \.self) { key in
                                Text(NutritionText.value(key)).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Text(NutritionText.value("limitation")).font(.footnote).foregroundStyle(.secondary)
                    DisclosureGroup(isExpanded: $showsSources) {
                        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                            Text(NutritionText.value("rationale"))
                            Text(NutritionText.value(context.isEndurance && (context.durationSeconds ?? 0) > 0 ? "context.known" : "context.general"))
                            ForEach(NutritionAdvice.sources, id: \.url) { source in
                                VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                                    if let url = URL(string: source.url) { Link(NutritionText.value(source.title), destination: url).frame(minHeight: 44, alignment: .leading) }
                                    Text(NutritionText.value(source.applicability)).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Text(NutritionText.value("version")).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.top, OutboundSpacing.standard)
                    } label: { Text(NutritionText.value("why")) }
                    .onChange(of: showsSources) { _, expanded in
                        if expanded { track(.nutritionAdviceExplained) }
                    }
                    VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                        Text(NutritionText.value("logs")).font(.title2.weight(.semibold))
                        Text(NutritionText.value("privacy")).font(.footnote).foregroundStyle(.secondary)
                        OutboundPrimaryButton(title: NutritionText.value("add"), systemImage: "plus", expands: false) {
                            editor = .init(linkage: context.linkage, workoutTitle: context.title, workoutDate: context.date,
                                           phase: context.phase, consumedAt: Date(), description: "", note: "")
                        }
                        .disabled(!store.loaded)
                        Toggle(NutritionText.value("all_logs"), isOn: $showsAllLogs)
                        if store.failed {
                            Text(NutritionText.value("storage_error")).foregroundStyle(.secondary)
                            Button(NutritionText.value("retry")) { store.reload() }.frame(minHeight: 44)
                        } else if visibleEntries.isEmpty {
                            Text(NutritionText.value("empty")).foregroundStyle(.secondary)
                        }
                        ForEach(visibleEntries) { entry in logCard(entry) }
                    }
                }
                .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle(NutritionText.value("title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(NutritionText.value("done")) { dismiss() } } }
            .sheet(item: $editor) { entry in
                NutritionLogEditor(entry: entry) { updated in
                    let success = store.save(updated)
                    if success { track(.nutritionLogSaved) }
                    return success
                }
            }
            .confirmationDialog(NutritionText.value("delete_confirm"), isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), titleVisibility: .visible) {
                Button(NutritionText.value("delete"), role: .destructive) {
                    if let entry = pendingDeletion, store.delete(entry) { track(.nutritionLogDeleted) }
                    pendingDeletion = nil
                }
                Button(NutritionText.value("cancel"), role: .cancel) { pendingDeletion = nil }
            }
            .task { track(.nutritionAdviceViewed) }
        }
    }
    private func logCard(_ entry: NutritionFoodLog) -> some View {
        OutboundCard {
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                Text(entry.description).font(.headline)
                Text(entry.phase.title).font(.subheadline)
                Text(entry.consumedAt, format: .dateTime.year().month().day().hour().minute()).font(.subheadline).foregroundStyle(.secondary)
                if !entry.note.isEmpty { Text(entry.note) }
                if showsAllLogs {
                    Text(entry.workoutTitle).font(.footnote).foregroundStyle(.secondary)
                    Text(entry.workoutDate, format: .dateTime.year().month().day()).font(.footnote).foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack { logActions(entry) }
                    VStack(alignment: .leading) { logActions(entry) }
                }
                .disabled(!store.loaded)
            }
        }
    }
    @ViewBuilder private func logActions(_ entry: NutritionFoodLog) -> some View {
        Button(NutritionText.value("edit")) { editor = entry }
            .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control)).frame(minHeight: 44)
        Button(NutritionText.value("delete"), role: .destructive) { pendingDeletion = entry }
            .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control)).frame(minHeight: 44)
    }
    private func track(_ name: ProductEventName) { Task { await analyticsManager?.track(.init(name)) } }
}

private struct NutritionLogEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: NutritionFoodLog
    @State private var saveFailed = false
    let onSave: (NutritionFoodLog) -> Bool
    private var valid: Bool { !entry.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(NutritionText.value("description"), text: $entry.description, axis: .vertical)
                        .lineLimit(2...5)
                    TextField(NutritionText.value("note"), text: $entry.note, axis: .vertical)
                        .lineLimit(2...4)
                    DatePicker(NutritionText.value("consumed_at"), selection: $entry.consumedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    Picker(NutritionText.value("phase"), selection: $entry.phase) {
                        ForEach(NutritionPhase.allCases) { phase in Text(phase.title).tag(phase) }
                    }
                } footer: { Text(NutritionText.value("actual_only")) }
                if saveFailed { Section { Text(NutritionText.value("storage_error")) } }
            }
            .navigationTitle(NutritionText.value("log_title"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(NutritionText.value("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NutritionText.value("save")) {
                        entry.description = entry.description.trimmingCharacters(in: .whitespacesAndNewlines)
                        if onSave(entry) { dismiss() } else { saveFailed = true }
                    }.disabled(!valid)
                }
            }
        }
    }
}
