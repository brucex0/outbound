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

struct ManualWorkoutEntryView: View {
    @FocusState private var focusedInput: String?
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
                        .focused($focusedInput, equals: "draft_title")
                        .submitLabel(.next)
                        .inputSubmissionAnalytics(.activityEntry)
                        .onSubmit { focusedInput = "durationText" }
                    DatePicker("Date and time", selection: $draft.startedAt)
                    Toggle("Indoor workout", isOn: $draft.isIndoor)
                }

                Section("Details") {
                    LabeledContent("Duration") {
                        HStack(spacing: 6) {
                            TextField("30", text: $durationText)
                                .submitLabel(.done)
                                .onSubmit { focusedInput = nil }
                                .focused($focusedInput, equals: "durationText")
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 72)
                            Text("min").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Distance") {
                        HStack(spacing: 6) {
                            TextField("Optional", text: $distanceText)
                                .submitLabel(.done)
                                .onSubmit { focusedInput = nil }
                                .focused($focusedInput, equals: "distanceText")
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
        focusedInput = nil
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
        case .strengthTraining: return String(localized: "plan_builder.activity.strength", defaultValue: "Strength")
        case .mobility: return String(localized: "plan_builder.activity.mobility", defaultValue: "Mobility")
        }
    }

    var defaultManualTitle: String {
        String(localized: "Manual \(manualEntryTitle)")
    }
}
