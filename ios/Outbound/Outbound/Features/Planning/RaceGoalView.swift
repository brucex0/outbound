import SwiftUI

struct SavedRaceGoal: Codable, Equatable, Identifiable {
    let id: String
    let targetDate: String?
    let targetDistanceMeters: Double?
    let eventIntent: String
    let targetTimeSeconds: Int?
    let daysPerWeekTarget: Int
    let maxSessionMinutes: Int
    let shortRunSessions: Bool
    let optionalMobility: Bool
    let editable: Bool
}

struct RaceGoalRoadmap: Codable, Equatable {
    struct Phase: Codable, Equatable { let phase: String; let startDate: String; let endDate: String }
    let currentPhase: String
    let detailedFromDate: String?
    let detailedThroughDate: String?
    let phases: [Phase]
}

struct RaceGoalUpdateRequest: Encodable {
    let targetDate: String
    let targetDistanceMeters: Double
    let eventIntent: String
    let targetTimeSeconds: Int?
    let daysPerWeekTarget: Int
    let maxSessionMinutes: Int
    let shortRunSessions: Bool
    let optionalMobility: Bool
}

private func raceText(_ key: String) -> String { String(localized: String.LocalizationValue("today.race_goal." + key)) }
private func raceDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let parts = value.prefix(10).split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
}
private func raceClock(_ seconds: Int) -> String { String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }

struct RaceGoalCard: View {
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @Environment(\.analyticsManager) private var analytics
    let goal: SavedRaceGoal
    let roadmap: RaceGoalRoadmap?
    @State private var editing = false

    var body: some View {
        OutboundCard {
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                Text(raceText("title")).font(.headline)
                if let distance = goal.targetDistanceMeters {
                    Text("\(measurementPreferences.unitSystem.distanceValue(meters: distance).formatted(.number.precision(.fractionLength(1)))) \(measurementPreferences.unitSystem.distanceUnit)").font(.title3.bold())
                }
                if let date = raceDate(goal.targetDate) {
                    Text(date, format: .dateTime.year().month(.abbreviated).day())
                    Text(String(format: raceText("countdown"), max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: date).day ?? 0))).font(.subheadline)
                }
                Text(goal.eventIntent == "targetTime" ? "\(raceText("finish_time")): \(raceClock(goal.targetTimeSeconds ?? 0))" : raceText(goal.eventIntent == "perform" ? "perform" : "finish"))
                if let roadmap {
                    Text(String(format: raceText("phase"), raceText(roadmap.currentPhase))).font(.subheadline.bold())
                    Text(raceText("roadmap")).font(.headline).padding(.top, OutboundSpacing.compact)
                    ForEach(roadmap.phases, id: \.phase) { phase in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(raceText(phase.phase)).font(.subheadline.weight(phase.phase == roadmap.currentPhase ? .bold : .regular))
                            if let start = raceDate(phase.startDate), let end = raceDate(phase.endDate) {
                                Text("\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let through = raceDate(roadmap.detailedThroughDate) {
                        Text(String(format: raceText("window"), through.formatted(date: .abbreviated, time: .omitted))).font(.subheadline)
                    }
                    Text(raceText("rolling")).font(.caption).foregroundStyle(.secondary)
                }
                if goal.editable {
                    Button(raceText("edit")) {
                        editing = true
                        Task { await analytics?.track(.init(.planningSurfaceOpened, properties: [.sourceType: .string("race_goal_edit"), .entrySource: .string("plan_details")])) }
                    }.buttonStyle(.bordered)
                }
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { RaceGoalEditor(goal: goal) } }
    }
}

private struct RaceGoalEditor: View {
    @EnvironmentObject private var store: TrainingPlanStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analytics
    let goal: SavedRaceGoal
    @State private var date: Date
    @State private var distance: Double
    @State private var intent: String
    @State private var timeInput: String
    @State private var days: Int
    @State private var cap: Int
    @State private var short: Bool
    @State private var mobility: Bool
    @State private var saving = false
    @State private var toast: String?

