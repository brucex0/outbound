import SwiftUI

/// Today experiment: one contextual entry, with the existing domain editors.
/// The standalone launch surface keeps its current pills and goal card.
extension ActivityFlowView {
    @ViewBuilder
    var compactLaunchGoalCard: some View {
        if model.setup.selectedGoalMode == .freestyle {
            Button(action: openCompactLaunchModes) {
                HStack(spacing: OutboundSpacing.compact) {
                    Image(systemName: "plus")
                        .accessibilityHidden(true)
                    Text(String(localized: "record.goal.set_goal_workout", defaultValue: "Set goal"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, OutboundSpacing.compact)
                .frame(minHeight: 44)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
                .outboundTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("activity.goal.edit")
            .accessibilityHint(String(localized: "record.goal.mode_picker_hint", defaultValue: "Choose a goal or workout mode"))
        } else {
            // Independent sibling targets: opening the selector must never
            // toggle Pause at goal, and the pause control never opens a sheet.
            HStack(spacing: 0) {
                Button(action: openCompactLaunchModes) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(compactGoalTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !compactGoalSummary.isEmpty {
                            Text(compactGoalSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .outboundTapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("activity.goal.edit")
                .accessibilityHint(String(localized: "record.goal.mode_picker_hint", defaultValue: "Choose a goal or workout mode"))

                if [.distance, .time, .calories].contains(model.setup.selectedGoalMode) {
                    Button(action: model.toggleSetupPauseAtGoal) {
                        Image(systemName: model.autoStopAtGoalEnabled ? "pause.circle.fill" : "pause.circle")
                            .font(.title2)
                            .foregroundStyle(model.autoStopAtGoalEnabled ? theme.actionColor : Color.secondary)
                            .outboundTapTarget()
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                    .accessibilityIdentifier("activity.goal.pauseAtGoal")
                    .accessibilityLabel(String(localized: "today.stop.at.goal", defaultValue: "Pause at goal"))
                    .accessibilityValue(model.autoStopAtGoalEnabled
                        ? String(localized: "common.on", defaultValue: "On")
                        : String(localized: "common.off", defaultValue: "Off"))
                    .accessibilityAddTraits(model.autoStopAtGoalEnabled ? .isSelected : [])
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: OutboundRadius.card, style: .continuous))
        }
    }

    private func openCompactLaunchModes() {
        model.track(.init(.goalEditorOpened, properties: [
            .activityType: .string(model.setup.setupActivityType.rawValue),
            .goalType: .string(model.analyticsGoalType),
            .entrySource: .string("compact_goal_card")
        ]))
        model.setup.setupSheet = .mode
    }

    var launchModeChoices: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach([SessionGoalMode.freestyle, .distance, .time, .calories, .curated, .race]
                    .filter { model.setup.availableManualGoalModes.contains($0) }, id: \.self) { mode in
                    Button {
                        model.setup.pendingLaunchMode = mode
                        model.setup.setupSheet = nil
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.systemImage)
                                .frame(width: 24)
                                .foregroundStyle(theme.accentColor)
                            Text(mode.pillTitle)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if mode == model.setup.selectedGoalMode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(theme.accentColor)
                            }
                        }
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .outboundTapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("activity.goal.mode.\(mode.rawValue)")
                    .accessibilityAddTraits(mode == model.setup.selectedGoalMode ? .isSelected : [])
                }
            }
            .padding(16)
        }
        .accessibilityIdentifier("activity.launch.modes")
    }

    private var compactGoalTitle: String {
        let key: String
        let value: String
        switch model.setup.selectedGoalMode {
        case .curated:
            key = String(localized: "record.goal.workout_format", defaultValue: "Workout: %@")
            value = model.setup.curatedWorkoutIntent?.title ?? model.setup.launchGoalValue
        case .race:
            key = String(localized: "record.goal.race_format", defaultValue: "Race: %@")
            if let race = model.setup.plannedIntent?.raceIntent {
                value = model.dependencies.measurementPreferences.unitSystem.distanceString(meters: race.distanceMeters, fractionDigits: 1)
            } else { value = model.setup.launchGoalValue }
        default:
            key = String(localized: "record.goal.goal_format", defaultValue: "Goal: %@")
            value = model.setup.launchGoalValue
        }
        return String(format: key, locale: .autoupdatingCurrent, value)
    }

    private var compactGoalSummary: String {
        if model.setup.selectedGoalMode == .curated, let intent = model.setup.curatedWorkoutIntent {
            // The catalog's authored prescription includes the real target and
            // work set (for example, 30 min · 4 × 2 min fast), already localized
            // with the selected snapshot. Route labels never replace this text.
            return intent.detail
        }
        if model.setup.selectedGoalMode == .race, let race = model.setup.plannedIntent?.raceIntent {
            switch race.pacingStrategy {
            case .effortBased:
                return String(localized: "race.planner.effort", defaultValue: "Finish by feel")
            case .even, .negativeSplit:
                let strategy = race.pacingStrategy == .even
                    ? String(localized: "race.planner.even", defaultValue: "Even effort")
                    : String(localized: "race.planner.negative_split", defaultValue: "Patient start, stronger finish")
                let target = race.goalTimeSeconds.map(ActivitySetupViewModel.raceDurationLabel)
                return [target, strategy].compactMap { $0 }.joined(separator: " · ")
            }
        }
        return model.setup.selectedGoalMode == .calories ? model.setup.launchGoalHint : ""
    }
}
