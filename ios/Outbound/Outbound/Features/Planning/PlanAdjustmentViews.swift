import SwiftUI

func planAdjustText(_ key: String) -> String { String(localized: String.LocalizationValue("plan.adjust." + key), table: "PlanAdjustments") }

struct PlanAvailabilityDTO: Codable, Equatable {
    var paused: Bool?
    var pausedOn: String?
    var reminderDate: String?
    var unavailableFrom: String?
    var unavailableThrough: String?
    var availableDays: [Int]?

    func advice(at date: Date, calendar: Calendar) -> String? {
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: date)
        if paused == true && today >= (pausedOn ?? "") { return planAdjustText("today_paused") }
        if let from = unavailableFrom, let through = unavailableThrough, today >= from, today <= through,
           !(availableDays ?? []).contains(calendar.component(.weekday, from: date)) { return planAdjustText("today_unavailable") }
        return nil
    }
}
struct PlanChangeWorkoutDTO: Codable, Identifiable, Equatable {
    let id: String
    let date: String
    let title: String
    let durationSeconds: Int
    let optional: Bool
    let status: String
}
struct PlanChangeContextDTO: Decodable {
    let planId: String
    let today: String
    let timeZone: String
    let workouts: [PlanChangeWorkoutDTO]
    let availability: PlanAvailabilityDTO
    let undoCommandId: String?
}
struct PlanChangeRequestDTO: Encodable {
    let planId: String
    let idempotencyKey: String
    let reason: String?
    let change: Change
    struct Change: Encodable {
        var operation: String
        var workoutId: String? = nil
        var toDate: String? = nil
        var fromDate: String? = nil
        var throughDate: String? = nil
        var availableDays: [Int]? = nil
        var reminderDate: String? = nil
        var commandId: String? = nil
        enum CodingKeys: String, CodingKey { case operation, workoutId, toDate, fromDate, throughDate, availableDays, reminderDate, commandId }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(operation, forKey: .operation)
            try c.encodeIfPresent(workoutId, forKey: .workoutId); try c.encodeIfPresent(toDate, forKey: .toDate)
            try c.encodeIfPresent(commandId, forKey: .commandId)
            if operation == "availability" {
                try c.encode(fromDate, forKey: .fromDate); try c.encode(throughDate, forKey: .throughDate)
                try c.encode(availableDays ?? [], forKey: .availableDays)
            }
            if operation == "pause" { try c.encode(fromDate, forKey: .fromDate); try c.encode(reminderDate, forKey: .reminderDate) }
        }
    }
}
struct PlanChangePreviewDTO: Decodable {
    let previewId: String
    let operation: String
    let expiresAt: String
    let applied: Bool
    let before: [PlanChangeWorkoutDTO]
    let after: [PlanChangeWorkoutDTO]
    let availability: PlanAvailabilityDTO
}
struct PlanChangeApplyRequestDTO: Encodable { let previewId: String; let idempotencyKey: String }

