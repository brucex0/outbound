import SwiftUI

struct TodayWorkoutChangeSelection {
    let reason: ReadinessChoice
    let action: String
    let minutes: Int
    let catalog: StandaloneWorkout?
}

struct TodayChangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.outboundTheme) private var theme
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @FocusState private var editingMinutes: Bool
    let original: ActivitySuggestionPayload?
    let displayedOverride: SessionIntent?
    let pendingAdjustment: AdjustmentProposalDTO?
    let busy: Bool
    let onApply: (TodayWorkoutChangeSelection) -> Void
    let onDecision: (Bool) -> Void
    @State private var reason: ReadinessChoice?
    @State private var action = "easy"
    @State private var minutesText = ""
    @State private var selectedWorkout: StandaloneWorkout?
    @State private var showsCatalog = false

    private var canonicalSeconds: Int { original?.durationSeconds ?? (original?.durationMinutes ?? 0) * 60 }
    private var displayedSeconds: Int {
        guard let displayedOverride else { return canonicalSeconds }
        let steps = displayedOverride.workoutSteps.reduce(0) { $0 + $1.durationSeconds }
        return steps > 0 ? steps : displayedOverride.targetDurationSeconds ?? canonicalSeconds
    }
    private var originalMinutes: Int { Int(ceil(Double(displayedSeconds) / 60)) }
    private var maximumMinutes: Int { min(360, (min(displayedSeconds, canonicalSeconds) - (action == "shorter" ? 1 : 0)) / 60) }
    private var validMinutes: Int? {
        guard let value = Int(minutesText), value >= 5, value <= maximumMinutes else { return nil }
        return value
    }
    private var isRest: Bool { action == "rest" }
    private var selection: TodayWorkoutChangeSelection? {
        guard original != nil, let reason else { return nil }
        if action == "catalog" {
            guard let selectedWorkout, selectedWorkout.catalogVersion != nil else { return nil }
            return .init(reason: .good, action: action, minutes: 5, catalog: selectedWorkout)
        }
        guard isRest || validMinutes != nil else { return nil }
        return .init(reason: reason, action: action, minutes: validMinutes ?? 5, catalog: nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                    Text(String(localized: "today.change.scope", defaultValue: "Change today only. Your other workouts stay as planned."))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let pendingAdjustment {
                        DisclosureGroup(String(localized: "today.adjustment.recommendation.title", defaultValue: "Recommended plan update")) {
                            Text(pendingAdjustment.explanation).font(.subheadline)
                            ForEach(Array(pendingAdjustment.changes.enumerated()), id: \.offset) { _, change in
                                Text(change.beforeTitle).font(.caption).strikethrough().foregroundStyle(.secondary)
                                Text(change.afterTitle).font(.subheadline.weight(.semibold))
                            }
                            Button(String(localized: "today.adjustment.apply", defaultValue: "Apply update")) { onDecision(true) }
                                .frame(minHeight: 44)
                            Button(String(localized: "today.adjustment.keep", defaultValue: "Keep original plan")) { onDecision(false) }
                                .frame(minHeight: 44)
                        }
                    }
                    if reason == nil {
                        Text(String(localized: "today.change.question", defaultValue: "What needs to change?"))
                            .font(.title2.weight(.semibold))
                        reasonButton(String(localized: "today.change.less_time", defaultValue: "Less time"), icon: "clock", choice: .shortOnTime)
                        reasonButton(String(localized: "today.change.low_energy", defaultValue: "Low energy"), icon: "battery.25percent", choice: .tired)
                        reasonButton(String(localized: "today.change.sore", defaultValue: "Sore or uncomfortable"), icon: "bandage", choice: .sore)
                        Button { reason = .good; action = "catalog"; showsCatalog = true } label: {
                            Label(String(localized: "today.change.choose", defaultValue: "Choose another workout"), systemImage: "rectangle.stack")
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        .disabled(original.flatMap { SportType(rawValue: $0.modality) } == nil || (displayedOverride != nil && displayedOverride?.sport.rawValue != original?.modality))
                    } else {
                        Button(String(localized: "today.change.back", defaultValue: "Change reason")) { reason = nil; selectedWorkout = nil }
                            .frame(minHeight: 44)
                        if reason == .tired {
                            ViewThatFits(in: .horizontal) {
                                HStack { energyOptions }
                                VStack(alignment: .leading) { energyOptions }
                            }
                        }
                        if reason == .sore {
                            Text(String(localized: "today.change.rest_explanation", defaultValue: "Rest today. Return to activity when comfortable."))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if action == "catalog" {
                            Button(String(localized: "today.change.choose", defaultValue: "Choose another workout")) { showsCatalog = true }
                                .frame(minHeight: 44)
                        } else if !isRest {
                            durationControls
                        }
                    }
                    if let original {
                        previewCard(label: String(localized: "today.change.current", defaultValue: "Current workout"), title: localizedTitle(original), duration: originalDuration(original), effort: displayedOverride?.detail ?? BuiltinWorkoutText.localized(original.effortLabel))
                    }
                    if reason != nil {
                        replacementPreview
                        if let selection {
                            OutboundPrimaryButton(title: String(localized: "today.change.apply", defaultValue: "Apply"), systemImage: "checkmark") {
                                editingMinutes = false
                                onApply(selection)
                            }
                            .disabled(busy)
                        }
                    }
                    Button(String(localized: "today.change.cancel", defaultValue: "Cancel")) { dismiss() }
                        .frame(minHeight: 44)
                }
                .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle(String(localized: "today.change.sheet_title", defaultValue: "Change today’s workout"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(String(localized: "common.done", defaultValue: "Done")) { editingMinutes = false } } }
            .sheet(isPresented: $showsCatalog) {
                StandaloneWorkoutPickerView(sport: original.flatMap { SportType(rawValue: $0.modality) } ?? .run) { workout in
                    selectedWorkout = workout
                    showsCatalog = false
                }
            }
        }
    }

    @ViewBuilder private var energyOptions: some View {
        energyButton(String(localized: "today.change.easier", defaultValue: "Make easier"), value: "easy")
        energyButton(String(localized: "today.change.shorter", defaultValue: "Make shorter"), value: "shorter")
        energyButton(String(localized: "today.change.rest", defaultValue: "Rest today"), value: "rest")
    }

    private func energyButton(_ title: String, value: String) -> some View {
        Button { setAction(value) } label: {
            HStack { Text(title); if action == value { Image(systemName: "checkmark") } }
                .frame(minHeight: 44)
        }.buttonStyle(.bordered).tint(theme.accentColor)
    }

    private var durationControls: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
            Text(String(localized: "today.change.minutes_label", defaultValue: "Whole-session minutes")) .font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack { durationShortcuts }
                VStack(alignment: .leading) { durationShortcuts }
            }
            TextField(String(localized: "today.change.custom_minutes", defaultValue: "Custom minutes"), text: $minutesText)
                .keyboardType(.numberPad).textFieldStyle(.roundedBorder).focused($editingMinutes)
                .accessibilityLabel(String(localized: "today.change.custom_minutes", defaultValue: "Custom minutes"))
            Text(maximumMinutes < 5
                 ? String(localized: "today.change.no_shorter", defaultValue: "This session is already too short to shorten further. Choose another option.")
                 : String(format: String(localized: "today.change.minute_range", defaultValue: "Enter 5–%d minutes, including the whole session."), maximumMinutes))
                .font(.caption).foregroundStyle(.secondary)
            Text(String(localized: "today.change.easy_explanation", defaultValue: "This replaces today’s workout with a simple easy session. Intervals and other targets are removed."))
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var durationShortcuts: some View {
        ForEach([10, 15, 20, 30, 45, 60].filter { $0 <= maximumMinutes && $0 < originalMinutes }, id: \.self) { minutes in
            Button(minuteLabel(minutes)) { minutesText = String(minutes) }.buttonStyle(.bordered).frame(minHeight: 44)
        }
    }

    @ViewBuilder private var replacementPreview: some View {
        if isRest {
            previewCard(label: String(localized: "today.change.replacement", defaultValue: "Replacement"), title: String(localized: "today.change.rest", defaultValue: "Rest today"), duration: nil, effort: nil)
        } else if let workout = selectedWorkout, action == "catalog" {
            let total = workout.targetDistanceMeters.map { Int(($0 / 1000 * 420).rounded()) } ?? workout.steps.reduce(0) { $0 + $1.durationSeconds }
            let duration = workout.targetDistanceMeters.map {
                String(format: String(localized: "today.change.distance_estimate", defaultValue: "%1$@ · about %2$@"), measurementPreferences.unitSystem.distanceString(meters: $0, fractionDigits: 1), durationLabel(total))
            } ?? durationLabel(total)
            let efforts = workout.guideInstructions.segments.map(\.effort)
            previewCard(label: String(localized: "today.change.replacement", defaultValue: "Replacement"), title: workout.title, duration: duration, effort: String(format: String(localized: "today.change.rpe_range", defaultValue: "RPE %1$d–%2$d"), locale: .autoupdatingCurrent, efforts.map(\.rpeMin).min() ?? 1, efforts.map(\.rpeMax).max() ?? 2))
            if workout.targetDistanceMeters != nil {
                Text(String(localized: "today.change.estimate_basis", defaultValue: "Time is an estimate at 7 min/km. The workout ends at the selected distance."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(workout.subtitle).font(.subheadline).foregroundStyle(.secondary)
            ForEach(workout.steps) { step in
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.label).font(.subheadline.weight(.semibold))
                    Text(durationLabel(step.durationSeconds)).font(.caption)
                    if let detail = step.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
            }
        } else if let minutes = validMinutes {
            previewCard(label: String(localized: "today.change.replacement", defaultValue: "Replacement"), title: String(localized: "today.change.easy_session", defaultValue: "Easy session"), duration: minuteLabel(minutes), effort: String(localized: "Very easy"))
        }
    }

    private func previewCard(label: String, title: String, duration: String?, effort: String?) -> some View {
        OutboundCard {
            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(title).font(.headline)
                if let duration { Text(duration).font(.subheadline.monospacedDigit()) }
                if let effort { Text(effort).font(.subheadline).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reasonButton(_ title: String, icon: String, choice: ReadinessChoice) -> some View {
        Button { reason = choice; setAction(choice == .sore ? "rest" : choice == .shortOnTime ? "shorter" : "easy") } label: {
            HStack { Label(title, systemImage: icon); Spacer(); Image(systemName: "chevron.right") }.frame(minHeight: 44)
        }.buttonStyle(.bordered)
    }

    private func setAction(_ value: String) {
        action = value
        minutesText = String(value == "shorter" ? max(5, min(maximumMinutes, Int(Double(originalMinutes) * 0.75))) : max(5, maximumMinutes))
    }

    private func originalDuration(_ original: ActivitySuggestionPayload) -> String {
        if let displayedOverride {
            if let distance = displayedOverride.targetDistanceMeters { return measurementPreferences.unitSystem.distanceString(meters: distance, fractionDigits: 1) }
            return durationLabel(displayedSeconds)
        }
        let duration = durationLabel(original.durationSeconds ?? originalMinutes * 60)
        guard original.catalogWorkout?.targetDistanceMeters != nil, let distance = original.distanceMeters else { return duration }
        return String(format: String(localized: "today.change.distance_estimate", defaultValue: "%1$@ · about %2$@"), measurementPreferences.unitSystem.distanceString(meters: distance, fractionDigits: 1), duration)
    }

    private func localizedTitle(_ original: ActivitySuggestionPayload) -> String {
        if let displayedOverride { return BuiltinWorkoutText.localized(displayedOverride.title) }
        return original.catalogWorkout.map { $0.withCatalogVersion(original.catalogVersion ?? 1).title } ?? BuiltinWorkoutText.localized(original.title)
    }

    private func durationLabel(_ seconds: Int) -> String {
        guard seconds % 60 != 0 else { return minuteLabel(seconds / 60) }
        return String(format: String(localized: "today.change.duration_seconds", defaultValue: "%1$d min %2$d sec"), locale: .autoupdatingCurrent, seconds / 60, seconds % 60)
    }

    private func minuteLabel(_ minutes: Int) -> String {
        String(format: String(localized: "activity.completed.duration.format", defaultValue: "%d min"), locale: .autoupdatingCurrent, minutes)
    }
}
