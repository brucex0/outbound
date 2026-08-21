import Foundation
import SwiftUI

struct ManualWorkoutDraft: Equatable {
    var activityType: ActivityType?
    var title = ""
    var startedAt = Date()
    var durationMinutes: Int?
    var distanceMeters: Double?
    var isIndoor = false
    var shoeID: UUID?

    var firstMissingField: MissingField? {
        if activityType == nil { return .activityType }
        if durationMinutes == nil { return .duration }
        return nil
    }

    enum MissingField {
        case activityType
        case duration

        var question: String {
            switch self {
            case .activityType:
                return String(localized: "What kind of workout was it—run, ride, walk, hike, or swim?")
            case .duration:
                return String(localized: "How long did the workout take?")
            }
        }
    }
}

enum ManualWorkoutPromptParser {
    static func beginsWorkoutLog(_ text: String) -> Bool {
        let value = text.lowercased()
        let actions = ["log", "add", "record", "save", "registr", "añad", "agreg", "记录", "添加", "保存"]
        let workouts = ["workout", "activity", "run", "ride", "walk", "hike", "swim", "entren", "actividad", "correr", "corrí", "bicic", "camin", "nad", "锻炼", "运动", "跑", "骑", "走", "游泳"]
        let pastWorkout = ["yesterday", "completed", "finished", "i did", "i ran", "i rode", "i walked", "i hiked", "i swam", "ayer", "corrí", "completé", "昨天", "完成了", "跑了", "骑了", "走了", "游了"]
            .contains(where: value.contains)
        return workouts.contains(where: value.contains)
            && (actions.contains(where: value.contains) || pastWorkout)
    }

    static func parse(_ text: String, into original: ManualWorkoutDraft = ManualWorkoutDraft()) -> ManualWorkoutDraft {
        var draft = original
        let value = text.lowercased()

        if containsAny(value, ["run", "jog", "correr", "corrí", "跑步", "跑了"]) { draft.activityType = .running }
        else if containsAny(value, ["ride", "bike", "cycling", "bicic", "骑行", "骑车"]) { draft.activityType = .cycling }
        else if containsAny(value, ["hike", "sender", "徒步"]) { draft.activityType = .hiking }
        else if containsAny(value, ["walk", "camin", "步行", "走路"]) { draft.activityType = .walking }
        else if containsAny(value, ["swim", "nad", "游泳"]) { draft.activityType = .swimming }

        if containsAny(value, ["yesterday", "ayer", "昨天"]) {
            draft.startedAt = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        } else if containsAny(value, ["today", "hoy", "今天"]) {
            draft.startedAt = Date()
        }

        if containsAny(value, ["indoor", "treadmill", "interior", "cinta", "室内", "跑步机"]) {
            draft.isIndoor = true
        }

        if let duration = firstNumber(in: value, before: ["minutes", "minute", "mins", "minutos", "minuto", "分钟"]) {
            draft.durationMinutes = max(1, Int(duration.rounded()))
        } else if let hours = firstNumber(in: value, before: ["hours", "hour", "hrs", "hora", "horas", "小时"]) {
            draft.durationMinutes = max(1, Int((hours * 60).rounded()))
        }

        if let kilometers = firstNumber(in: value, before: ["kilometers", "kilometer", "kilometres", "kilometre", "km", "kilómetros", "kilómetro", "公里", "千米"]) {
            draft.distanceMeters = kilometers * 1_000
        } else if let shorthandKilometers = firstNumber(in: value, before: ["k"]) {
            draft.distanceMeters = shorthandKilometers * 1_000
        } else if let miles = firstNumber(in: value, before: ["miles", "mile", "mi", "millas", "milla", "英里"]) {
            draft.distanceMeters = miles * 1_609.344
        }

        return draft
    }

    private static func containsAny(_ value: String, _ candidates: [String]) -> Bool {
        candidates.contains(where: value.contains)
    }

    private static func firstNumber(in value: String, before units: [String]) -> Double? {
        let escapedUnits = units.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let pattern = #"([0-9]+(?:[\.,][0-9]+)?)\s*(?:"# + escapedUnits + #")"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return Double(value[range].replacingOccurrences(of: ",", with: "."))
    }
}