/// All schedule rows in the review come from the server; drafting alone never changes a plan.
struct PlanAdjustmentSheet: View {
    @EnvironmentObject private var store: TrainingPlanStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.analyticsManager) private var analytics
    let plan: ActiveTrainingPlan
    let onApplied: () -> Void
    @State private var context: PlanChangeContextDTO?
    @State private var action: String?
    @State private var preview: PlanChangePreviewDTO?
    @State private var previewKey = UUID().uuidString
    @State private var selectedWorkout = ""
    @State private var moveDate = Date()
    @State private var fromDate = Date()
    @State private var throughDate = Date()
    @State private var reminderDate = Date()
    @State private var hasReminder = false
    @State private var availableDays: Set<Int> = [2, 4, 6]
    @State private var reason = "none"
    @State private var readyToResume = false
    @State private var moreOptions = false
    @State private var showsEventEditor = false
    @State private var busy = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    private struct Draft {
        let workout: String; let move: Date; let from: Date; let through: Date
        let reminder: Date; let hasReminder: Bool; let days: Set<Int>; let reason: String; let ready: Bool
    }
    @State private var drafts: [String: Draft] = [:]

    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; value.locale = locale; return value }
    private var minimumDate: Date { context.flatMap { Self.date($0.today) } ?? calendar.startOfDay(for: Date()) }
    private var workouts: [PlanChangeWorkoutDTO] { context?.workouts.filter { $0.status == "planned" && !$0.optional } ?? [] }
    private var isPaused: Bool { context?.availability.paused == true }
    private var activelyPaused: Bool { isPaused && (availability?.pausedOn ?? "") <= (context?.today ?? "") }
    private var availability: PlanAvailabilityDTO? { context?.availability }
    private var canPreview: Bool {
        guard context != nil, let action else { return false }
        if action == "move" { return !selectedWorkout.isEmpty && workouts.first(where: { $0.id == selectedWorkout })?.date != dateKey(moveDate) }
        if action == "availability" { return throughDate >= fromDate }
        if action == "pause" || action == "edit_pause" { return !hasReminder || reminderDate >= fromDate }
        if action == "resume" { return readyToResume }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OutboundSpacing.section) {
                    Text(plan.localizedTitle).font(.title3.bold())
                    if let preview { previewContent(preview) }
                    else if let action { configuration(action) }
                    else if context != nil { menu }
                    else if busy { ProgressView(planAdjustText("loading")) }
                    else { Text(planAdjustText("load_failed")).foregroundStyle(.secondary); Button(planAdjustText("retry")) { Task { await loadContext() } }.buttonStyle(.bordered).frame(minHeight: 44) }
                }
                .padding(OutboundSpacing.screen)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(OutboundPalette.background)
            .navigationTitle(planAdjustText(preview != nil ? "review_title" : action ?? "title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Let the navigation bar provide its native button chrome without a second bordered surface.
                ToolbarItem(placement: .cancellationAction) {
                    if action != nil || preview != nil {
                        Button(planAdjustText("back")) { goBack() }.disabled(busy)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button(planAdjustText("cancel")) { dismiss() }.disabled(busy) }
            }
            .safeAreaInset(edge: .bottom) {
                if action != nil {
                    HStack(spacing: OutboundSpacing.standard) {
                        if busy { ProgressView().accessibilityLabel(planAdjustText("saving")) }
                        OutboundPrimaryButton(title: planAdjustText(preview == nil ? "preview" : "apply"), expands: false) {
                            Task { if preview == nil { await createPreview() } else { await apply() } }
                        }.disabled(busy || (preview == nil && !canPreview))
                        Spacer(minLength: 0)
                    }.padding(OutboundSpacing.standard).background(OutboundPalette.background)
                }
            }
            .disabled(busy)
            .interactiveDismissDisabled(busy)
            .overlay(alignment: .top) {
                if let toast { Text(toast).font(.subheadline).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: OutboundRadius.control)).padding().accessibilityAddTraits(.updatesFrequently).allowsHitTesting(false) }
            }
            .sheet(isPresented: $showsEventEditor, onDismiss: { Task { await loadContext() } }) {
                if let goal = (store.activePlan?.id == plan.id ? store.activePlan?.raceGoal : plan.raceGoal) { NavigationStack { RaceGoalEditor(goal: goal) } }
            }
            .task { await loadContext() }
            .onDisappear { toastTask?.cancel() }
        }
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
            Text(planAdjustText("menu_detail")).font(.body).foregroundStyle(.secondary)
            if isPaused {
                Text(String(format: planAdjustText(availability?.pausedOn.map { $0 > (context?.today ?? "") } == true ? "pause_scheduled" : "paused_since"), dateLabel(availability?.pausedOn ?? ""))).font(.headline)
                if let reminder = availability?.reminderDate { Text(String(format: planAdjustText("reminder_summary"), dateLabel(reminder))).font(.subheadline).foregroundStyle(.secondary) }
                actionButton("edit_pause", image: "pencil")
                actionButton("resume", image: "play.fill")
            }
            actionButton("move", image: "calendar")
            actionButton("availability", image: "calendar.badge.clock")
            if !isPaused { actionButton("pause", image: "pause.fill") }
            if let start = availability?.unavailableFrom, let end = availability?.unavailableThrough, end >= (context?.today ?? "") {
                OutboundCard {
                    VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                        Text(String(format: planAdjustText("availability_summary"), dateLabel(start), dateLabel(end))).font(.subheadline.weight(.semibold))
                        Button(planAdjustText("end_adjustment")) { choose("end") }.buttonStyle(.bordered).frame(minHeight: 44)
                    }
                }
            }
            if context?.undoCommandId != nil { actionButton("undo", image: "arrow.uturn.backward") }
            DisclosureGroup(planAdjustText("more"), isExpanded: $moreOptions) {
                VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                    actionButton("rebuild", image: "arrow.clockwise")
                    if plan.raceGoal?.editable == true {
                        Button { showsEventEditor = true } label: { Label(planAdjustText("event"), systemImage: "flag.checkered").frame(minHeight: 44) }.buttonStyle(.bordered)
                    }
                }.padding(.top, OutboundSpacing.standard)
            }.font(.subheadline.weight(.semibold))
            Text(planAdjustText("workout_hint")).font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func actionButton(_ operation: String, image: String) -> some View {
        Button { choose(operation) } label: { Label(planAdjustText(operation), systemImage: image).multilineTextAlignment(.leading).frame(minHeight: 44) }.buttonStyle(.bordered)
            .disabled((operation == "move" && (workouts.isEmpty || activelyPaused)) || (operation == "rebuild" && activelyPaused))
    }
    private func goBack() {
        if preview != nil { preview = nil; return }
        if let action { drafts[action] = Draft(workout: selectedWorkout, move: moveDate, from: fromDate, through: throughDate, reminder: reminderDate, hasReminder: hasReminder, days: availableDays, reason: reason, ready: readyToResume) }
        action = nil
    }
    private func choose(_ operation: String) {
        Task { await track(operation, "opened") }
        action = operation
        preview = nil; previewKey = UUID().uuidString
        if let draft = drafts[operation] {
            selectedWorkout = draft.workout; moveDate = draft.move; fromDate = draft.from; throughDate = draft.through
            reminderDate = draft.reminder; hasReminder = draft.hasReminder; availableDays = draft.days; reason = draft.reason; readyToResume = draft.ready
            return
        }
        reason = "none"
        if operation == "availability" {
            fromDate = availability?.unavailableFrom.flatMap(Self.date) ?? minimumDate
            if fromDate < minimumDate { fromDate = minimumDate }
            throughDate = max(fromDate, availability?.unavailableThrough.flatMap(Self.date) ?? calendar.date(byAdding: .day, value: 6, to: fromDate)!)
            availableDays = Set(availability?.availableDays ?? [2, 4, 6])
        } else if operation == "pause" || operation == "edit_pause" {
            fromDate = availability?.pausedOn.flatMap(Self.date) ?? minimumDate
            reminderDate = availability?.reminderDate.flatMap(Self.date) ?? calendar.date(byAdding: .day, value: 7, to: minimumDate)!
            hasReminder = availability?.reminderDate != nil
        }
    }

    @ViewBuilder private func configuration(_ operation: String) -> some View {
        if operation == "move" {
            Text(planAdjustText("move_detail")).font(.body)
            Picker(planAdjustText("workout"), selection: $selectedWorkout) {
                ForEach(workouts) { row in Text("\(dateLabel(row.date)) · \(BuiltinWorkoutText.localized(row.title))").tag(row.id) }
            }.pickerStyle(.menu).buttonStyle(.bordered)
            DatePicker(planAdjustText("to_date"), selection: $moveDate, in: minimumDate..., displayedComponents: .date).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            Text(planAdjustText("move_guard")).font(.footnote).foregroundStyle(.secondary)
        } else if operation == "availability" {
            Text(planAdjustText("availability_detail")).font(.body)
            DatePicker(planAdjustText("from_date"), selection: $fromDate, in: minimumDate..., displayedComponents: .date).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            DatePicker(planAdjustText("through_date"), selection: $throughDate, in: fromDate..., displayedComponents: .date).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                Text(planAdjustText("available_days")).font(.headline)
                ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                    Toggle(calendar.weekdaySymbols[weekday - 1], isOn: Binding(get: { availableDays.contains(weekday) }, set: { if $0 { availableDays.insert(weekday) } else { availableDays.remove(weekday) } }))
                        .frame(minHeight: 44)
                }
            }
            Text(planAdjustText("zero_days")).font(.footnote).foregroundStyle(.secondary)
        } else if operation == "pause" || operation == "edit_pause" {
            Text(planAdjustText("pause_detail")).font(.body)
            if fromDate < minimumDate {
                Text(String(format: planAdjustText("paused_since"), dateLabel(dateKey(fromDate)))).font(.subheadline)
            } else {
                DatePicker(planAdjustText("pause_from"), selection: $fromDate, in: minimumDate..., displayedComponents: .date).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            }
            Toggle(planAdjustText("has_reminder"), isOn: $hasReminder)
            if hasReminder { DatePicker(planAdjustText("return_date"), selection: $reminderDate, in: fromDate..., displayedComponents: .date).environment(\.timeZone, TimeZone(secondsFromGMT: 0)!) }
            Text(planAdjustText("reminder_detail")).font(.footnote).foregroundStyle(.secondary)
        } else if operation == "resume" {
            Text(planAdjustText("resume_detail")).font(.body)
            Toggle(planAdjustText("ready"), isOn: $readyToResume)
            Text(planAdjustText("not_ready")).font(.footnote).foregroundStyle(.secondary)
        } else {
            Text(planAdjustText(operation + "_detail")).font(.body)
        }
        if operation != "undo" {
            Picker(planAdjustText("reason"), selection: $reason) {
                ForEach(["none", "schedule", "travel", "weather", "illness", "recovery", "other"], id: \.self) { Text(planAdjustText("reason_" + $0)).tag($0) }
            }.pickerStyle(.menu).buttonStyle(.bordered)
            Text(planAdjustText("reason_detail")).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func previewContent(_ value: PlanChangePreviewDTO) -> some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
            Text(planAdjustText("review_detail")).font(.body)
            if value.availability.paused == true, let start = value.availability.pausedOn {
                Text(String(format: planAdjustText("pause_scheduled"), dateLabel(start))).font(.headline)
                Text(planAdjustText("reminder_detail")).font(.footnote).foregroundStyle(.secondary)
            }
            if let reminder = value.availability.reminderDate {
                Text(String(format: planAdjustText("reminder_summary"), dateLabel(reminder))).font(.subheadline).foregroundStyle(.secondary)
            }
            if value.operation == "availability", let start = value.availability.unavailableFrom, let end = value.availability.unavailableThrough {
                Text(String(format: planAdjustText("availability_summary"), dateLabel(start), dateLabel(end))).font(.headline)
                let days = (value.availability.availableDays ?? []).sorted().map { calendar.weekdaySymbols[$0 - 1] }.joined(separator: ", ")
                Text(days.isEmpty ? planAdjustText("none_available") : days).font(.subheadline)
            }
            if value.operation == "resume" || value.operation == "rebuild" { Text(planAdjustText("no_catchup")).font(.footnote).foregroundStyle(.secondary) }
            let changed = changedRows(value)
            if changed.isEmpty { Text(planAdjustText("no_rows")).font(.subheadline).foregroundStyle(.secondary) }
            ForEach(changed, id: \.self) { id in
                OutboundCard {
                    VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                        if let before = value.before.first(where: { $0.id == id && $0.status == "planned" }) {
                            Text(planAdjustText("before")).font(.caption).foregroundStyle(.secondary)
                            rowLabel(before)
                        }
                        Text(planAdjustText("after")).font(.caption).foregroundStyle(.secondary)
                        if let after = value.after.first(where: { $0.id == id && $0.status == "planned" }) { rowLabel(after) }
                        else { Text(planAdjustText("removed")).font(.subheadline) }
                    }
                }
            }
            Text(planAdjustText("expiry")).font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func changedRows(_ value: PlanChangePreviewDTO) -> [String] {
        let ids = Set(value.before.filter { $0.status == "planned" }.map(\.id) + value.after.filter { $0.status == "planned" }.map(\.id))
        return ids.filter { id in value.before.first(where: { $0.id == id }) != value.after.first(where: { $0.id == id }) }.sorted { lhs, rhs in
            let l = value.before.first(where: { $0.id == lhs })?.date ?? value.after.first(where: { $0.id == lhs })?.date ?? ""
            let r = value.before.first(where: { $0.id == rhs })?.date ?? value.after.first(where: { $0.id == rhs })?.date ?? ""
            return l == r ? lhs < rhs : l < r
        }
    }
    private func rowLabel(_ row: PlanChangeWorkoutDTO) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(BuiltinWorkoutText.localized(row.title)).font(.subheadline.weight(.semibold))
            Text("\(dateLabel(row.date)) · \(String(format: planAdjustText("minutes"), Int(ceil(Double(row.durationSeconds) / 60))))").font(.subheadline).foregroundStyle(.secondary)
            if row.optional { Text(planAdjustText("optional")).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func loadContext() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let value = try await store.fetchPlanChangeContext()
            guard value.planId == plan.id else {
                ActivityDiagnosticLog.error(.sync, "Plan adjustment operation=context error=plan_changed")
                showToast(planAdjustText("stale")); return
            }
            context = value
            if selectedWorkout.isEmpty { selectedWorkout = value.workouts.first(where: { $0.status == "planned" && !$0.optional })?.id ?? "" }
            fromDate = minimumDate; throughDate = calendar.date(byAdding: .day, value: 6, to: minimumDate)!
            reminderDate = calendar.date(byAdding: .day, value: 7, to: minimumDate)!
            moveDate = calendar.date(byAdding: .day, value: 1, to: minimumDate)!
        } catch { report(error, operation: "context") }
    }
    private func createPreview() async {
        guard let context, let action, !busy else { return }
        busy = true; defer { busy = false }
        var change = PlanChangeRequestDTO.Change(operation: action)
        switch action {
        case "move": change.workoutId = selectedWorkout; change.toDate = dateKey(moveDate)
        case "availability": change.fromDate = dateKey(fromDate); change.throughDate = dateKey(throughDate); change.availableDays = availableDays.sorted()
        case "pause", "edit_pause": change.operation = "pause"; change.fromDate = dateKey(fromDate); change.reminderDate = hasReminder ? dateKey(reminderDate) : nil
        case "end": change = .init(operation: "availability", availableDays: [])
        case "undo": change.commandId = context.undoCommandId
        default: break
        }
        // New preview for every review; an ambiguous Apply always retries the retained preview/key.
        let request = PlanChangeRequestDTO(planId: context.planId, idempotencyKey: UUID().uuidString, reason: reason == "none" ? nil : reason, change: change)
        do { preview = try await store.previewPlanChange(request); previewKey = request.idempotencyKey; await track(action, "previewed") }
        catch { report(error, operation: "preview"); await track(action, "failed") }
    }
    private func apply() async {
        guard let preview, !busy else { return }; busy = true; defer { busy = false }
        do {
            try await store.applyPlanChange(.init(previewId: preview.previewId, idempotencyKey: previewKey))
            await track(action ?? preview.operation, "applied"); onApplied(); dismiss()
        } catch { report(error, operation: "apply"); await track(action ?? preview.operation, "failed") }
    }
    private func report(_ error: Error, operation: String) {
        guard !(error is CancellationError) else { return }
        ActivityDiagnosticLog.error(.sync, "Plan adjustment operation=\(operation) error=\(ActivityDiagnosticLog.errorCategory(error))")
        toastTask?.cancel(); toast = planAdjustText(operation == "context" ? "load_failed" : "failed")
        if let api = error as? APIError, case let .http(_, _, code) = api, let code {
            if ["preview_stale", "preview_expired", "plan_changed", "undo_changed"].contains(code) { toast = planAdjustText("stale") }
            else if ["invalid_move", "closed_day", "recovery_spacing", "event_boundary"].contains(code) { toast = planAdjustText("move_invalid") }
            else if code == "rebuild_unavailable" { toast = planAdjustText("rebuild_unavailable") }
        }
        if let toast { showToast(toast) }
    }
    private func showToast(_ value: String) {
        toastTask?.cancel(); toast = value
        toastTask = Task { do { try await Task.sleep(for: .seconds(5)); toast = nil } catch { /* Replaced/dismissed toast. */ } }
    }
    private func track(_ operation: String, _ result: String) async {
        await analytics?.track(.init(.featureExposed, properties: [.feature: .string("plan_adjustment_" + operation), .result: .string(result)]))
    }
    private func dateKey(_ date: Date) -> String { let f = DateFormatter(); f.calendar = calendar; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd"; return f.string(from: date) }
    nonisolated private static func date(_ value: String) -> Date? { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; return f.date(from: String(value.prefix(10))) }
    private func dateLabel(_ value: String) -> String { guard let date = Self.date(value) else { return value }; let f = DateFormatter(); f.locale = locale; f.timeZone = calendar.timeZone; f.setLocalizedDateFormatFromTemplate("MMMddEEE"); return f.string(from: date) }
}
