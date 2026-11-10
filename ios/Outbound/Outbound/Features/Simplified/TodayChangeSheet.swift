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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @FocusState private var editingMinutes: Bool
    @ScaledMetric(relativeTo: .body) private var minutesFieldWidth = 54
    @State private var reason: ReadinessChoice?
    @State private var action = "easy"
    @State private var minutesText = ""
    @State private var selectedWorkout: StandaloneWorkout?
    @State private var showsCatalog = false
    @State private var detailsExpanded = false
    @State private var editorHeight: CGFloat = 44
    @State private var comparisonHeight: CGFloat = 100
    @State private var footerHeight: CGFloat = 60

    private var scrollsComparison: Bool { dynamicTypeSize.isAccessibilitySize || editingMinutes }
    private var fittedHeight: CGFloat {
        min(UIScreen.main.bounds.height * 0.85, 70 + (scrollsComparison ? 0 : comparisonHeight) + editorHeight + footerHeight)
    }

    let original: ActivitySuggestionPayload?
    let displayedOverride: SessionIntent?
    let pendingAdjustment: AdjustmentProposalDTO?
    let busy: Bool
    let onApply: (TodayWorkoutChangeSelection) -> Void
    let onDecision: (Bool) -> Void

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
            VStack(spacing: 0) {
                if let original, !scrollsComparison {
                    comparison(original)
                        .padding(.horizontal, OutboundSpacing.screen)
                        .padding(.top, OutboundSpacing.compact)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { comparisonHeight = $0 }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                        if let original, scrollsComparison { comparison(original) }
                        if let pendingAdjustment { recommendation(pendingAdjustment) }
                        changeMenu
                        if reason != nil { editor }
                    }
                    .padding(OutboundSpacing.screen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { editorHeight = $0 }
                }
                .scrollDismissesKeyboard(.interactively)
                Divider()
                HStack {
                    if editingMinutes {
                        Button(String(localized: "common.done", defaultValue: "Done")) { editingMinutes = false }
                            .frame(minHeight: 44)
                    }
                    Spacer(minLength: 0)
                    Button {
                        guard let selection else { return }
                        editingMinutes = false
                        onApply(selection)
                    } label: {
                        Label(String(localized: "today.change.apply", defaultValue: "Apply"), systemImage: "checkmark")
                            .font(.body.weight(.semibold)).frame(minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(theme.actionColor)
                    .disabled(selection == nil || busy)
                    .accessibilityIdentifier("todayChangeApply")
                }
                .padding(.horizontal, OutboundSpacing.screen)
                .padding(.vertical, OutboundSpacing.compact)
                .background(OutboundPalette.background)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
            }
            .background(OutboundPalette.background)
            .navigationTitle(String(localized: "today.change.sheet_title", defaultValue: "Change workout"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "today.change.cancel", defaultValue: "Cancel")) { dismiss() }.frame(minHeight: 44)
                }
            }
            .sheet(isPresented: $showsCatalog) {
                StandaloneWorkoutPickerView(sport: original.flatMap { SportType(rawValue: $0.modality) } ?? .run) { workout in
                    selectedWorkout = workout
                    showsCatalog = false
                }
            }
        }
        .presentationDetents([.height(fittedHeight), .large])
        .presentationDragIndicator(.visible)
    }

    private var changeMenu: some View {
        Menu {
            Button(String(localized: "today.change.less_time", defaultValue: "Less time"), systemImage: "clock") { choose(.shortOnTime) }
            Button(String(localized: "today.change.low_energy", defaultValue: "Low energy"), systemImage: "battery.25percent") { choose(.tired) }
            Button(String(localized: "today.change.sore", defaultValue: "Sore or uncomfortable"), systemImage: "bandage") { choose(.sore) }
            Button(String(localized: "today.change.choose", defaultValue: "Choose another workout"), systemImage: "rectangle.stack") {
                reason = .good; setAction("catalog"); showsCatalog = true
            }.disabled(original.flatMap { SportType(rawValue: $0.modality) } == nil || (displayedOverride != nil && displayedOverride?.sport.rawValue != original?.modality))
        } label: {
            HStack(spacing: 6) {
                Text(reasonTitle).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .foregroundStyle(theme.accentColor)
            .frame(minHeight: 44)
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint(String(localized: "today.change.menu_hint", defaultValue: "Choose why you want to change today’s workout."))
    }

    private var reasonTitle: String {
        guard let reason else { return String(localized: "today.change.prompt", defaultValue: "Choose a change") }
        switch reason {
        case .shortOnTime: return String(localized: "today.change.less_time", defaultValue: "Less time")
        case .tired: return String(localized: "today.change.low_energy", defaultValue: "Low energy")
        case .sore: return String(localized: "today.change.sore", defaultValue: "Sore or uncomfortable")
        case .good: return String(localized: "today.change.choose", defaultValue: "Choose another workout")
        }
    }

    @ViewBuilder private var editor: some View {
        if reason == .tired {
            if dynamicTypeSize.isAccessibilitySize {
                energyMenu
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: OutboundSpacing.compact) { energyOptions }.fixedSize(horizontal: true, vertical: false)
                    energyMenu
                }
            }
        }
        if reason == .sore {
            Text(String(localized: "today.change.rest_explanation", defaultValue: "Rest today. Return to activity when comfortable."))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        if action == "catalog" {
            if let selectedWorkout {
                Button(String(localized: "today.change.change_catalog", defaultValue: "Change workout")) { showsCatalog = true }
                    .frame(minHeight: 44)
                catalogPreview(selectedWorkout)
            } else {
                Button(String(localized: "today.change.choose", defaultValue: "Choose another workout")) { showsCatalog = true }.frame(minHeight: 44)
            }
        } else if !isRest {
            durationControls
            if removesTargets {
                Text(String(localized: "today.change.targets_removed", defaultValue: "Intervals and other targets are removed."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var energyOptions: some View {
        energyButton(String(localized: "today.change.easier_short", defaultValue: "Easier"), value: "easy")
        energyButton(String(localized: "today.change.shorter_short", defaultValue: "Shorter"), value: "shorter")
        energyButton(String(localized: "today.change.rest_short", defaultValue: "Rest"), value: "rest")
    }

    private var energyMenu: some View {
        Menu {
            Button(String(localized: "today.change.easier_short", defaultValue: "Easier")) { setAction("easy") }
            Button(String(localized: "today.change.shorter_short", defaultValue: "Shorter")) { setAction("shorter") }
            Button(String(localized: "today.change.rest", defaultValue: "Rest today")) { setAction("rest") }
        } label: {
            HStack(spacing: 8) { Text(actionTitle); Image(systemName: "chevron.down") }.padding(.horizontal, 12).frame(minHeight: 44)
                .background(OutboundPalette.surface, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
                .fixedSize(horizontal: false, vertical: true)
        }.accessibilityLabel(String(localized: "today.change.energy_choice", defaultValue: "Energy adjustment"))
            .accessibilityValue(actionTitle)
    }

    private var actionTitle: String {
        switch action {
        case "shorter": return String(localized: "today.change.shorter_short", defaultValue: "Shorter")
        case "rest": return String(localized: "today.change.rest_short", defaultValue: "Rest")
        default: return String(localized: "today.change.easier_short", defaultValue: "Easier")
        }
    }

    private func energyButton(_ title: String, value: String) -> some View {
        Button { setAction(value) } label: {
            HStack(spacing: 4) { if action == value { Image(systemName: "checkmark") }; Text(title) }
                .font(.subheadline.weight(action == value ? .semibold : .regular))
                .padding(.horizontal, 10).frame(minHeight: 44)
                .background(action == value ? theme.accentColor.opacity(0.16) : OutboundPalette.surface, in: Capsule())
                .overlay(Capsule().stroke(action == value ? theme.accentColor : Color.clear, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityAddTraits(action == value ? .isSelected : [])
    }

    private var durationControls: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                    durationLabelView
                    minutesInput
                }
            } else {
                HStack(spacing: OutboundSpacing.standard) {
                    durationLabelView
                    minutesInput
                }
            }
            if maximumMinutes >= 5 {
                let presets = durationPresets
                if presets.count >= 2 {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: OutboundSpacing.compact) {
                            ForEach(Array(presets), id: \.self) { minutes in
                                Button(minuteLabel(minutes)) { minutesText = String(minutes) }
                                    .font(.caption.weight(.medium)).padding(.horizontal, 10).frame(minHeight: 44)
                                    .background(OutboundPalette.surface, in: Capsule())
                            }
                        }.fixedSize(horizontal: true, vertical: false)
                        Color.clear.frame(height: 0)
                    }
                }
            }
            if maximumMinutes < 5 {
                Text(String(localized: "today.change.no_shorter", defaultValue: "This session is already too short to shorten further. Choose another option."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if maximumMinutes >= 5 && !minutesText.isEmpty && validMinutes == nil {
                Text(String(format: String(localized: "today.change.range_error", defaultValue: "Enter 5–%d minutes."), maximumMinutes))
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var durationLabelView: some View {
        Text(String(localized: "today.change.duration_label", defaultValue: "Duration"))
            .font(.subheadline.weight(.medium))
    }

    private var minutesInput: some View {
        HStack(spacing: 4) {
            TextField("", text: $minutesText)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .frame(width: minutesFieldWidth).frame(minHeight: 44).focused($editingMinutes)
                .accessibilityLabel(String(localized: "today.change.custom_minutes", defaultValue: "Custom minutes"))
                .accessibilityHint(maximumMinutes >= 5
                    ? String(format: String(localized: "today.change.range_error", defaultValue: "Enter 5–%d minutes."), maximumMinutes)
                    : String(localized: "today.change.no_shorter", defaultValue: "This session is already too short to shorten further. Choose another option."))
            Text(String(localized: "today.change.minutes_unit", defaultValue: "min"))
                .font(.subheadline).foregroundStyle(.secondary).fixedSize()
        }
        .padding(.horizontal, 8).frame(minHeight: 44)
        .background(OutboundPalette.surface, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private func comparison(_ original: ActivitySuggestionPayload) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: OutboundSpacing.standard))
            : AnyLayout(HStackLayout(alignment: .top, spacing: OutboundSpacing.standard))
        layout {
            comparisonColumn(String(localized: "today.change.current_short", defaultValue: "Current"), currentComparisonTitle(original), originalDuration(original), displayedOverride?.detail ?? BuiltinWorkoutText.localized(original.effortLabel))
            Image(systemName: dynamicTypeSize.isAccessibilitySize ? "arrow.down" : "arrow.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, dynamicTypeSize.isAccessibilitySize ? 0 : 18).accessibilityHidden(true)
            comparisonColumn(String(localized: "today.change.new", defaultValue: "New"), proposedTitle, proposedDuration, proposedEffort)
        }
        .padding(OutboundSpacing.standard).frame(maxWidth: .infinity, alignment: .leading)
        .background(OutboundPalette.surface, in: RoundedRectangle(cornerRadius: OutboundRadius.card))
    }

    private func comparisonColumn(_ label: String, _ title: String, _ duration: String, _ effort: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(duration).font(.caption.monospacedDigit())
            Text(effort).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func currentComparisonTitle(_ original: ActivitySuggestionPayload) -> String {
        // Duration has its own exact-value line; remove only recognized leading duration prose.
        let title = localizedTitle(original).replacingOccurrences(
            of: #"^\s*\d+(?:[.:]\d+)?\s*(?:min(?:ute)?s?|分钟|分)\s*[·:–-]?\s*"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = title.first else { return title }
        return first.uppercased() + title.dropFirst()
    }

    private var durationPresets: [Int] {
        guard maximumMinutes >= 5 else { return [] }
        let options = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 300, 360]
            .filter { $0 <= maximumMinutes && $0 < originalMinutes }
        let target = Double(originalMinutes) * 0.75
        return Array(options.sorted { abs(Double($0) - target) < abs(Double($1) - target) }.prefix(3)).sorted()
    }

    private var removesTargets: Bool {
        guard reason != nil, action == "easy" || action == "shorter" else { return false }
        if let displayedOverride {
            return displayedOverride.targetDistanceMeters != nil
                || displayedOverride.coachingTarget?.pace != nil
                || displayedOverride.workoutSteps.contains { $0.coachingTarget?.phase == .work }
        }
        guard let original else { return false }
        return original.catalogWorkout != nil || original.distanceMeters != nil || original.targetCalories != nil
            || ["pace", "heartRate", "power"].contains(original.intensityModel)
            || !["easy", "easyAerobic", "recovery", "rest"].contains(original.stimulus)
    }

    private var proposedTitle: String {
        if action == "catalog", let selectedWorkout { return selectedWorkout.title }
        if isRest { return String(localized: "today.change.rest", defaultValue: "Rest today") }
        return reason == nil || action == "catalog" ? String(localized: "today.change.prompt", defaultValue: "Choose a change") : String(localized: "today.change.easy_session", defaultValue: "Easy session")
    }
    private var proposedDuration: String {
        guard reason != nil else { return "—" }
        if action == "catalog", let workout = selectedWorkout {
            let secs = workout.targetDistanceMeters.map { Int(($0 / 1000 * 420).rounded()) } ?? workout.steps.reduce(0) { $0 + $1.durationSeconds }
            return workout.targetDistanceMeters.map { String(format: String(localized: "today.change.distance_estimate", defaultValue: "%1$@ · about %2$@"), measurementPreferences.unitSystem.distanceString(meters: $0, fractionDigits: 1), durationLabel(secs)) } ?? durationLabel(secs)
        }
        if isRest { return String(localized: "today.change.rest_short", defaultValue: "Rest") }
        return validMinutes.map(minuteLabel) ?? "—"
    }
    private var proposedEffort: String {
        guard reason != nil else { return "—" }
        if action == "catalog", let workout = selectedWorkout {
            let values = workout.guideInstructions.segments.map(\.effort)
            return String(format: String(localized: "today.change.rpe_range", defaultValue: "RPE %1$d–%2$d"), locale: .autoupdatingCurrent, values.map(\.rpeMin).min() ?? 1, values.map(\.rpeMax).max() ?? 2)
        }
        if isRest { return "—" }
        return validMinutes == nil ? "—" : String(localized: "Very easy")
    }

    private func catalogPreview(_ workout: StandaloneWorkout) -> some View {
        DisclosureGroup(String(localized: "today.change.workout_details", defaultValue: "Workout details"), isExpanded: $detailsExpanded) {
            Text(workout.subtitle).font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if workout.targetDistanceMeters != nil {
                Text(String(localized: "today.change.estimate_basis", defaultValue: "Time is an estimate at 7 min/km. The workout ends at the selected distance."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(workout.steps) { step in
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.label).font(.subheadline.weight(.semibold))
                    Text(durationLabel(step.durationSeconds)).font(.caption)
                    if let detail = step.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }

    private func recommendation(_ pendingAdjustment: AdjustmentProposalDTO) -> some View {
        DisclosureGroup(String(localized: "today.adjustment.recommendation.title", defaultValue: "Recommended plan update")) {
            Text(pendingAdjustment.explanation).font(.subheadline)
            ForEach(Array(pendingAdjustment.changes.enumerated()), id: \.offset) { _, change in
                Text(change.beforeTitle).font(.caption).strikethrough().foregroundStyle(.secondary)
                Text(change.afterTitle).font(.subheadline.weight(.semibold))
            }
            HStack {
                Button(String(localized: "today.adjustment.apply", defaultValue: "Apply update")) { onDecision(true) }.frame(minHeight: 44)
                Button(String(localized: "today.adjustment.keep", defaultValue: "Keep original plan")) { onDecision(false) }.frame(minHeight: 44)
            }
        }
    }

    private func choose(_ choice: ReadinessChoice) {
        reason = choice
        selectedWorkout = nil
        setAction(choice == .sore ? "rest" : choice == .shortOnTime ? "shorter" : "easy")
    }

    private func setAction(_ value: String) {
        action = value
        if value == "shorter" {
            minutesText = String(max(5, min(maximumMinutes, Int(Double(originalMinutes) * 0.75))))
        } else if value == "easy" {
            minutesText = String(max(5, maximumMinutes))
        } else { minutesText = "" }
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
