import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var coachCatalog: CoachCatalogStore

    let onComplete: (Bool) -> Void

    private var accentColor: Color {
        coachCatalog.selectedPersona.face.onboardingAccentColor
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    progressHeader
                    content
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 120)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                footer
                    .background(.regularMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if onboardingStore.step != .welcome {
                        Button {
                            onboardingStore.goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Back")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        onComplete(false)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch onboardingStore.step {
        case .welcome:
            welcomeStep
        case .goal:
            goalStep
        case .body:
            bodyStep
        case .baseline:
            baselineStep
        case .review:
            reviewStep
        case .setup:
            setupStep
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases) { step in
                    Capsule()
                        .fill(step.rawValue <= onboardingStore.step.rawValue ? accentColor : Color.primary.opacity(0.12))
                        .frame(height: 5)
                }
            }

            Text(onboardingStore.progressText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .animation(.easeOut(duration: 0.18), value: onboardingStore.step)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "sparkles")
                .font(.system(size: 70, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("Outbound")
                    .font(.largeTitle.bold())
                Text("Tell your coach the real story. We will turn it into a first session and a plan that fits.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                onboardingPromiseRow(
                    systemImage: "text.bubble.fill",
                    title: "Use your own words",
                    detail: "Goals, constraints, and worries do not need to fit a tiny list."
                )
                onboardingPromiseRow(
                    systemImage: "figure.run.circle.fill",
                    title: "Start with today",
                    detail: "Your coach recommends one concrete session you can begin right away."
                )
                onboardingPromiseRow(
                    systemImage: "flame.fill",
                    title: "Better estimates",
                    detail: "Age, height, and weight help personalize calories and plan load."
                )
            }
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle(
                "What should your coach help you do first?",
                subtitle: "Write it naturally. A race, weight goal, comeback, faster pace, or just feeling fitter all work."
            )

            IntakeTextEditor(
                text: Binding(
                    get: { onboardingStore.draft.goalText },
                    set: { onboardingStore.updateGoalText($0) }
                ),
                placeholder: "I want to run my first 10K this fall and lose some weight without getting hurt."
            )

            exampleSection(title: "Examples") {
                ExamplePromptButton("Run my first 5K without stopping") {
                    onboardingStore.updateGoalText("Run my first 5K without stopping.")
                }
                ExamplePromptButton("Get faster for a spring race") {
                    onboardingStore.updateGoalText("Get faster for a spring race.")
                }
                ExamplePromptButton("Get back safely after a long break") {
                    onboardingStore.updateGoalText("Get back safely after a long break.")
                }
            }
        }
    }

    private var bodyStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepTitle(
                "Add body basics.",
                subtitle: "These help estimate calories and keep the first plan realistic. You can change them later."
            )

            Picker("Units", selection: Binding(
                get: { onboardingStore.draft.unitSystem },
                set: { onboardingStore.selectUnitSystem($0) }
            )) {
                ForEach(MeasurementUnitSystem.allCases) { unitSystem in
                    Text(unitSystem.title).tag(unitSystem)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 12) {
                NumberField(
                    title: "Age",
                    detail: "Years",
                    text: Binding(
                        get: { onboardingStore.draft.ageText },
                        set: { onboardingStore.updateAgeText($0) }
                    )
                )
                NumberField(
                    title: "Height",
                    detail: onboardingStore.draft.unitSystem == .metric ? "Centimeters" : "Inches",
                    text: Binding(
                        get: { onboardingStore.draft.heightText },
                        set: { onboardingStore.updateHeightText($0) }
                    )
                )
                NumberField(
                    title: "Weight",
                    detail: onboardingStore.draft.unitSystem == .metric ? "Kilograms" : "Pounds",
                    text: Binding(
                        get: { onboardingStore.draft.weightText },
                        set: { onboardingStore.updateWeightText($0) }
                    )
                )
            }

            choiceSection(title: "Body profile for calorie estimates") {
                Picker("Body profile", selection: Binding(
                    get: { onboardingStore.draft.sex },
                    set: { onboardingStore.selectSex($0) }
                )) {
                    ForEach(OnboardingBodySex.allCases) { sex in
                        Text(sex.title).tag(sex)
                    }
                }
                .pickerStyle(.segmented)
            }

            Text(onboardingStore.bodyProfile.calorieEstimateLine)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var baselineStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepTitle(
                "Tell your coach where you are starting.",
                subtitle: "Use plain language. Include what you can comfortably do and anything your coach should be careful with."
            )

            IntakeTextEditor(
                text: Binding(
                    get: { onboardingStore.draft.baselineText },
                    set: { onboardingStore.updateBaselineText($0) }
                ),
                placeholder: "I can jog 15-20 minutes, but my knees get cranky. I walk a lot and bike on weekends."
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("What does a realistic week look like?")
                    .font(.headline)
                IntakeTextEditor(
                    text: Binding(
                        get: { onboardingStore.draft.scheduleText },
                        set: { onboardingStore.updateScheduleText($0) }
                    ),
                    placeholder: "Three days is realistic. Weekends are easiest, weekdays need shorter sessions.",
                    minHeight: 104
                )
            }

            exampleSection(title: "Examples") {
                ExamplePromptButton("New to running, but active") {
                    onboardingStore.updateBaselineText("I am new to running, but I walk a lot and can exercise for about 25 minutes.")
                    onboardingStore.updateScheduleText("Two or three days per week is realistic.")
                }
                ExamplePromptButton("Running weekly already") {
                    onboardingStore.updateBaselineText("I run 2-3 miles twice a week, around 10 min/mile, and want to build up.")
                    onboardingStore.updateScheduleText("Three days per week works best, with a longer session on Sunday.")
                }
                ExamplePromptButton("Coming back carefully") {
                    onboardingStore.updateBaselineText("I have not run in a year and want to be careful with my knees.")
                    onboardingStore.updateScheduleText("Two short weekday sessions and one weekend session could work.")
                }
            }
        }
    }

    private var reviewStep: some View {
        let summary = onboardingStore.intakeSummary

        return VStack(alignment: .leading, spacing: 20) {
            stepTitle(
                "Here is what your coach understood.",
                subtitle: "Adjust the effort if this read feels too gentle or too spicy."
            )

            VStack(alignment: .leading, spacing: 14) {
                summaryRow(systemImage: "flag.fill", title: "Focus", detail: summary.focus.title)
                summaryRow(systemImage: summary.sport.systemImage, title: "Sport", detail: summary.sport.displayName)
                summaryRow(systemImage: "waveform.path.ecg", title: "Baseline", detail: summary.baselineLine)
                summaryRow(systemImage: "calendar", title: "Week", detail: summary.weeklyRhythm.title)
                summaryRow(systemImage: "timer", title: "First session", detail: summary.firstSessionLength.title)
                if let cautionLine = summary.cautionLine {
                    summaryRow(systemImage: "cross.case.fill", title: "Caution", detail: cautionLine)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            choiceSection(title: "Plan feel") {
                LazyVGrid(columns: optionColumns, spacing: 10) {
                    ForEach(OnboardingEffortPreference.allCases) { effort in
                        CompactChoiceButton(
                            title: effort.title,
                            detail: effort.detail,
                            systemImage: effort == .balanced ? "checkmark.seal.fill" : "slider.horizontal.3",
                            isSelected: summary.effortPreference == effort,
                            accentColor: accentColor
                        ) {
                            onboardingStore.selectEffortPreference(effort)
                        }
                    }
                }
            }

            Button {
                while onboardingStore.step != .goal {
                    onboardingStore.goBack()
                }
            } label: {
                Label("Edit my answers", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(accentColor)
        }
    }

    private var setupStep: some View {
        let profile = onboardingStore.previewProfile
        let session = profile.suggestedSession

        return VStack(alignment: .leading, spacing: 20) {
            stepTitle(
                "Your recommendation is ready.",
                subtitle: "A reviewed plan path, tuned from your words and body basics."
            )

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: session.sport.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .frame(width: 42, height: 42)
                        .background(accentColor.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 6) {
                        Text(profile.planTitle)
                            .font(.title3.bold())
                        Text(profile.recommendationRationale)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()

                setupRow(
                    systemImage: "timer",
                    title: "Today",
                    detail: "\(session.durationLabel) - \(session.activityLabel)"
                )
                setupRow(
                    systemImage: "calendar.badge.checkmark",
                    title: "This week",
                    detail: profile.weeklySetupLine
                )
                setupRow(
                    systemImage: "flame.fill",
                    title: "Calories",
                    detail: profile.bodyProfile.calorieEstimateLine
                )
                setupRow(
                    systemImage: coachCatalog.selectedPersona.face.symbolName,
                    title: "Coach",
                    detail: coachCatalog.selectedPersona.template.displayName
                )
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            Text(session.coachLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                if onboardingStore.step == .setup {
                    onComplete(true)
                } else {
                    onboardingStore.advance()
                }
            } label: {
                Label(primaryButtonTitle, systemImage: primaryButtonImage)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .disabled(!onboardingStore.canAdvance)

            if onboardingStore.step == .setup {
                Button("Save plan and go to Me") {
                    onComplete(false)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            } else if onboardingStore.step == .welcome {
                Button("Skip setup") {
                    onComplete(false)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var primaryButtonTitle: String {
        switch onboardingStore.step {
        case .welcome: return "Set up my coach"
        case .goal, .body, .baseline: return "Continue"
        case .review: return "Build recommendation"
        case .setup: return "Start first session"
        }
    }

    private var primaryButtonImage: String {
        switch onboardingStore.step {
        case .setup: return "play.fill"
        default: return "arrow.right"
        }
    }

    private var optionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 112), spacing: 10)]
    }

    private func stepTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choiceSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func exampleSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                content()
            }
        }
    }

    private func onboardingPromiseRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accentColor)
                .frame(width: 28, height: 28)
                .background(accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setupRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func summaryRow(systemImage: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct IntakeTextEditor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 142

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: minHeight)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct NumberField: View {
    let title: String
    let detail: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            TextField("Required", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.headline)
                .frame(maxWidth: 120)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ExamplePromptButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "quote.opening")
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CompactChoiceButton: View {
    let title: String
    let detail: String
    let systemImage: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? accentColor : .secondary)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? accentColor : Color.secondary.opacity(0.45))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? accentColor : Color.clear, lineWidth: 1.4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private extension CoachFace {
    var onboardingAccentColor: Color {
        switch colorName {
        case "orange": .orange
        case "pink": .pink
        case "green": .green
        case "blue": .blue
        case "cyan": .cyan
        case "yellow": .yellow
        case "red": .red
        case "gray": .gray
        default: .orange
        }
    }
}