struct ManualWorkoutEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var gearStore: GearStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences

    @State private var draft: ManualWorkoutDraft
    @State private var distanceText: String
    @State private var durationText: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    let onSaved: ((SavedActivity) -> Void)?
    private let initialDistanceMeters: Double

    init(draft: ManualWorkoutDraft = ManualWorkoutDraft(), onSaved: ((SavedActivity) -> Void)? = nil) {
        var resolved = draft
        resolved.activityType = resolved.activityType ?? .running
        resolved.durationMinutes = resolved.durationMinutes ?? 30
        _draft = State(initialValue: resolved)
        _durationText = State(initialValue: String(resolved.durationMinutes ?? 30))
        let distance = resolved.distanceMeters ?? 0
        initialDistanceMeters = distance
        _distanceText = State(initialValue: "")
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    Picker("Activity", selection: Binding(
                        get: { draft.activityType ?? .running },
                        set: { draft.activityType = $0 }
                    )) {
                        ForEach(ActivityType.allCases, id: \.self) { type in
                            Text(type.manualEntryTitle).tag(type)
                        }
                    }
                    TextField("Title (optional)", text: $draft.title)
                    DatePicker("Date and time", selection: $draft.startedAt)
                    Toggle("Indoor workout", isOn: $draft.isIndoor)
                }

                Section("Details") {
                    LabeledContent("Duration") {
                        HStack(spacing: 6) {
                            TextField("30", text: $durationText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 72)
                            Text("min").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Distance") {
                        HStack(spacing: 6) {
                            TextField("Optional", text: $distanceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 92)
                            Text(measurementPreferences.unitSystem.distanceUnit).foregroundStyle(.secondary)
                        }
                    }
                    if draft.activityType == .running, !gearStore.shoes.isEmpty {
                        Picker("Shoes", selection: $draft.shoeID) {
                            Text("None").tag(nil as UUID?)
                            ForEach(gearStore.shoes) { shoe in
                                Text(shoe.displayName).tag(shoe.id as UUID?)
                            }
                        }
                    }
                }

                Section {
                    Text("Manual workouts count toward your progress but do not include a GPS route.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!isValid || isSaving)
                }
            }
            .overlay { if isSaving { ProgressView().controlSize(.large) } }
            .task {
                guard distanceText.isEmpty, initialDistanceMeters > 0 else { return }
                distanceText = measurementPreferences.unitSystem.distanceValueString(
                    meters: initialDistanceMeters,
                    fractionDigits: 2
                )
            }
            .alert("Couldn’t save workout", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private var isValid: Bool {
        guard let duration = Int(durationText), duration > 0 else { return false }
        if !distanceText.isEmpty, parsedDistanceValue == nil { return false }
        return true
    }

    private var parsedDistanceValue: Double? {
        Double(distanceText.replacingOccurrences(of: ",", with: "."))
    }

    @MainActor
    private func save() async {
        guard let durationMinutes = Int(durationText), durationMinutes > 0 else { return }
        isSaving = true
        defer { isSaving = false }
        let distanceM = max(0, measurementPreferences.unitSystem.distanceMeters(from: parsedDistanceValue ?? 0))
        let durationSeconds = durationMinutes * 60
        let type = draft.activityType ?? .running
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? type.defaultManualTitle : title
        let gear = draft.shoeID.flatMap { id in
            gearStore.shoes.first(where: { $0.id == id }).map {
                ActivityGearAttachment(shoeID: $0.id, shoeName: $0.displayName)
            }
        }
        let summary = ActivitySummary(
            startedAt: draft.startedAt,
            endedAt: draft.startedAt.addingTimeInterval(TimeInterval(durationSeconds)),
            durationSecs: durationSeconds,
            distanceM: distanceM,
            avgPace: distanceM > 0 ? Double(durationSeconds) / (distanceM / 1_000) : nil,
            trackPoints: []
        )
        do {
            let saved = try await activityStore.save(
                summary: summary,
                photos: [],
                activityType: type,
                reflection: nil,
                title: resolvedTitle,
                source: ActivitySourceMetadata(
                    kind: .manual,
                    displayName: String(localized: "Manual entry"),
                    deviceName: nil,
                    externalID: nil,
                    importedAt: Date()
                ),
                gear: gear,
                manualEdits: ActivityManualEdits(editedAt: Date(), editedFields: ["created-manually"]),
                indoor: ActivityIndoorMetadata(isIndoor: draft.isIndoor, mode: draft.isIndoor ? "manual-indoor" : nil)
            )
            onSaved?(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension ActivityType {
    var manualEntryTitle: String {
        switch self {
        case .running: return String(localized: "Run")
        case .cycling: return String(localized: "Ride")
        case .hiking: return String(localized: "Hike")
        case .walking: return String(localized: "Walk")
        case .swimming: return String(localized: "Swim")
        }
    }

    var defaultManualTitle: String {
        String(localized: "Manual \(manualEntryTitle)")
    }
}
