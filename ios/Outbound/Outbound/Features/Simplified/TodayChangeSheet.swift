import SwiftUI
import os

struct TodayWorkoutEditPresentation: Identifiable {
    let id = UUID()
    let baseline: ActivitySuggestionResponse?
    let displayedOverride: SessionIntent?
}

struct TodayWorkoutChangeSelection {
    let baseline: ActivitySuggestionResponse?
    let reason: String?
    let change: WorkoutEditApplyRequestDTO.Change
}

struct TodayChangeSheet: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.plainstride.outbound", category: "workout-edit")
    @Environment(\.dismiss) private var dismiss
    @Environment(\.outboundTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @FocusState private var editingTarget: Bool
    @ScaledMetric(relativeTo: .title3) private var targetFieldWidth = 104
    @State private var reason = "none"
    @State private var goalKind = "time"
    @State private var targetText = ""
    @State private var effortPreset = "unchanged"
    @State private var showsCatalog = false
    @State private var showsReasonPicker = false
    @State private var confirmsSkip = false
    @State private var contentHeight: CGFloat = 380
    @State private var selectedDetent: PresentationDetent = .height(488)
    @State private var footerHeight: CGFloat = 64
    @State private var submitting = false
    @State private var failed = false

    let baseline: ActivitySuggestionResponse?
    private var original: ActivitySuggestionPayload? { baseline?.primary }
    let displayedOverride: SessionIntent?
    private var context: WorkoutEditContextDTO? { baseline?.editContext }
    private var recoveryAdvised: Bool { baseline?.recoveryAdvised == true }
    let pendingAdjustment: AdjustmentProposalDTO?
    let busy: Bool
    let onApply: (TodayWorkoutChangeSelection) async -> Bool
    let onDecision: (Bool) -> Void

    private var seconds: Int {
        if let displayedOverride {
            let total = displayedOverride.workoutSteps.reduce(0) { $0 + $1.durationSeconds }
            return total > 0 ? total : displayedOverride.targetDurationSeconds ?? original?.durationSeconds ?? 0
        }
        return original?.durationSeconds ?? (original?.durationMinutes ?? 0) * 60
    }
    private var currentTitle: String {
        if let displayedOverride { return BuiltinWorkoutText.localized(displayedOverride.title) }
        guard let original else { return "" }
        return (original.effectiveWorkout ?? original.catalogWorkout).map { $0.withCatalogVersion(original.catalogVersion ?? 1).title } ?? BuiltinWorkoutText.localized(original.title)
    }
    private var currentDistance: Double? { displayedOverride != nil ? displayedOverride?.targetDistanceMeters : original?.distanceMeters }
    private var currentEffortLabel: String { displayedOverride?.detail ?? BuiltinWorkoutText.localized(original?.effortLabel ?? "Easy") }
    private var canEditTarget: Bool { displayedOverride == nil && (context?.canEditTarget ?? true) }
    private var canEditEffort: Bool { displayedOverride == nil && (context?.canEditEffort ?? true) }
    // Local draft bounds are input guardrails, not server authorization.
    private var minimumDuration: Int { context?.minimumDurationSeconds ?? 300 }
    private var maximumDuration: Int { context?.maximumDurationSeconds ?? 21_600 }
    private var minimumDistance: Double { context?.minimumDistanceMeters ?? 100 }
    private var maximumDistance: Double { context?.maximumDistanceMeters ?? 50_000 }
    private var effortPresetIDs: [String] { context.map { $0.effortPresets.map(\.id) } ?? ["veryEasy", "easy", "steady"] }
    private var distanceScale: Double { measurementPreferences.unitSystem == .imperial ? 1609.344 : 1000 }
    private var distanceUnit: String { measurementPreferences.unitSystem == .imperial ? "mi" : "km" }
    private var optionalReason: String? { reason == "none" ? nil : reason }
    private var parsedTarget: WorkoutEditApplyRequestDTO.Target? {
        if goalKind == "distance" {
            guard let number = Double(targetText.replacingOccurrences(of: ",", with: ".")) else { return nil }
            let meters = number * distanceScale
            guard meters >= minimumDistance && meters <= maximumDistance else { return nil }
            return .init(kind: "distance", meters: meters)
        }
        let parts = targetText.split(separator: ":", omittingEmptySubsequences: false)
        guard let minutes = Int(parts.first ?? ""), parts.count <= 2 else { return nil }
        let remainder = parts.count == 2 ? Int(parts[1]) : 0
        guard let remainder, (0...59).contains(remainder),
              minutes >= 0, minutes <= maximumDuration / 60 else { return nil }
        let value = minutes * 60 + remainder
        guard value >= minimumDuration && value <= maximumDuration else { return nil }
        return .init(kind: "time", seconds: value)
    }
    private var changedTarget: WorkoutEditApplyRequestDTO.Target? {
        guard let parsedTarget else { return nil }
        if parsedTarget.kind == "time" && original?.distanceMeters == nil && parsedTarget.seconds == seconds { return nil }
        if parsedTarget.kind == "distance", let old = original?.distanceMeters, abs((parsedTarget.meters ?? 0) - old) < 1 { return nil }
        return parsedTarget
    }
    private var changedEffort: String? { effortPreset == "unchanged" || effortPreset == context?.currentEffortPreset ? nil : effortPreset }
    private var canApply: Bool { displayedOverride == nil && (!canEditTarget || parsedTarget != nil) && (changedTarget != nil || changedEffort != nil) }

    private var footerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: OutboundSpacing.compact))
            : AnyLayout(HStackLayout(spacing: OutboundSpacing.standard))
    }

    var body: some View {
        NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                        if original != nil || displayedOverride != nil {
                            Text(currentTitle)
                                .font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            if recoveryAdvised {
                                Text(String(localized: "today.recovery.choice", defaultValue: "Choose a short, very easy recovery workout, or skip today. Your planned workout changes only after you apply your choice."))
                                    .font(.body).fixedSize(horizontal: false, vertical: true)
                            } else {
                                targetControls
                                effortControl
                            }
                            if displayedOverride != nil {
                                Text(String(localized: "today.edit.local_setup", defaultValue: "This session has its own setup. Choose another workout to save a replacement for today."))
                                    .font(.body).foregroundStyle(.secondary)
                            } else if context?.limitation != nil {
                                Text(String(localized: "today.edit.structured", defaultValue: "This workout keeps its phases and targets. Choose another workout to change them."))
                                    .font(.body).foregroundStyle(.secondary)
                            } else if context?.canConvertGoal == false && changedTarget != nil {
                                Text(String(localized: "today.edit.phases", defaultValue: "Warmup and cooldown stay the same. The main part changes."))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Button(String(localized: "today.change.choose", defaultValue: "Choose another workout")) {
                                editingTarget = false; showsCatalog = true
                            }.frame(minHeight: 44).accessibilityIdentifier("todayEditChooseWorkout")
                                .disabled(original.flatMap { SportType(rawValue: $0.modality) } == nil || (displayedOverride != nil && displayedOverride?.sport.rawValue != original?.modality))
                            reasonControl
                        } else {
                            Text(String(localized: "today.edit.unavailable", defaultValue: "Refresh Today to edit the current workout."))
                                .font(.body)
                        }
                        if let pendingAdjustment { recommendation(pendingAdjustment) }
                    }
                    .padding(OutboundSpacing.screen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        contentHeight = height
                        if selectedDetent != .large { selectedDetent = .height(min(UIScreen.main.bounds.height * 0.85, height + footerHeight + 44)) }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                footerLayout {
                    if editingTarget {
                        Button(String(localized: "common.done", defaultValue: "Done")) { editingTarget = false }.frame(minHeight: 44)
                    } else {
                        Button(role: .destructive) { confirmsSkip = true } label: {
                            Text(String(localized: "today.edit.skip", defaultValue: "Skip today"))
                        }.frame(minHeight: 44).disabled(displayedOverride != nil).accessibilityIdentifier("todayEditSkip")
                    }
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    if busy { ProgressView().accessibilityLabel(String(localized: "today.edit.saving", defaultValue: "Saving…")) }
                    if !recoveryAdvised {
                    OutboundPrimaryButton(title: String(localized: "today.change.apply", defaultValue: "Apply"), systemImage: "checkmark", expands: false) {
                        editingTarget = false
                        save(.init(baseline: baseline, reason: optionalReason, change: .init(operation: "edit", edits: .init(target: changedTarget, effortPreset: changedEffort))))
                    }.disabled(!canApply || busy).accessibilityIdentifier("todayChangeApply")
                    }
                }
                .padding(.horizontal, OutboundSpacing.screen).padding(.vertical, OutboundSpacing.compact)
                .background(OutboundPalette.background)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    footerHeight = height
                    if selectedDetent != .large { selectedDetent = .height(min(UIScreen.main.bounds.height * 0.85, contentHeight + height + 44)) }
                }
            }
            .background(OutboundPalette.background)
            .navigationTitle(String(localized: "today.change.sheet_title", defaultValue: "Change workout"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "today.change.cancel", defaultValue: "Cancel")) { dismiss() }
                        .frame(minHeight: 44).disabled(busy || submitting)
                }
            }
            .disabled(busy || submitting)
            .overlay(alignment: .top) {
                if failed {
                    Text(String(localized: "today.change.failed", defaultValue: "Could not save. Your changes are kept. Try again, or reopen Change workout to refresh."))
                        .font(.body).padding(OutboundSpacing.standard)
                        .background(OutboundPalette.surface, in: RoundedRectangle(cornerRadius: OutboundRadius.card))
                        .padding(OutboundSpacing.screen).accessibilityIdentifier("todayEditFailure")
                        .allowsHitTesting(false)
                }
            }
            .sheet(isPresented: $showsCatalog) {
                StandaloneWorkoutPickerView(sport: original.flatMap { SportType(rawValue: $0.modality) } ?? .run,
                    recoveryMaximumSeconds: recoveryAdvised ? min(seconds, 30 * 60) : nil,
                    onUse: { workout in
                        let success = await onApply(.init(baseline: baseline, reason: optionalReason, change: .init(operation: "replace", catalogWorkoutId: workout.id, catalogVersion: workout.catalogVersion)))
                        return success
                    }, onSelect: { _ in })
                    .interactiveDismissDisabled(busy || submitting)
            }
            .sheet(isPresented: $showsReasonPicker) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                            ForEach(["none", "lessTime", "lowEnergy", "soreness", "other"], id: \.self) { value in
                                Button {
                                    reason = value; showsReasonPicker = false
                                } label: {
                                    HStack(spacing: OutboundSpacing.compact) {
                                        Text(reasonTitle(value)).font(.body).fixedSize(horizontal: false, vertical: true)
                                        if reason == value { Image(systemName: "checkmark").accessibilityHidden(true) }
                                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }.buttonStyle(.plain).accessibilityIdentifier("todayEditReasonOption-" + value)
                                    .accessibilityAddTraits(reason == value ? .isSelected : [])
                            }
                        }.padding(OutboundSpacing.screen)
                    }
                    .background(OutboundPalette.background)
                    .navigationTitle(String(localized: "today.edit.reason", defaultValue: "Reason (optional)"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "today.change.cancel", defaultValue: "Cancel")) { showsReasonPicker = false }
                        }
                    }
                }.presentationDetents([.large])
            }
            .confirmationDialog(String(localized: "today.edit.skip_confirm", defaultValue: "Skip today’s workout?"), isPresented: $confirmsSkip, titleVisibility: .visible) {
                Button(String(localized: "today.edit.skip", defaultValue: "Skip today"), role: .destructive) {
                    save(.init(baseline: baseline, reason: optionalReason, change: .init(operation: "skip")))
                }
                Button(String(localized: "today.change.cancel", defaultValue: "Cancel"), role: .cancel) { }
            }
        }
        .interactiveDismissDisabled(busy || submitting)
        .presentationDetents([.height(min(UIScreen.main.bounds.height * 0.85, contentHeight + footerHeight + 44)), .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
        .onAppear {
            goalKind = currentDistance == nil ? "time" : "distance"
            resetTarget()
            effortPreset = displayedOverride == nil ? context?.currentEffortPreset ?? "unchanged" : "unchanged"
            if context?.canEditTarget == false || context?.canEditEffort == false || context?.canConvertGoal == false {
                let limitation: String
                switch context?.limitation {
                case .some("structuredWorkout"): limitation = "structuredWorkout"
                case .some("unsupportedTargets"): limitation = "unsupportedTargets"
                case nil: limitation = "none"
                default: limitation = "other"
                }
                let slotPrescriptionDiffers = original.map { primary in
                    primary.plannedWorkoutId.map { primary.id != "planned-\($0)" } ?? false
                } ?? false
                Self.logger.info("Workout edit capability restricted limitation=\(limitation, privacy: .public) target=\(context?.canEditTarget ?? false, privacy: .public) effort=\(context?.canEditEffort ?? false, privacy: .public) goal=\(context?.canConvertGoal ?? false, privacy: .public) planned=\(original?.plannedWorkoutId != nil, privacy: .public) slotPrescriptionDiffers=\(slotPrescriptionDiffers, privacy: .public)")
            }
        }
        .task(id: failed) {
            guard failed else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }; failed = false
        }
    }

    private var targetControls: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
            Text(String(localized: "today.edit.goal", defaultValue: "Goal")).font(.headline)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: OutboundSpacing.compact))
                : AnyLayout(HStackLayout(spacing: OutboundSpacing.standard))
            layout { goalMenu; targetField }
            if canEditTarget && parsedTarget == nil {
                Text(targetRangeHint)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    private var targetRangeHint: String {
        if goalKind == "time" {
            return String(format: String(localized: "today.edit.time_range", defaultValue: "Enter %@–%@ min. You can also use minutes:seconds."),
                String(minimumDuration / 60), String(maximumDuration / 60))
        }
        let lower = ceil(minimumDistance / distanceScale * 100) / 100
        let upper = floor(maximumDistance / distanceScale * 100) / 100
        return String(format: String(localized: "today.edit.distance_range", defaultValue: "Enter %@–%@ %@."),
            String(format: "%.2f", locale: .autoupdatingCurrent, lower), String(format: "%.2f", locale: .autoupdatingCurrent, upper), distanceUnit)
    }
    private var goalTitle: String {
        goalKind == "time" ? String(localized: "today.edit.time", defaultValue: "Time") : String(localized: "today.edit.distance", defaultValue: "Distance")
    }
    @ViewBuilder private var goalMenu: some View {
        if displayedOverride == nil && (context?.canConvertGoal ?? true) {
            Menu {
                Button(String(localized: "today.edit.time", defaultValue: "Time")) { goalKind = "time"; resetTarget() }
                Button(String(localized: "today.edit.distance", defaultValue: "Distance")) { goalKind = "distance"; resetTarget() }
            } label: {
                selectorLabel(goalTitle)
            }.accessibilityIdentifier("todayEditGoal")
        } else {
            Text(goalTitle).font(.body).frame(minHeight: 44)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("todayEditGoal")
        }
    }
    private var targetField: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: OutboundSpacing.compact))
            : AnyLayout(HStackLayout(spacing: OutboundSpacing.compact))
        return layout {
            TextField("", text: $targetText).font(.title3.monospacedDigit()).keyboardType(goalKind == "time" ? .numbersAndPunctuation : .decimalPad)
                .focused($editingTarget).frame(width: min(targetFieldWidth, 240)).frame(minHeight: 44)
                .accessibilityLabel(goalKind == "time" ? String(localized: "today.edit.time", defaultValue: "Time") : String(localized: "today.edit.distance", defaultValue: "Distance"))
                .accessibilityIdentifier("todayEditTarget")
            Text(goalKind == "time" ? (targetText.contains(":") ? String(localized: "today.edit.minutes_seconds_unit", defaultValue: "min:sec") : String(localized: "today.change.minutes_unit", defaultValue: "min")) : distanceUnit).font(.body).foregroundStyle(.secondary)
        }
        .padding(.horizontal, OutboundSpacing.compact)
        .background(OutboundPalette.surface, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
        .fixedSize(horizontal: true, vertical: false).disabled(!canEditTarget)
    }
    private var effortControl: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: OutboundSpacing.standard))
        return layout {
            Text(String(localized: "today.edit.effort", defaultValue: "Effort")).font(.headline)
            Menu {
                Button(currentEffortLabel) { effortPreset = "unchanged" }
                ForEach(effortPresetIDs, id: \.self) { id in
                    Button(effortTitle(id)) { effortPreset = id }
                }
            } label: {
                selectorLabel(effortPreset == "unchanged" ? currentEffortLabel : effortTitle(effortPreset))
            }.disabled(!canEditEffort).accessibilityIdentifier("todayEditEffort")
        }
    }
    private var reasonControl: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: OutboundSpacing.standard))
        return layout {
            Text(String(localized: "today.edit.reason", defaultValue: "Reason (optional)")).font(.headline)
            if dynamicTypeSize.isAccessibilitySize {
                Button { editingTarget = false; showsReasonPicker = true } label: { reasonMenuLabel }
                    .accessibilityIdentifier("todayEditReason")
            } else {
                Menu {
                    ForEach(["none", "lessTime", "lowEnergy", "soreness", "other"], id: \.self) { value in
                        Button(reasonTitle(value)) { reason = value }
                    }
                } label: { reasonMenuLabel }.accessibilityIdentifier("todayEditReason")
            }
        }
    }
    private var reasonMenuLabel: some View {
        selectorLabel(reasonTitle(reason)).foregroundStyle(theme.accentColor)
    }
    private func selectorLabel(_ title: String) -> some View {
        HStack(spacing: OutboundSpacing.compact) {
            Text(title).font(.body).fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
    }
    private func reasonTitle(_ value: String) -> String {
        switch value {
        case "lessTime": String(localized: "today.change.less_time", defaultValue: "Less time")
        case "lowEnergy": String(localized: "today.change.low_energy", defaultValue: "Low energy")
        case "soreness": String(localized: "today.edit.soreness", defaultValue: "Soreness")
        case "other": String(localized: "today.edit.other", defaultValue: "Other")
        default: String(localized: "today.edit.none", defaultValue: "None")
        }
    }
    private func effortTitle(_ value: String) -> String {
        switch value {
        case "veryEasy": String(localized: "Very easy")
        case "steady": String(localized: "Steady")
        default: String(localized: "Easy")
        }
    }
    private func resetTarget() {
        if goalKind == "time" { targetText = seconds % 60 == 0 ? String(seconds / 60) : "\(seconds / 60):\(String(format: "%02d", seconds % 60))" }
        else { targetText = String(format: "%.2f", locale: .autoupdatingCurrent, (currentDistance ?? Double(seconds) / 420 * 1000) / distanceScale) }
    }
    private func save(_ selection: TodayWorkoutChangeSelection) {
        guard !submitting && !busy else { return }
        failed = false
        submitting = true
        Task {
            failed = !(await onApply(selection)); submitting = false
            if failed { UIAccessibility.post(notification: .announcement,
                argument: String(localized: "today.change.failed", defaultValue: "Could not save. Your changes are kept. Try again, or reopen Change workout to refresh.")) }
        }
    }
    private func recommendation(_ proposal: AdjustmentProposalDTO) -> some View {
        DisclosureGroup(String(localized: "today.adjustment.recommendation.title", defaultValue: "Recommended plan update")) {
            Text(proposal.explanation).font(.body)
            ForEach(Array(proposal.changes.enumerated()), id: \.offset) { _, change in
                Text(change.beforeTitle).font(.body).strikethrough().foregroundStyle(.secondary)
                Text(change.afterTitle).font(.body.weight(.semibold))
            }
            Button(String(localized: "today.adjustment.apply", defaultValue: "Apply update")) { onDecision(true) }.frame(minHeight: 44)
            Button(String(localized: "today.adjustment.keep", defaultValue: "Keep original plan")) { onDecision(false) }.frame(minHeight: 44)
        }
    }
}