    init(goal: SavedRaceGoal) {
        self.goal = goal
        _date = State(initialValue: raceDate(goal.targetDate) ?? Date())
        _distance = State(initialValue: (goal.targetDistanceMeters ?? 10_000) / 1000)
        _intent = State(initialValue: goal.eventIntent)
        _timeInput = State(initialValue: raceClock(goal.targetTimeSeconds ?? 3600))
        _days = State(initialValue: goal.daysPerWeekTarget)
        _cap = State(initialValue: max(goal.shortRunSessions ? 10 : 25, goal.maxSessionMinutes))
        _short = State(initialValue: goal.shortRunSessions)
        _mobility = State(initialValue: goal.optionalMobility)
    }

    var body: some View {
        Form {
            Section(raceText("title")) {
                TextField(raceText("km"), value: $distance, format: .number).keyboardType(.decimalPad)
                DatePicker(raceText("date"), selection: $date, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                Picker(raceText("intent"), selection: $intent) {
                    Text(raceText("finish")).tag("finish")
                    Text(raceText("perform")).tag("perform")
                    Text(raceText("target_time")).tag("targetTime")
                }
                if intent == "targetTime" { TextField(raceText("finish_time_input"), text: $timeInput).keyboardType(.numbersAndPunctuation) }
            }
            Section {
                Stepper(String(format: raceText("days"), days), value: $days, in: 1...6)
                Stepper(String(format: raceText("cap"), cap), value: $cap, in: (short ? 10 : 25)...180, step: 5)
                Text(raceText("duration_detail")).font(.caption).foregroundStyle(.secondary)
                Toggle(raceText("short"), isOn: $short).onChange(of: short) { _, value in if !value { cap = max(25, cap) } }
                Text(raceText("short_detail")).font(.caption).foregroundStyle(.secondary)
                Toggle(raceText("mobility"), isOn: $mobility)
                Text(raceText("mobility_detail")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(raceText("edit"))
        .disabled(saving)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(raceText("cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button(raceText("save")) { save() }.disabled(saving || !distance.isFinite || distance <= 0 || distance > 500 || (intent == "targetTime" && parsedTime == nil) || date < Calendar.current.startOfDay(for: Date())) }
        }
        .overlay(alignment: .bottom) {
            if let toast { Text(toast).font(.subheadline).padding().background(.regularMaterial, in: Capsule()).padding().accessibilityAddTraits(.updatesFrequently) }
        }
    }

    private var parsedTime: Int? {
        let parts = timeInput.split(separator: ":", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 3, parts[0] >= 0, (0...59).contains(parts[1]), (0...59).contains(parts[2]) else { return nil }
        let seconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
        return seconds > 0 && seconds <= 172800 ? seconds : nil
    }

    private func save() {
        saving = true
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let request = RaceGoalUpdateRequest(targetDate: formatter.string(from: date), targetDistanceMeters: distance * 1000, eventIntent: intent, targetTimeSeconds: intent == "targetTime" ? parsedTime : nil, daysPerWeekTarget: days, maxSessionMinutes: cap, shortRunSessions: short, optionalMobility: mobility)
        Task {
            do {
                try await store.updateRaceGoal(goal, request: request)
                await analytics?.track(.init(.raceGoalUpdated, properties: [.result: .string("success"), .selectionType: .string(short ? "short" : "standard")]))
                toast = raceText("saved")
                try? await Task.sleep(for: .seconds(1))
                dismiss()
            } catch {
                ActivityDiagnosticLog.error(.sync, "[planning] race_goal_update_failed category=\(ActivityDiagnosticLog.errorCategory(error))")
                await analytics?.track(.init(.raceGoalUpdated, properties: [.result: .string("failure"), .selectionType: .string(short ? "short" : "standard")]))
                toast = raceText("failed")
                try? await Task.sleep(for: .seconds(4))
                toast = nil
            }
            saving = false
        }
    }
}
