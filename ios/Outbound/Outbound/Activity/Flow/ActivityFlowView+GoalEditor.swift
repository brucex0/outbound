import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

extension ActivityFlowView {
    func sessionGoalCard(for intent: SessionIntent) -> some View {
        Button {
            model.setup.selectedGoalMode = SessionGoalMode(goal: intent.activityGoal)
            model.track(.init(.goalEditorOpened, properties: [
                .activityType: .string(intent.resolvedActivityType.rawValue),
                .goalType: .string(model.analyticsGoalType)
            ]))
            model.setup.setupSheet = .goal
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "flag.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .frame(width: 28)
                Text(String(localized: "record.goal.title", defaultValue: "Goal"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(intent.activityGoal.label(unitSystem: model.dependencies.measurementPreferences.unitSystem))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let estimate = model.setup.calorieEstimateLabel(for: intent) {
                        Text(estimate)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: model.startSetupCardCornerRadius, style: .continuous))
        .onAppear {
            model.setup.selectedGoalMode = SessionGoalMode(goal: intent.activityGoal)
        }
    }

    var goalValueEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.setup.goalEditorKind != nil {
                Button {
                    model.autoStopAtGoalEnabled.toggle()
                    model.track(.init(.activityConfigurationChanged, properties: [
                        .changeType: .string("auto_stop_at_goal"),
                        .selectionType: .string(model.autoStopAtGoalEnabled ? "enabled" : "disabled"),
                        .activityType: .string((model.setup.plannedIntent ?? .freestyleRun).resolvedActivityType.rawValue)
                    ]))
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.autoStopAtGoalEnabled ? "checkmark.square.fill" : "square")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(model.autoStopAtGoalEnabled ? theme.accentColor : Color.secondary)
                        Text(String(localized: "today.stop.at.goal", defaultValue: "Pause at goal"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("activity.goal.pauseAtGoal")
                .accessibilityLabel(String(localized: "today.stop.at.goal", defaultValue: "Pause at goal"))
                .accessibilityValue(model.autoStopAtGoalEnabled
                    ? String(localized: "common.on", defaultValue: "On")
                    : String(localized: "common.off", defaultValue: "Off"))
            }

            if let kind = model.setup.goalEditorKind {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.setup.goalEditorPresetGoals(for: kind), id: \.self) { goal in
                            goalPresetButton(
                                title: model.setup.goalEditorPresetTitle(goal),
                                isSelected: model.setup.goalEditorSelection == goal
                            ) {
                                model.setup.goalEditorSelection = goal
                                customGoalTextBinding(for: kind).wrappedValue = ""
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField(
                        model.setup.customGoalAlertTitle(for: kind),
                        text: goalEditorTextBinding(for: kind),
                        prompt: Text("0")
                    )
                    .accessibilityIdentifier("activity.goal.custom")
                    .keyboardType(kind == .distance ? .decimalPad : .numberPad)
                    .font(.body.monospacedDigit().weight(.semibold))
                    .focused($focusedCustomGoalKind, equals: kind)

                    Text(model.setup.customGoalUnitLabel(for: kind))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                }
            }

            HStack(spacing: 12) {
                Button(String(localized: "common.cancel", defaultValue: "Cancel")) {
                    dismissGoalEditor()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("activity.goal.cancel")
                .frame(maxWidth: .infinity)

                Button(String(localized: "common.done", defaultValue: "Done")) {
                    saveGoalEditorSelection()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("activity.goal.done")
                .tint(.orange)
                .frame(maxWidth: .infinity)
                .disabled(model.setup.goalEditorGoal == nil)
            }
        }
    }

    func dismissGoalEditor() {
        focusedCustomGoalKind = nil
        model.setup.goalEditorSelection = nil
        model.setup.setupSheet = nil
    }

    func saveGoalEditorSelection() {
        guard let goal = model.setup.goalEditorGoal, model.applyGoal(goal, selectionType: model.setup.goalEditorSelection == nil ? "custom" : "preset") else { return }
        focusedCustomGoalKind = nil
        model.setup.goalEditorSelection = nil
        model.setup.setupSheet = nil
    }

    var routeSetupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let route = model.setup.plannedIntent?.preparedRoute {
                RoutePreviewMap(points: route.directedPoints, showsEndpoints: true)
                    .id("\(route.source.rawValue)-\(route.id)-\(route.direction.rawValue)")
                    .frame(height: 138)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(route.name)
                            .font(.headline)
                            .lineLimit(1)
                        Text(model.routeDistanceLabel(route))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(String(localized: "common.change", defaultValue: "Change")) { model.openRouteLibrary() }
                        .font(.subheadline.weight(.semibold))
                    Button(role: .destructive) { model.removeSelectedRoute(route) } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel(String(localized: "record.route.remove", defaultValue: "Remove route"))
                }

                if let advisory = model.routeGoalAdvisory(route) {
                    Label(advisory, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker(
                    String(localized: "record.route.direction", defaultValue: "Direction"),
                    selection: Binding(
                        get: { route.direction },
                        set: { model.updateRouteDirection($0, for: route) }
                    )
                ) {
                    Text(String(localized: "record.route.direction.saved", defaultValue: "As saved"))
                        .tag(RouteDirection.forward)
                    Text(String(localized: "record.route.direction.reverse", defaultValue: "Reverse"))
                        .tag(RouteDirection.reverse)
                }
                .pickerStyle(.segmented)
                .accessibilityHint(String(localized: "record.route.direction.hint", defaultValue: "Choose which endpoint you intend to start from."))
            } else if let routeName = model.setup.plannedIntent?.routeName {
                HStack(spacing: 12) {
                    Image(systemName: "map.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(routeName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(String(localized: "record.route.preview_unavailable", defaultValue: "Preview unavailable for this route"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(String(localized: "common.change", defaultValue: "Change")) { model.openRouteLibrary() }
                        .font(.subheadline.weight(.semibold))
                    Button(role: .destructive) { model.removeNamedRoute() } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel(String(localized: "record.route.remove", defaultValue: "Remove route"))
                }
            } else {
                Button(action: model.openRouteLibrary) {
                    HStack(spacing: 12) {
                        Image(systemName: "map.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "record.setup.route", defaultValue: "Route"))
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(String(localized: "record.route.choose", defaultValue: "Choose a route and preview it here"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: model.startSetupCardCornerRadius, style: .continuous))
    }

    func plannedWorkoutCard(for intent: SessionIntent) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(String(localized: "record.workout_plan.title", defaultValue: "Workout plan"), systemImage: "list.bullet.clipboard")
                    .font(.headline)
                Spacer()
                Text(model.setup.plannedWorkoutDurationLabel(for: intent))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(intent.workoutSteps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Color.orange, in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.label)
                                .font(.subheadline.weight(.semibold))
                            if let detail = step.detail, !detail.isEmpty {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 8)

                        Text(model.setup.workoutStepDurationLabel(step.durationSeconds))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)

                    if index < intent.workoutSteps.count - 1 {
                        Divider()
                            .padding(.leading, 36)
                    }
                }
            }

            if intent.allowsCalorieGoal {
                Button {
                    model.track(.init(.goalEditorOpened, properties: [
                        .activityType: .string(intent.resolvedActivityType.rawValue),
                        .goalType: .string("calories")
                    ]))
                    if model.setup.hasWeightForCalories {
                        model.setup.selectedGoalMode = .calories
                        model.setup.setupSheet = .goal
                    } else {
                        model.presentCaloriesWeightPrompt(for: .selectMode(reopenGoalEditor: true))
                    }
                } label: {
                    Label(
                        String(localized: "record.goal.use_calories", defaultValue: "Use Calories instead"),
                        systemImage: "flame.fill"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: model.startSetupCardCornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    func goalPresetButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, isSelected ? 18 : 20)
            .frame(height: 40)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? Color.orange : Color(.tertiarySystemBackground), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activity.goal.preset.\(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    func customGoalTextBinding(for kind: CustomGoalKind) -> Binding<String> {
        Binding(
            get: {
                switch kind {
                case .distance: return model.setup.customDistanceText
                case .time: return model.setup.customTimeText
                case .calories: return model.setup.customCaloriesText
                }
            },
            set: { value in
                switch kind {
                case .distance: model.setup.customDistanceText = value
                case .time: model.setup.customTimeText = value
                case .calories: model.setup.customCaloriesText = value
                }
            }
        )
    }

    func goalEditorTextBinding(for kind: CustomGoalKind) -> Binding<String> {
        let text = customGoalTextBinding(for: kind)
        return Binding(
            get: { text.wrappedValue },
            set: { value in
                text.wrappedValue = value
                model.setup.goalEditorSelection = nil
            }
        )
    }
}
