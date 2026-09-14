import SwiftUI

struct SimplifiedOnboardingFlow: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var healthAuthorizationStore: HealthAuthorizationStore
    @EnvironmentObject private var healthImportStore: HealthImportStore
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    let onComplete: () -> Void

    @State private var step: Step = .welcome
    @State private var draft = PlanBuilderDraft()
    @State private var displayName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var identityCompleted = false
    @State private var isSavingIdentity = false
    @State private var identityError: String?
    @State private var isResolvingSkip = false
    @State private var isConnectingHealth = false
    @State private var didConnectHealth = false
    @State private var isSavingTrainingProfile = false
    @State private var savedTrainingProfile: TrainingProfileDTO?
    @State private var intakeContext: PlanIntakeContextDTO?
    @State private var isLoadingIntakeContext = false
    @State private var goalMessage = ""
    @State private var interpretationReply: String?
    @State private var isInterpretingGoal = false
    @State private var isEventDatePickerPresented = false
    @FocusState private var isGoalInputFocused: Bool
    @State private var healthMessage: String?
    @State private var toastMessage: String?
    @State private var toastRetry: ToastRetry?
    @State private var creationStartedAt: Date?
    @State private var hasTrackedOpen = false
    @State private var hasTrackedProfileView = false

    private var isFirstUse: Bool {
        onboardingStore.presentationSource == .onboarding
            && authStore.user?.resolvedOnboardingStatus == .pending
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if step != .creating && step != .result {
                        ProgressView(value: Double(progressIndex), total: Double(progressCount))
                            .tint(OutboundPalette.companion)
                            .padding(.horizontal, OutboundSpacing.screen)
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                                content
                                Color.clear.frame(height: 1).id(Self.conversationBottomID)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(OutboundSpacing.screen)
                        }
                        .onChange(of: objectiveConversationProgress) { _, _ in
                            guard step == .objective else { return }
                            withAnimation(.snappy) {
                                proxy.scrollTo(Self.conversationBottomID, anchor: .bottom)
                            }
                        }
                    }
                    if step != .creating { footer.padding(OutboundSpacing.screen) }
                }
                .background(OutboundPalette.background)

                if let toastMessage {
                    HStack(spacing: 12) {
                        Text(toastMessage).font(.subheadline.weight(.semibold))
                        Spacer()
                        Button(String(localized: "common.retry", defaultValue: "Retry")) { retryToastAction() }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
                    .padding()
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle(String(localized: "plan_builder.title", defaultValue: "Plan setup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(isFirstUse)
        .sheet(isPresented: $isEventDatePickerPresented) { eventDatePickerSheet }
        .onAppear { configure() }
        .onChange(of: draft) { _, value in onboardingStore.savePlanBuilderDraft(value) }
        .onChange(of: step) { _, value in
            if value == .profile {
                restoreTrainingProfileStep()
                trackProfileViewIfNeeded()
            }
        }
        .animation(.snappy, value: toastMessage)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if step.canGoBack {
                Button(String(localized: "onboarding.action.back", defaultValue: "Back"), systemImage: "chevron.left") { goBack() }
            } else if !isFirstUse, step != .creating {
                Button(String(localized: "plan_builder.finish_later", defaultValue: "Finish later")) { finishLater() }
            }
        }
        if step.canGoBack, step != .creating {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "plan_builder.finish_later", defaultValue: "Finish later")) { finishLater() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if shouldShowIdentityPrompt {
            identityContent
        } else {
            switch step {
            case .welcome: welcomeContent
            case .objective: objectiveContent
            case .activities: activitiesContent
            case .baseline: baselineContent
            case .week: weekContent
            case .profile: privateDetailsContent
            case .review: reviewContent
            case .creating: creatingContent
            case .result: resultContent
            }
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(
                String(localized: "plan_builder.welcome.title", defaultValue: "A plan that fits real life"),
                String(localized: "plan_builder.welcome.subtitle", defaultValue: "Plainstride turns your goal, activities, and available time into a plan that adapts as you train.")
            )
            Label(String(localized: "plan_builder.welcome.today", defaultValue: "Know what to do today"), systemImage: "sparkles")
            Label(String(localized: "plan_builder.welcome.week", defaultValue: "Start with a concrete week"), systemImage: "calendar")
            Label(String(localized: "plan_builder.welcome.adapts", defaultValue: "Adjust when life changes"), systemImage: "arrow.triangle.2.circlepath")
        }
    }

    private var objectiveContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            coachMessage(
                String(localized: "plan_builder.objective.title", defaultValue: "What do you want this plan to help you achieve?"),
                detail: String(localized: "plan_builder.conversation.goal_hint", defaultValue: "Choose a quick reply or describe the goal in your own words.")
            )

            if draft.objectiveConfirmed == true {
                editableRunnerMessage(goalResponseText, field: "goal") {
                    resetGoalConversation()
                }
                coachMessage(goalAcknowledgement)
                Button(String(localized: "plan_builder.conversation.change_goal", defaultValue: "Change goal")) {
                    editGoalConversation()
                }
                .font(.subheadline.weight(.semibold))
                .padding(.leading, 48)

                if draft.objective == .eventPreparation {
                    eventConversationFields
                } else {
                    genericGoalConversationFields
                }
            } else {
                LazyVGrid(columns: Self.choiceColumns, spacing: 10) {
                    ForEach(PlanObjective.availableInBuilder) { objective in
                        optionTile(objective.title, systemImage: objective.systemImage, selected: false) {
                            selectObjectiveQuickReply(objective)
                        }
                    }
                }

                HStack(spacing: 10) {
                    TextField(
                        String(localized: "plan_builder.coach_prompt.placeholder", defaultValue: "For example: Prepare for a half marathon"),
                        text: $goalMessage,
                        axis: .vertical
                    )
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($isGoalInputFocused)
                    Button {
                        interpretGoal()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.headline.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(String(localized: "plan_builder.coach_prompt.action", defaultValue: "Use this goal"))
                    .disabled(goalMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isInterpretingGoal)
                }
                .padding(.leading, 48)

                if isInterpretingGoal {
                    coachTypingIndicator
                } else if let interpretationReply {
                    coachMessage(interpretationReply, isError: true)
                }
            }
        }
    }

    private var activitiesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isLoadingIntakeContext, intakeContext == nil {
                coachMessage(String(localized: "plan_builder.smart_setup.loading", defaultValue: "Checking your recent training…"))
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if let setup = intakeContext?.suggestedSetup,
               setup.confidence == "high",
               draft.observedBaselineConfirmed != false {
                coachMessage(
                    String(localized: "plan_builder.smart_setup.title", defaultValue: "I already know your training pattern"),
                    detail: String(localized: "plan_builder.smart_setup.subtitle", defaultValue: "I used your recent synced activities to fill this in. Confirm it if your current routine still fits.")
                )
                OutboundCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(
                            String(
                                format: String(localized: "plan_builder.smart_setup.based_on", defaultValue: "Based on %1$d sessions across %2$d recent weeks"),
                                locale: .autoupdatingCurrent,
                                setup.evidence.sessionCount,
                                setup.evidence.activeWeekCount
                            ),
                            systemImage: "checkmark.seal.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(OutboundPalette.companion)
                        smartSetupRow(
                            String(localized: "plan_builder.smart_setup.activities", defaultValue: "Activities"),
                            value: setupActivitiesTitle,
                            systemImage: "figure.run"
                        )
                        smartSetupRow(
                            String(localized: "plan_builder.smart_setup.rhythm", defaultValue: "Weekly rhythm"),
                            value: String(
                                format: String(localized: "plan_builder.smart_setup.rhythm_value", defaultValue: "%1$d sessions · up to %2$d min"),
                                locale: .autoupdatingCurrent,
                                boundedSessionsPerWeek(setup.sessionsPerWeek),
                                setup.maxSessionMinutes
                            ),
                            systemImage: "calendar"
                        )
                        smartSetupRow(
                            String(localized: "plan_builder.smart_setup.days", defaultValue: "Usual days"),
                            value: setupDaysTitle(setup),
                            systemImage: "clock"
                        )
                        TextField(
                            String(localized: "plan_builder.smart_setup.constraints", defaultValue: "Anything changed? Injury, illness, travel, or schedule constraints (optional)"),
                            text: $draft.constraints,
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                        VStack(spacing: 8) {
                            Button {
                                acceptSuggestedSetup()
                            } label: {
                                Text(String(localized: "plan_builder.smart_setup.use", defaultValue: "Use this setup"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            Button {
                                draft.observedBaselineConfirmed = false
                                track(.planIntakeBaselineConfirmed, [.result: .string("corrected"), .sourceType: .string("recent_activity_setup")])
                            } label: {
                                Text(String(localized: "plan_builder.smart_setup.adjust", defaultValue: "Adjust it"))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } else {
                coachMessage(
                    String(localized: "plan_builder.activities.title", defaultValue: "Which activities should your plan use?"),
                    detail: String(localized: "plan_builder.activities.subtitle", defaultValue: "Choose one or more. Plainstride will balance them across your week.")
                )
                LazyVGrid(columns: Self.choiceColumns, spacing: 10) {
                    ForEach(PlanActivity.availableInBuilder) { activity in
                        optionTile(activity.title, systemImage: activity.systemImage, selected: draft.activities.contains(activity)) {
                            toggleActivity(activity)
                        }
                    }
                }
            }
        }
    }

    private var baselineContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            coachMessage(
                String(localized: "plan_builder.baseline.title", defaultValue: "Where are you starting from?"),
                detail: String(localized: "plan_builder.baseline.subtitle", defaultValue: "A rough starting point is enough. Your first three relevant sessions will refine it.")
            )
            if intakeContext?.suggestedSetup == nil,
               let baseline = intakeContext?.observedBaseline,
               baseline.confidence == "high" {
                OutboundCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(String(localized: "plan_builder.baseline.observed", defaultValue: "Based on your last 28 days"), systemImage: "checkmark.seal")
                            .font(.headline)
                        Text(observedBaselineSummary(baseline)).foregroundStyle(.secondary)
                        HStack {
                            Button(String(localized: "plan_builder.baseline.use", defaultValue: "Use this baseline")) {
                                draft.observedBaselineConfirmed = true
                                track(.planIntakeBaselineConfirmed, [.result: .string("accepted"), .sourceType: .string("recent_activities")])
                            }
                            .buttonStyle(.borderedProminent)
                            Button(String(localized: "plan_builder.baseline.update", defaultValue: "Update it")) {
                                draft.observedBaselineConfirmed = false
                                track(.planIntakeBaselineConfirmed, [.result: .string("corrected"), .sourceType: .string("recent_activities")])
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            if intakeContext?.observedBaseline?.confidence != "high"
                || intakeContext?.suggestedSetup != nil
                || draft.observedBaselineConfirmed == false {
                ForEach(PlanBaselineContext.allCases) { context in
                    selectionRow(context.title, selected: draft.baselineContext == context) { draft.baselineContext = context }
                }
                Stepper(String(format: String(localized: "plan_builder.baseline.frequency", defaultValue: "Recent sessions: %d per week"), locale: .autoupdatingCurrent, draft.recentSessionsPerWeek), value: $draft.recentSessionsPerWeek, in: 0...6)
                    .planBuilderCard()
                Stepper(String(format: String(localized: "plan_builder.baseline.duration", defaultValue: "Comfortable session: %d min"), locale: .autoupdatingCurrent, draft.comfortableMinutes), value: $draft.comfortableMinutes, in: 10...120, step: 5)
                    .planBuilderCard()
            }
        }
    }

    private var weekContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            coachMessage(
                String(localized: "plan_builder.week.title", defaultValue: "What can most weeks support?"),
                detail: String(localized: "plan_builder.week.subtitle", defaultValue: "Choose what is realistic. Preferred days are optional.")
            )
            Stepper(String(format: String(localized: "plan_builder.week.sessions", defaultValue: "%d sessions per week"), locale: .autoupdatingCurrent, draft.sessionsPerWeek), value: $draft.sessionsPerWeek, in: 1...6)
                .planBuilderCard()
                .onChange(of: draft.sessionsPerWeek) { _, count in
                    if draft.preferredDays.count > count {
                        draft.preferredDays = Array(draft.preferredDays.prefix(count))
                    }
                }
            Stepper(String(format: String(localized: "plan_builder.week.duration", defaultValue: "About %d min per session"), locale: .autoupdatingCurrent, draft.availableMinutes), value: $draft.availableMinutes, in: 10...120, step: 5)
                .planBuilderCard()
            Text(String(localized: "plan_builder.week.preferred_days", defaultValue: "Preferred days (optional)"))
                .font(.headline)
            LazyVGrid(columns: Self.dayColumns, alignment: .leading, spacing: 8) {
                ForEach(Self.weekdays, id: \.code) { day in
                    toggleChip(day.label, selected: draft.preferredDays.contains(day.code)) { togglePreferredDay(day.code) }
                }
            }
            TextField(String(localized: "plan_builder.week.constraints", defaultValue: "Injury, illness, travel, or schedule constraints (optional)"), text: $draft.constraints, axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var privateDetailsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            coachMessage(
                String(localized: "onboarding.profile.required_title", defaultValue: "Private planning details"),
                detail: String(localized: "onboarding.profile.required_subtitle", defaultValue: "Birth date, sex assigned at birth, and weight are required for safe plan personalization and calorie calculations. You can enter them manually or import available values from Apple Health. Height is optional.")
            )
            Button { connectHealth() } label: {
                Label(
                    healthConnectionTitle,
                    systemImage: didConnectHealth ? "checkmark.circle.fill" : "heart.fill"
                ).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isConnectingHealth || didConnectHealth || isSavingTrainingProfile)
            if let healthMessage { Text(healthMessage).font(.subheadline).foregroundStyle(.secondary) }

            Text(String(localized: "onboarding.profile.manual", defaultValue: "Or add them yourself"))
                .textCase(.uppercase)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            OutboundCard {
                VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                    Toggle(
                        String(localized: "Add birthday"),
                        isOn: Binding(
                            get: { draft.birthDate != nil },
                            set: { draft.birthDate = $0 ? (draft.birthDate ?? Self.defaultBirthDate) : nil }
                        )
                    )
                    if let birthDate = draft.birthDate {
                        DatePicker(
                            String(localized: "Birthday"),
                            selection: Binding(get: { birthDate }, set: { draft.birthDate = $0 }),
                            in: oldestBirthDate...youngestBirthDate,
                            displayedComponents: .date
                        )
                    }
                    Text(String(
                        localized: "profile.training_details.birthday_footer",
                        defaultValue: "Birthday is stored instead of age so your details stay accurate over time."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: OutboundSpacing.compact) {
                trainingMeasurementField(heightLabel, text: $draft.heightText)
                trainingMeasurementField(weightLabel, text: $draft.weightText)
            }

            VStack(alignment: .leading, spacing: OutboundSpacing.compact) {
                Text(String(localized: "Sex assigned at birth"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker(String(localized: "Sex assigned at birth"), selection: $draft.sexAtBirth) {
                    Text(String(localized: "Not provided")).tag(nil as TrainingProfileSex?)
                    ForEach(TrainingProfileSex.allCases) { value in
                        Text(value.title).tag(value as TrainingProfileSex?)
                    }
                }
                .pickerStyle(.segmented)
            }

            if !trainingMeasurementsAreValid {
                Text(trainingMeasurementError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Label(String(localized: "onboarding.profile.private", defaultValue: "These details stay private and are never shared."), systemImage: "lock.shield")
                .font(.subheadline).foregroundStyle(.secondary)
            if !requiredBodyProfileComplete {
                Text(String(localized: "onboarding.profile.required_error", defaultValue: "Add a valid birth date, sex assigned at birth, and weight to continue."))
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            coachMessage(
                String(localized: "plan_builder.review.title", defaultValue: "Ready to create your plan"),
                detail: String(localized: "plan_builder.review.subtitle", defaultValue: "Plainstride will schedule the next 7–14 days and adapt what comes after.")
            )
            summaryRow(String(localized: "plan_builder.review.objective", defaultValue: "Goal"), draft.objective.title)
            if draft.objective == .eventPreparation {
                summaryRow(
                    String(localized: "plan_builder.review.event", defaultValue: "Event"),
                    [eventDistanceTitle, draft.eventDate?.formatted(date: .abbreviated, time: .omitted), eventIntentTitle]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                )
            } else {
                summaryRow(String(localized: "plan_builder.review.horizon", defaultValue: "Review point"), reviewHorizonTitle)
                if let successSignal = draft.successSignal?.trimmingCharacters(in: .whitespacesAndNewlines), !successSignal.isEmpty {
                    summaryRow(String(localized: "plan_builder.review.success", defaultValue: "Meaningful progress"), successSignal)
                }
            }
            summaryRow(String(localized: "plan_builder.review.activities", defaultValue: "Activity mix"), draft.activities.map(\.title).joined(separator: " · "))
            summaryRow(String(localized: "plan_builder.review.week", defaultValue: "Realistic week"), String(format: String(localized: "plan_builder.review.week_value", defaultValue: "%1$d sessions · about %2$d min each"), locale: .autoupdatingCurrent, draft.sessionsPerWeek, draft.availableMinutes))
        }
    }

    private var creatingContent: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 80)
            ProgressView().controlSize(.large)
            Text(String(localized: "plan_builder.creating", defaultValue: "Building a plan around your week…"))
                .font(.title3.weight(.semibold)).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading(
                String(localized: "plan_builder.result.plan", defaultValue: "Your plan"),
                trainingPlanStore.activePlan?.subtitle ?? String(localized: "plan_builder.result.direction", defaultValue: "A flexible direction built around your objective and available week.")
            )
            summaryRow(String(localized: "plan_builder.review.objective", defaultValue: "Goal"), draft.objective.title)
            summaryRow(String(localized: "plan_builder.review.activities", defaultValue: "Activity mix"), draft.activities.map(\.title).joined(separator: " · "))
            Text(String(localized: "plan_builder.result.week", defaultValue: "Your starting week")).font(.title3.weight(.bold))
            if let week = trainingPlanStore.currentWeek {
                let totalMinutes = week.scheduledWorkouts.reduce(0) { $0 + $1.durationMinutesRounded }
                summaryRow(
                    String(localized: "plan_builder.result.total_time", defaultValue: "Starting-week time"),
                    String(format: String(localized: "plan_builder.result.total_time_value", defaultValue: "%d min"), locale: .autoupdatingCurrent, totalMinutes)
                )
                ForEach(week.scheduledWorkouts) { workout in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(workout.dayLabel) · \(workout.title)").font(.headline)
                            Text("\(workout.durationLabel) · \(workout.effortLabel)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if workout.isOptional { Text(String(localized: "common.optional", defaultValue: "Optional")).font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 4)
                }
                Text(week.guideLine).font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Button(String(localized: "plan_builder.result.easier", defaultValue: "Make it easier")) {
                    draft.sessionsPerWeek = max(1, draft.sessionsPerWeek - 1)
                    draft.availableMinutes = max(10, draft.availableMinutes - 5)
                    step = .week
                }
                Button(String(localized: "plan_builder.result.change_days", defaultValue: "Change days")) { step = .week }
                Button(String(localized: "plan_builder.result.change_mix", defaultValue: "Change activity mix")) { step = .activities }
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !shouldHideActivitiesFooter && (step != .objective || draft.objectiveConfirmed == true) {
            VStack(spacing: 10) {
                OutboundPrimaryButton(title: primaryButtonTitle, systemImage: step == .result ? "arrow.right" : "sparkles") { primaryAction() }
                    .disabled(primaryDisabled)
                if isFirstUse, step == .welcome {
                    Button(String(localized: "plan_builder.explore", defaultValue: "Explore first")) { exploreFirst() }
                        .font(.headline).disabled(isResolvingSkip)
                }
            }
        }
    }

    private var primaryButtonTitle: String {
        if shouldShowIdentityPrompt { return isSavingIdentity ? String(localized: "onboarding.identity.saving", defaultValue: "Saving…") : String(localized: "onboarding.identity.continue", defaultValue: "Continue") }
        switch step {
        case .profile where isSavingTrainingProfile:
            return String(localized: "onboarding.identity.saving", defaultValue: "Saving…")
        case .welcome, .review: return String(localized: "plan_builder.create", defaultValue: "Create my plan")
        case .result: return String(localized: "plan_builder.go_today", defaultValue: "Go to Today")
        default: return String(localized: "onboarding.action.continue", defaultValue: "Continue")
        }
    }

    private var primaryDisabled: Bool {
        isSavingIdentity
            || isResolvingSkip
            || isConnectingHealth
            || isSavingTrainingProfile
            || (step == .profile && !trainingMeasurementsAreValid)
            || (step == .profile && !requiredBodyProfileComplete)
            || (step == .baseline && intakeContext?.suggestedSetup == nil && intakeContext?.observedBaseline?.confidence == "high" && draft.observedBaselineConfirmed == nil)
            || ([.objective, .review].contains(step) && draft.objectiveConfirmed != true)
            || ([.objective, .review].contains(step) && draft.objective == .eventPreparation && !eventDetailsComplete)
            || draft.activities.isEmpty
            || ([.objective, .review].contains(step) && draft.objective != .eventPreparation && draft.reviewHorizonConfirmed != true)
    }

    private func primaryAction() {
        if shouldShowIdentityPrompt { Task { await saveIdentity() }; return }
        switch step {
        case .welcome: step = .objective
        case .profile: Task { await saveTrainingProfileAndContinue() }
        case .review: createPlan()
        case .result: onboardingStore.finishLater(); onComplete()
        default: advance()
        }
    }

    private func configure() {
        draft = onboardingStore.loadPlanBuilderDraft()
        normalizeBuilderChoices()
        goalMessage = draft.goalInputText ?? ""
        step = isFirstUse ? .welcome : .objective
        displayName = validDisplayName ? (authStore.user?.displayName ?? "") : ""
        username = authStore.user?.username == "runner" ? "" : (authStore.user?.username ?? "")
        email = validEmail ? (authStore.user?.email ?? "") : ""
        if authStore.user != nil {
            isLoadingIntakeContext = true
            Task {
                async let profileRequest = try? APIClient.shared.fetchTrainingProfile()
                async let contextRequest = try? APIClient.shared.fetchPlanIntakeContext()
                let (profile, context) = await (profileRequest, contextRequest)
                if let profile { savedTrainingProfile = profile; restoreDraftFromSavedTrainingProfile() }
                if let context { applyIntakeContext(context) }
                isLoadingIntakeContext = false
            }
        }
        guard !hasTrackedOpen else { return }
        hasTrackedOpen = true
        track(.planBuilderOpened, [.entrySource: .string(onboardingStore.presentationSource.rawValue)])
    }

    private func exploreFirst() {
        isResolvingSkip = true
        Task {
            let success = await authStore.resolveOnboardingAsSkipped()
            isResolvingSkip = false
            guard success else {
                showToast(
                    String(localized: "plan_builder.skip_error", defaultValue: "Couldn’t save that choice. Try again."),
                    retry: .skip
                )
                return
            }
            onboardingStore.markResolved(.skipped)
            track(.onboardingResolved, [.result: .string("skipped")])
            onboardingStore.finishLater()
            onComplete()
        }
    }

    private func createPlan() {
        toastMessage = nil
        creationStartedAt = Date()
        step = .creating
        Task {
            do {
                try await trainingPlanStore.createPersonalizedPlan(request)
                if authStore.user?.resolvedOnboardingStatus == .pending {
                    authStore.markOnboardingResolved(.completed)
                    onboardingStore.markResolved(.completed)
                    track(.onboardingResolved, [.result: .string("completed")])
                }
                onboardingStore.clearPlanBuilderDraft()
                trackCreation(result: "success")
                step = .result
            } catch {
                trackCreation(result: "failure", errorCategory: planningErrorCategory(error))
                step = .review
                showToast(
                    String(localized: "plan_builder.create_error", defaultValue: "We couldn’t create your plan. Your answers are saved."),
                    retry: .create
                )
            }
        }
    }

    private func showToast(_ message: String, retry: ToastRetry) {
        toastMessage = message
        toastRetry = retry
        Task {
            try? await Task.sleep(for: .seconds(6))
            if toastMessage == message {
                toastMessage = nil
                toastRetry = nil
            }
        }
    }

    private func retryToastAction() {
        switch toastRetry {
        case .skip: exploreFirst()
        case .create: createPlan()
        case .profile: Task { await saveTrainingProfileAndContinue() }
        case nil: break
        }
    }

    private var request: PlanningGoalRequest {
        PlanningGoalRequest(
            type: draft.objective.rawValue,
            activities: draft.activities.map(\.rawValue),
            baselineContext: draft.baselineContext.rawValue,
            targetDate: draft.objective == .eventPreparation ? draft.eventDate.map(Self.apiDateFormatter.string) : nil,
            targetDistanceMeters: draft.objective == .eventPreparation ? draft.eventDistanceMeters : nil,
            eventIntent: draft.objective == .eventPreparation ? draft.eventIntent : nil,
            targetTimeSeconds: draft.objective == .eventPreparation ? draft.targetTimeSeconds : nil,
            reviewHorizonWeeks: draft.objective == .eventPreparation ? nil : draft.reviewHorizonWeeks,
            successSignal: draft.successSignal,
            goalDescription: draft.goalDescription,
            intakeContextVersion: draft.intakeContextVersion,
            priority: draft.objective == .eventPreparation ? "finish" : "generalHealth",
            preferredDays: draft.preferredDays,
            daysPerWeekTarget: boundedSessionsPerWeek(draft.sessionsPerWeek),
            maxSessionMinutes: draft.availableMinutes,
            riskTolerance: draft.baselineContext == .returningAfterBreak ? "conservative" : "balanced",
            constraints: ["notes": draft.constraints].filter { !$0.value.isEmpty }
        )
    }

    private var identityContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(String(localized: "onboarding.identity.heading", defaultValue: "Finish your profile"), String(localized: "onboarding.identity.subtitle", defaultValue: "Your identity stays separate from plan setup."))
            TextField(String(localized: "onboarding.identity.display_name", defaultValue: "Display name"), text: $displayName).textFieldStyle(.roundedBorder)
            TextField(String(localized: "onboarding.identity.username", defaultValue: "Username"), text: $username).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            if !validEmail { TextField(String(localized: "onboarding.identity.email", defaultValue: "Email"), text: $email).textInputAutocapitalization(.never).keyboardType(.emailAddress).textFieldStyle(.roundedBorder) }
            if let identityError { Text(identityError).font(.footnote).foregroundStyle(.red) }
        }
    }

    private func saveIdentity() async {
        guard identityFormIsValid else { return }
        isSavingIdentity = true; identityError = nil
        defer { isSavingIdentity = false }
        do {
            let profile = try await APIClient.shared.updateMyProfile(.init(username: cleanedUsername, displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines), bio: nil, contactEmail: validEmail ? nil : email.lowercased(), contactPhone: nil))
            authStore.applyProfileIdentity(username: profile.username, displayName: profile.displayName)
            identityCompleted = true
        } catch { identityError = String(localized: "onboarding.identity.error", defaultValue: "That username may already be taken. Try another one.") }
    }

    /// Prefills the draft from the training profile already saved for this account so a returning
    /// user does not see blank height, weight, and sex fields again.
    private func restoreDraftFromSavedTrainingProfile() {
        guard let profile = savedTrainingProfile else { return }
        let usesMetric = measurementPreferences.unitSystem == .metric
        if let heightCentimeters = profile.heightCentimeters {
            draft.heightText = formattedMeasurement(usesMetric ? heightCentimeters : heightCentimeters / 2.54)
        }
        if let weightKilograms = profile.weightKilograms {
            draft.weightText = formattedMeasurement(usesMetric ? weightKilograms : weightKilograms / 0.45359237)
        }
        if draft.sexAtBirth == nil { draft.sexAtBirth = profile.sexAtBirth }
        if let birthDate = profile.birthDate.flatMap(Self.birthDateFormatter.date(from:)) {
            draft.birthDate = birthDate
        }
    }

    /// Imports the HealthKit profile details a previously-granted authorization already allows.
    private func importHealthProfileData() {
        isConnectingHealth = true
        Task {
            do {
                let since = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: Date()) ?? .distantPast
                let data = try await healthImportStore.personalizationData(since: since)
                applyHealthData(data)
                healthMessage = String(
                    format: String(localized: "plan_builder.health.connected", defaultValue: "Connected. Found %d recent activities."),
                    locale: .autoupdatingCurrent,
                    data.recentWorkouts.count
                )
            } catch {
                didConnectHealth = false
                healthMessage = String(localized: "onboarding.health.error", defaultValue: "Apple Health could not be connected. You can try again or continue without it.")
            }
            isConnectingHealth = false
        }
    }

    private func connectHealth() {
        isConnectingHealth = true
        Task {
            await trackHealth(.healthConnectionRequested)
            await healthAuthorizationStore.requestAuthorization()
            if healthAuthorizationStore.lastErrorMessage == nil {
                let since = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: Date()) ?? .distantPast
                do {
                    let data = try await healthImportStore.personalizationData(since: since)
                    applyHealthData(data)
                    didConnectHealth = true
                    healthMessage = String(format: String(localized: "plan_builder.health.connected", defaultValue: "Connected. Found %d recent activities."), locale: .autoupdatingCurrent, data.recentWorkouts.count)
                    await trackHealth(.healthConnectionCompleted, result: "connected")
                } catch {
                    healthMessage = String(localized: "onboarding.health.error", defaultValue: "Apple Health could not be connected. You can try again or continue without it.")
                    await trackHealth(.healthConnectionCompleted, result: "failed")
                }
            } else {
                healthMessage = String(localized: "onboarding.health.error", defaultValue: "Apple Health could not be connected. You can try again or continue without it.")
                await trackHealth(.healthConnectionCompleted, result: "failed")
            }
            isConnectingHealth = false
        }
    }

    private func saveTrainingProfileAndContinue() async {
        guard trainingMeasurementsAreValid, requiredBodyProfileComplete, !isSavingTrainingProfile else { return }

        isSavingTrainingProfile = true
        do {
            let profile = try await APIClient.shared.updateTrainingProfile(trainingProfileRequest)
            onboardingStore.applyTrainingProfile(profile)
            savedTrainingProfile = profile
            if let context = try? await APIClient.shared.fetchPlanIntakeContext(objective: draft.objective.rawValue) {
                applyIntakeContext(context)
            }
            isSavingTrainingProfile = false
            await trackTrainingProfileCompletion(result: "saved", source: didConnectHealth ? "health" : "manual")
            step = .review
        } catch {
            isSavingTrainingProfile = false
            showToast(String(localized: "Could not save profile. Try again."), retry: .profile)
        }
    }

    private func trackProfileViewIfNeeded() {
        guard !hasTrackedProfileView else { return }
        hasTrackedProfileView = true
        track(.onboardingTrainingProfileViewed, [:])
    }

    private func trackTrainingProfileCompletion(result: String, source: String) async {
        await analyticsManager?.track(.init(
            .onboardingTrainingProfileCompleted,
            properties: [.result: .string(result), .sourceType: .string(source)]
        ))
    }

    private func trackHealth(_ name: ProductEventName, result: String? = nil) async {
        let properties: [ProductPropertyKey: AnalyticsValue] = result.map { [.result: .string($0)] } ?? [:]
        await analyticsManager?.track(.init(name, properties: properties))
    }

    private func applyHealthData(_ data: HealthPersonalizationData) {
        if let dateOfBirth = data.dateOfBirth { draft.birthDate = dateOfBirth }
        switch data.biologicalSex {
        case .female: draft.sexAtBirth = .female
        case .male: draft.sexAtBirth = .male
        case .notSpecified: break
        }
        if let heightCentimeters = data.heightCentimeters {
            draft.heightText = formattedMeasurement(usesMetric ? heightCentimeters : heightCentimeters / 2.54)
        }
        if let weightKilograms = data.weightKilograms {
            draft.weightText = formattedMeasurement(usesMetric ? weightKilograms : weightKilograms / 0.45359237)
        }
    }

    private func finishLater() {
        onboardingStore.savePlanBuilderDraft(draft)
        track(.planBuilderExited, [.stepName: .string(step.analyticsValue)])
        guard isFirstUse else {
            onboardingStore.finishLater()
            return
        }
        isResolvingSkip = true
        Task {
            let success = await authStore.resolveOnboardingAsSkipped()
            isResolvingSkip = false
            guard success else {
                showToast(
                    String(localized: "plan_builder.skip_error", defaultValue: "Couldn’t save that choice. Try again."),
                    retry: .skip
                )
                return
            }
            onboardingStore.markResolved(.skipped)
            track(.onboardingResolved, [.result: .string("skipped")])
            onboardingStore.finishLater()
        }
    }

    private func trackCreation(result: String, errorCategory: String? = nil) {
        let seconds = Date().timeIntervalSince(creationStartedAt ?? Date())
        let bucket = seconds < 2 ? "under_2s" : seconds < 5 ? "2s_5s" : seconds < 10 ? "5s_10s" : "10s_plus"
        var properties: [ProductPropertyKey: AnalyticsValue] = [
            .result: .string(result),
            .latencyBucket: .string(bucket),
            .goalType: .string(draft.objective.rawValue),
            .countBucket: .string("activities_\(draft.activities.count)"),
        ]
        if let errorCategory { properties[.errorCategory] = .string(errorCategory) }
        track(.planCreationCompleted, properties)
    }

    private func track(_ name: ProductEventName, _ properties: [ProductPropertyKey: AnalyticsValue]) {
        Task { await analyticsManager?.track(.init(name, properties: properties)) }
    }

    private func toggleActivity(_ activity: PlanActivity) {
        if let index = draft.activities.firstIndex(of: activity) {
            guard draft.activities.count > 1 else { return }
            draft.activities.remove(at: index)
        } else {
            draft.activities.append(activity)
        }
    }
    private func togglePreferredDay(_ day: String) {
        if let index = draft.preferredDays.firstIndex(of: day) { draft.preferredDays.remove(at: index) }
        else if draft.preferredDays.count < draft.sessionsPerWeek { draft.preferredDays.append(day) }
    }
    private var usesMetric: Bool { measurementPreferences.unitSystem == .metric }
    private var heightLabel: String { usesMetric ? String(localized: "Height (cm)") : String(localized: "Height (in)") }
    private var weightLabel: String { usesMetric ? String(localized: "Weight (kg)") : String(localized: "Weight (lb)") }
    private var healthConnectionTitle: String {
        if didConnectHealth { return String(localized: "onboarding.health.connected", defaultValue: "Apple Health connected") }
        if isConnectingHealth { return String(localized: "onboarding.health.connecting", defaultValue: "Connecting…") }
        return String(localized: "onboarding.health.connect", defaultValue: "Connect Apple Health")
    }
    private var oldestBirthDate: Date { Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? .distantPast }
    private var youngestBirthDate: Date { Calendar.current.date(byAdding: .year, value: -13, to: Date()) ?? Date() }
    private var trainingMeasurementsAreValid: Bool {
        let heightIsValid = parsedMeasurement(draft.heightText)
            .map { usesMetric ? (90...250).contains($0) : (35...98.5).contains($0) }
            ?? draft.heightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let weightIsValid = parsedMeasurement(draft.weightText)
            .map { usesMetric ? (25...350).contains($0) : (55...772).contains($0) }
            ?? draft.weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return heightIsValid && weightIsValid
    }
    private var trainingMeasurementError: String {
        if usesMetric {
            return String(localized: "onboarding.profile.measurement_error.metric", defaultValue: "Use 90–250 cm for height and 25–350 kg for weight, or leave them blank.")
        }
        return String(localized: "onboarding.profile.measurement_error.imperial", defaultValue: "Use 35–98.5 in for height and 55–772 lb for weight, or leave them blank.")
    }
    private var hasTrainingProfileDetails: Bool {
        draft.birthDate != nil
            || draft.sexAtBirth != nil
            || parsedMeasurement(draft.heightText) != nil
            || parsedMeasurement(draft.weightText) != nil
    }
    private var requiredBodyProfileComplete: Bool {
        guard let birthDate = draft.birthDate,
              birthDate <= youngestBirthDate,
              birthDate >= oldestBirthDate,
              draft.sexAtBirth != nil,
              let weight = parsedMeasurement(draft.weightText)
        else { return false }
        return usesMetric ? (25...350).contains(weight) : (55...772).contains(weight)
    }
    private var trainingProfileRequest: TrainingProfileUpdateDTO {
        TrainingProfileUpdateDTO(
            sexAtBirth: draft.sexAtBirth,
            birthDate: draft.birthDate.map(Self.birthDateFormatter.string),
            heightCentimeters: parsedMeasurement(draft.heightText).map { usesMetric ? $0 : $0 * 2.54 },
            weightKilograms: parsedMeasurement(draft.weightText).map { usesMetric ? $0 : $0 * 0.45359237 },
            primaryMotivation: primaryMotivation,
            preferredRunGoalType: preferredRunGoalType
        )
    }
    private var primaryMotivation: RunnerPrimaryMotivation {
        switch draft.objective {
        case .eventPreparation, .endurance, .speed: .performance
        case .weightLoss: .weightLoss
        case .strength, .healthEnergy: .generalFitness
        }
    }
    private var preferredRunGoalType: PreferredRunGoalType {
        switch draft.objective {
        case .eventPreparation, .endurance: .distance
        case .weightLoss: .calories
        case .speed, .strength, .healthEnergy: .time
        }
    }

    private func parsedMeasurement(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private var draftHasTrainingDetails: Bool {
        draft.birthDate != nil || draft.sexAtBirth != nil
            || !draft.heightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.weightText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Restores the private-details step for a returning user: prefill measurements saved on the
    /// server, and treat Apple Health as already connected when the user previously granted access
    /// so the step does not always ask them to connect again.
    private func restoreTrainingProfileStep() {
        restoreDraftFromSavedTrainingProfile()
        guard !didConnectHealth else { return }

        if healthAuthorizationStore.snapshot.requestState == .reviewed {
            markHealthRestored()
        } else {
            Task {
                await healthAuthorizationStore.refresh()
                guard !didConnectHealth,
                      healthAuthorizationStore.lastErrorMessage == nil,
                      healthAuthorizationStore.snapshot.requestState == .reviewed
                else { return }
                markHealthRestored()
            }
        }
    }

    /// Reflects a previously-granted authorization, and quietly pulls HealthKit profile details
    /// only when the step is still completely blank so restored values are never overwritten.
    private func markHealthRestored() {
        didConnectHealth = true
        guard !draftHasTrainingDetails else { return }
        importHealthProfileData()
    }

    private func formattedMeasurement(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func normalizeBuilderChoices() {
        if !PlanObjective.availableInBuilder.contains(draft.objective) { draft.objective = .endurance }
        draft.activities = PlanActivity.availableInBuilder.filter(draft.activities.contains)
        if draft.activities.isEmpty { draft.activities = [.run] }
        draft.sessionsPerWeek = boundedSessionsPerWeek(draft.sessionsPerWeek)
        draft.recentSessionsPerWeek = min(max(draft.recentSessionsPerWeek, 0), 6)
        draft.preferredDays = Array(draft.preferredDays.prefix(draft.sessionsPerWeek))
        ensureObjectiveDefaults()
    }

    private func selectObjectiveQuickReply(_ objective: PlanObjective) {
        resetGoalDetails()
        selectObjective(objective)
        if objective == .eventPreparation, !draft.activities.contains(.run) {
            draft.activities.insert(.run, at: 0)
        }
        draft.objectiveConfirmed = true
        draft.goalInputText = nil
        interpretationReply = nil
        track(.planIntakeGoalInterpreted, [.result: .string("success"), .sourceType: .string("quick_reply")])
    }

    private func selectObjective(_ objective: PlanObjective) {
        draft.objective = objective
        ensureObjectiveDefaults()
    }

    private func resetGoalConversation() {
        resetGoalDetails()
        draft.objectiveConfirmed = nil
        draft.goalInputText = nil
        draft.goalDescription = nil
        goalMessage = ""
        interpretationReply = nil
    }

    private func editGoalConversation() {
        trackAnswerEdit("goal")
        resetGoalConversation()
    }

    private func resetGoalDetails() {
        draft.eventDistanceMeters = nil
        draft.eventDistanceConfirmed = nil
        draft.eventDistanceFromGoalText = nil
        draft.eventDate = nil
        draft.eventDateConfirmed = nil
        draft.eventDateFromGoalText = nil
        draft.eventIntent = nil
        draft.eventIntentConfirmed = nil
        draft.eventIntentFromGoalText = nil
        draft.targetTimeSeconds = nil
        draft.targetTimeConfirmed = nil
        draft.targetTimeFromGoalText = nil
        draft.reviewHorizonWeeks = nil
        draft.reviewHorizonConfirmed = nil
        draft.reviewHorizonFromGoalText = nil
        draft.successSignal = nil
    }

    private func ensureObjectiveDefaults() {
        if draft.objective == .eventPreparation {
            if draft.eventDate == nil { draft.eventDate = Self.defaultEventDate }
            if draft.eventDistanceMeters == nil { draft.eventDistanceMeters = 5_000 }
            if draft.eventIntent == nil { draft.eventIntent = "finish" }
            if draft.eventIntent == "targetTime", draft.targetTimeSeconds == nil {
                draft.targetTimeSeconds = defaultTargetTimeSeconds(for: draft.eventDistanceMeters ?? 5_000)
            }
        } else if draft.reviewHorizonWeeks == nil {
            draft.reviewHorizonWeeks = 8
        }
    }

    @ViewBuilder
    private var eventConversationFields: some View {
        if draft.eventDistanceConfirmed != true {
            coachMessage(String(localized: "plan_builder.conversation.event_distance", defaultValue: "What distance is the event?"))
            LazyVGrid(columns: Self.choiceColumns, spacing: 8) {
                eventDistanceChoice("5K", meters: 5_000)
                eventDistanceChoice("10K", meters: 10_000)
                eventDistanceChoice(String(localized: "plan_builder.event.half", defaultValue: "Half marathon"), meters: 21_097.5)
                eventDistanceChoice(String(localized: "plan_builder.event.marathon", defaultValue: "Marathon"), meters: 42_195)
            }
            .padding(.leading, 48)
        } else {
            editableRunnerMessage(eventDistanceTitle, field: "event_distance") {
                editEventDistance()
            }
            if draft.eventDateConfirmed != true {
                coachMessage(String(localized: "plan_builder.conversation.event_date", defaultValue: "When is the event?"))
                eventDateButton
                    .padding(.leading, 48)
            } else {
                editableRunnerMessage(
                    (draft.eventDate ?? Self.defaultEventDate).formatted(date: .long, time: .omitted),
                    field: "event_date"
                ) {
                    editEventDate()
                }
                if draft.eventIntentConfirmed != true {
                    coachMessage(String(localized: "plan_builder.event.intent", defaultValue: "What matters most?"))
                    VStack(spacing: 8) {
                        conversationChoiceButton(String(localized: "plan_builder.event.intent.finish", defaultValue: "Finish comfortably")) {
                            confirmEventIntent("finish")
                        }
                        conversationChoiceButton(String(localized: "plan_builder.event.intent.perform", defaultValue: "Perform strongly")) {
                            confirmEventIntent("perform")
                        }
                        conversationChoiceButton(String(localized: "plan_builder.event.intent.time", defaultValue: "Target a time")) {
                            confirmEventIntent("targetTime")
                        }
                    }
                    .padding(.leading, 48)
                } else {
                    editableRunnerMessage(eventIntentTitle, field: "event_intent") {
                        editEventIntent()
                    }
                    if draft.eventIntent == "targetTime" {
                        if draft.targetTimeConfirmed != true {
                            coachMessage(String(localized: "plan_builder.conversation.target_time", defaultValue: "What time are you aiming for?"))
                            VStack(spacing: 10) {
                                Stepper(
                                    targetTimeTitle,
                                    value: Binding(
                                        get: { max(15, (draft.targetTimeSeconds ?? defaultTargetTimeSeconds(for: draft.eventDistanceMeters ?? 5_000)) / 60) },
                                        set: { draft.targetTimeSeconds = $0 * 60 }
                                    ),
                                    in: 15...720,
                                    step: 5
                                )
                                .planBuilderCard()
                                Button(String(localized: "plan_builder.conversation.confirm_time", defaultValue: "Use this target time")) {
                                    draft.targetTimeConfirmed = true
                                    draft.targetTimeFromGoalText = nil
                                }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .padding(.leading, 48)
                        } else {
                            editableRunnerMessage(targetTimeTitle, field: "target_time") {
                                editTargetTime()
                            }
                        }
                    }
                }
            }
        }
    }

    private var eventDateButton: some View {
        Button {
            ensureObjectiveDefaults()
            isEventDatePickerPresented = true
        } label: {
            HStack {
                Text(String(localized: "plan_builder.conversation.choose_date", defaultValue: "Choose event date"))
                Spacer()
                Image(systemName: "calendar")
                    .foregroundStyle(OutboundPalette.companion)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .planBuilderCard()
    }

    private func eventDistanceChoice(_ title: String, meters: Double) -> some View {
        conversationChoiceButton(title) {
            draft.eventDistanceMeters = meters
            draft.eventDistanceConfirmed = true
            if draft.eventIntent == "targetTime", draft.targetTimeConfirmed != true {
                draft.targetTimeSeconds = defaultTargetTimeSeconds(for: meters)
            }
        }
    }

    @ViewBuilder
    private var genericGoalConversationFields: some View {
        if draft.reviewHorizonConfirmed != true {
            coachMessage(String(localized: "plan_builder.generic.review_horizon", defaultValue: "When should we review this focus?"))
            HStack(spacing: 8) {
                reviewHorizonChoice(4)
                reviewHorizonChoice(8)
                reviewHorizonChoice(12)
            }
            .padding(.leading, 48)
        } else {
            editableRunnerMessage(reviewHorizonTitle, field: "review_horizon") {
                editReviewHorizon()
            }
            coachMessage(
                String(localized: "plan_builder.generic.success", defaultValue: "What would meaningful progress feel like?"),
                detail: String(localized: "plan_builder.conversation.optional_answer", defaultValue: "Optional — you can continue without adding anything.")
            )
            TextField(
                String(localized: "plan_builder.conversation.success_placeholder", defaultValue: "For example: longer runs feel comfortable"),
                text: Binding(get: { draft.successSignal ?? "" }, set: { draft.successSignal = $0 }),
                axis: .vertical
            )
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)
            .padding(.leading, 48)
        }
    }

    private func reviewHorizonChoice(_ weeks: Int) -> some View {
        Button(String(format: String(localized: "plan_builder.conversation.weeks", defaultValue: "%d weeks"), locale: .autoupdatingCurrent, weeks)) {
            draft.reviewHorizonWeeks = weeks
            draft.reviewHorizonConfirmed = true
            draft.reviewHorizonFromGoalText = nil
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private func defaultTargetTimeSeconds(for distanceMeters: Double) -> Int {
        switch distanceMeters {
        case ..<7_500: 30 * 60
        case ..<15_000: 60 * 60
        case ..<30_000: 120 * 60
        default: 240 * 60
        }
    }

    private func confirmEventIntent(_ intent: String) {
        draft.eventIntent = intent
        draft.eventIntentConfirmed = true
        draft.eventIntentFromGoalText = nil
        if intent == "targetTime", draft.targetTimeSeconds == nil {
            draft.targetTimeSeconds = defaultTargetTimeSeconds(for: draft.eventDistanceMeters ?? 5_000)
        }
        if intent != "targetTime" { draft.targetTimeConfirmed = nil }
    }

    private func editEventDistance() {
        draft.eventDistanceConfirmed = nil
        draft.eventDistanceFromGoalText = nil
        if draft.eventIntent == "targetTime" {
            draft.targetTimeConfirmed = nil
            draft.targetTimeFromGoalText = nil
        }
    }

    private func editEventDate() {
        draft.eventDateConfirmed = nil
        draft.eventDateFromGoalText = nil
    }

    private func editEventIntent() {
        draft.eventIntentConfirmed = nil
        draft.eventIntentFromGoalText = nil
        draft.targetTimeConfirmed = nil
        draft.targetTimeFromGoalText = nil
    }

    private func editTargetTime() {
        draft.targetTimeConfirmed = nil
        draft.targetTimeFromGoalText = nil
    }

    private func editReviewHorizon() {
        draft.reviewHorizonConfirmed = nil
        draft.reviewHorizonFromGoalText = nil
    }

    private func trackAnswerEdit(_ field: String) {
        track(.planIntakeAnswerEdited, [
            .selectionType: .string(field),
            .sourceType: .string("conversation"),
        ])
    }

    private func boundedSessionsPerWeek(_ value: Int) -> Int {
        min(max(value, 1), 6)
    }

    private func planningErrorCategory(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case let .http(statusCode, _, _):
                switch statusCode {
                case 400: return "http_400"
                case 409: return "http_409"
                case 400..<500: return "http_4xx"
                case 500..<600: return "http_5xx"
                default: return "http_other"
                }
            }
        }
        if error is URLError { return "network" }
        if error is DecodingError { return "decoding" }
        return "unknown"
    }

    private var goalResponseText: String {
        guard let value = draft.goalInputText?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return draft.objective.title
        }
        return value
    }

    private var goalAcknowledgement: String {
        var parts: [String] = []
        if draft.objective == .eventPreparation {
            parts.append(draft.eventDistanceFromGoalText == true ? eventDistanceTitle : draft.objective.title)
            if draft.eventDateFromGoalText == true, let eventDate = draft.eventDate {
                parts.append(eventDate.formatted(date: .abbreviated, time: .omitted))
            }
            if draft.eventIntentFromGoalText == true { parts.append(eventIntentTitle) }
            if draft.targetTimeFromGoalText == true, let seconds = draft.targetTimeSeconds {
                parts.append(String(
                    format: String(localized: "plan_builder.event.target_minutes", defaultValue: "Target time: %d min"),
                    locale: .autoupdatingCurrent,
                    seconds / 60
                ))
            }
        } else {
            parts.append(draft.objective.title)
            if draft.reviewHorizonFromGoalText == true { parts.append(reviewHorizonTitle) }
        }
        return String(
            format: String(localized: "plan_builder.conversation.goal_acknowledged", defaultValue: "%@ — got it."),
            locale: .autoupdatingCurrent,
            parts.joined(separator: " · ")
        )
    }

    private var eventDistanceTitle: String {
        switch draft.eventDistanceMeters ?? 5_000 {
        case ..<7_500: return "5K"
        case ..<15_000: return "10K"
        case ..<30_000: return String(localized: "plan_builder.event.half", defaultValue: "Half marathon")
        default: return String(localized: "plan_builder.event.marathon", defaultValue: "Marathon")
        }
    }

    private var eventIntentTitle: String {
        switch draft.eventIntent {
        case "perform": return String(localized: "plan_builder.event.intent.perform", defaultValue: "Perform strongly")
        case "targetTime": return String(localized: "plan_builder.event.intent.time", defaultValue: "Target a time")
        default: return String(localized: "plan_builder.event.intent.finish", defaultValue: "Finish comfortably")
        }
    }

    private var reviewHorizonTitle: String {
        String(
            format: String(localized: "plan_builder.conversation.weeks", defaultValue: "%d weeks"),
            locale: .autoupdatingCurrent,
            draft.reviewHorizonWeeks ?? 8
        )
    }

    private var targetTimeTitle: String {
        String(
            format: String(localized: "plan_builder.event.target_minutes", defaultValue: "Target time: %d min"),
            locale: .autoupdatingCurrent,
            max(15, (draft.targetTimeSeconds ?? defaultTargetTimeSeconds(for: draft.eventDistanceMeters ?? 5_000)) / 60)
        )
    }

    private var eventDetailsComplete: Bool {
        guard draft.eventDistanceConfirmed == true,
              draft.eventDistanceMeters != nil,
              draft.eventDateConfirmed == true,
              draft.eventDate != nil,
              draft.eventIntentConfirmed == true,
              draft.eventIntent != nil
        else { return false }
        return draft.eventIntent != "targetTime"
            || (draft.targetTimeConfirmed == true && draft.targetTimeSeconds != nil)
    }

    private var eventDatePickerSheet: some View {
        NavigationStack {
            DatePicker(
                String(localized: "plan_builder.event.date", defaultValue: "Event date"),
                selection: Binding(get: { draft.eventDate ?? Self.defaultEventDate }, set: { draft.eventDate = $0 }),
                in: Calendar.current.startOfDay(for: Date())...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(OutboundSpacing.screen)
            .navigationTitle(String(localized: "plan_builder.event.date", defaultValue: "Event date"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done", defaultValue: "Done")) {
                        draft.eventDateConfirmed = true
                        isEventDatePickerPresented = false
                    }
                }
            }
            .onChange(of: draft.eventDate) { _, _ in
                draft.eventDateConfirmed = true
                draft.eventDateFromGoalText = nil
                isEventDatePickerPresented = false
            }
        }
        .presentationDetents([.medium])
    }

    private func applyIntakeContext(_ context: PlanIntakeContextDTO) {
        isLoadingIntakeContext = false
        intakeContext = context
        draft.intakeContextVersion = context.contextVersion
        track(.planIntakeContextLoaded, [.sourceType: .string(context.dataTier)])
        if let setup = context.suggestedSetup,
           setup.confidence == "high",
           draft.observedBaselineConfirmed != false {
            let inferredActivities = PlanActivity.availableInBuilder.filter { setup.activities.contains($0.rawValue) }
            if !inferredActivities.isEmpty { draft.activities = inferredActivities }
            draft.baselineContext = PlanBaselineContext(rawValue: setup.baselineContext) ?? .currentlyActive
            let inferredSessionsPerWeek = boundedSessionsPerWeek(setup.sessionsPerWeek)
            draft.recentSessionsPerWeek = inferredSessionsPerWeek
            draft.sessionsPerWeek = inferredSessionsPerWeek
            draft.availableMinutes = setup.maxSessionMinutes
            draft.preferredDays = Array(setup.preferredDays.prefix(inferredSessionsPerWeek))
            if let comfortable = context.observedBaseline?.comfortableMinutes {
                draft.comfortableMinutes = comfortable
            }
        } else if let baseline = context.observedBaseline,
                  baseline.confidence == "high",
                  draft.observedBaselineConfirmed == nil {
            draft.recentSessionsPerWeek = min(max(baseline.sessionsPerWeek, 0), 6)
            if let comfortable = baseline.comfortableMinutes { draft.comfortableMinutes = comfortable }
            let inferredActivities = PlanActivity.availableInBuilder.filter { baseline.activityMix.contains($0.rawValue) }
            if !inferredActivities.isEmpty { draft.activities = inferredActivities }
        }
        if context.suggestedSetup == nil, let schedule = context.previousSchedule {
            draft.sessionsPerWeek = boundedSessionsPerWeek(schedule.sessionsPerWeek)
            draft.availableMinutes = schedule.maxSessionMinutes
            draft.preferredDays = Array(schedule.preferredDays.prefix(draft.sessionsPerWeek))
        }
        if savedTrainingProfile == nil {
            savedTrainingProfile = TrainingProfileDTO(
                sexAtBirth: context.bodyProfile.sexAtBirth,
                birthDate: context.bodyProfile.birthDate,
                heightCentimeters: context.bodyProfile.heightCentimeters,
                weightKilograms: context.bodyProfile.weightKilograms,
                primaryMotivation: primaryMotivation,
                preferredRunGoalType: preferredRunGoalType
            )
            restoreDraftFromSavedTrainingProfile()
        }
    }

    private func interpretGoal() {
        let message = goalMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        isGoalInputFocused = false
        isInterpretingGoal = true
        interpretationReply = nil
        Task {
            do {
                let context: PlanIntakeContextDTO
                if let intakeContext {
                    context = intakeContext
                } else {
                    context = try await APIClient.shared.fetchPlanIntakeContext(
                        objective: draft.objectiveConfirmed == true ? draft.objective.rawValue : nil
                    )
                    applyIntakeContext(context)
                }
                let payload = PlanIntakeInterpretRequestDTO(
                    message: message,
                    contextVersion: context.contextVersion,
                    draft: .init(
                        objective: draft.objectiveConfirmed == true ? draft.objective.rawValue : nil,
                        activities: [],
                        eventDate: draft.eventDateConfirmed == true ? draft.eventDate.map(Self.apiDateFormatter.string) : nil,
                        eventDistanceMeters: draft.eventDistanceConfirmed == true ? draft.eventDistanceMeters : nil,
                        eventIntent: draft.eventIntentConfirmed == true ? draft.eventIntent : nil,
                        targetTimeSeconds: draft.targetTimeConfirmed == true ? draft.targetTimeSeconds : nil,
                        reviewHorizonWeeks: draft.reviewHorizonConfirmed == true ? draft.reviewHorizonWeeks : nil,
                        sessionsPerWeek: boundedSessionsPerWeek(draft.sessionsPerWeek),
                        maxSessionMinutes: draft.availableMinutes
                    )
                )
                let result = try await APIClient.shared.interpretPlanIntake(payload)
                guard let objective = result.objective.flatMap(PlanObjective.init(rawValue:)) else {
                    interpretationReply = result.assistantReply
                    track(.planIntakeGoalInterpreted, [
                        .result: .string("failure"),
                        .sourceType: .string("conversation_text"),
                        .errorCategory: .string("unsupported_goal"),
                    ])
                    isInterpretingGoal = false
                    return
                }
                let recognized = Set(result.recognizedFields)
                resetGoalDetails()
                selectObjective(objective)
                draft.objectiveConfirmed = true
                draft.goalInputText = message
                let interpretedActivities = result.activities.compactMap(PlanActivity.init(rawValue:))
                if !interpretedActivities.isEmpty {
                    draft.activities = PlanActivity.availableInBuilder.filter {
                        interpretedActivities.contains($0) || draft.activities.contains($0)
                    }
                }
                if recognized.contains("eventDate"), let value = result.eventDate.flatMap(Self.apiDateFormatter.date(from:)) {
                    draft.eventDate = value
                    draft.eventDateConfirmed = true
                    draft.eventDateFromGoalText = true
                }
                if recognized.contains("eventDistanceMeters"), let value = result.eventDistanceMeters {
                    draft.eventDistanceMeters = value
                    draft.eventDistanceConfirmed = true
                    draft.eventDistanceFromGoalText = true
                }
                if recognized.contains("eventIntent"), let value = result.eventIntent {
                    draft.eventIntent = value
                    draft.eventIntentConfirmed = true
                    draft.eventIntentFromGoalText = true
                }
                if recognized.contains("targetTimeSeconds"), let value = result.targetTimeSeconds {
                    draft.targetTimeSeconds = value
                    draft.targetTimeConfirmed = true
                    draft.targetTimeFromGoalText = true
                    if !recognized.contains("eventIntent") {
                        draft.eventIntent = "targetTime"
                        draft.eventIntentConfirmed = true
                        draft.eventIntentFromGoalText = true
                    }
                }
                if recognized.contains("reviewHorizonWeeks"), let value = result.reviewHorizonWeeks {
                    draft.reviewHorizonWeeks = value
                    draft.reviewHorizonConfirmed = true
                    draft.reviewHorizonFromGoalText = true
                }
                draft.goalDescription = result.goalDescription ?? message
                ensureObjectiveDefaults()
                interpretationReply = nil
                track(.planIntakeGoalInterpreted, [.result: .string("success"), .sourceType: .string("conversation_text")])
            } catch {
                interpretationReply = String(localized: "plan_builder.coach_prompt.error", defaultValue: "I couldn’t interpret that reliably. Try again or choose a quick reply.")
                track(.planIntakeGoalInterpreted, [
                    .result: .string("failure"),
                    .sourceType: .string("conversation_text"),
                    .errorCategory: .string(planningErrorCategory(error)),
                ])
            }
            isInterpretingGoal = false
        }
    }

    private func observedBaselineSummary(_ baseline: PlanIntakeObservedBaselineDTO) -> String {
        String(
            format: String(localized: "plan_builder.baseline.observed_summary", defaultValue: "%1$d sessions across %2$d weeks · typically %3$d min · longest %4$d min"),
            locale: .autoupdatingCurrent,
            baseline.sessionCount,
            baseline.activeWeekCount,
            baseline.comfortableMinutes ?? 0,
            baseline.longestSessionMinutes ?? 0
        )
    }

    private func advance() {
        if step == .objective { ensureObjectiveDefaults() }
        switch step {
        case .activities where draft.observedBaselineConfirmed == true && intakeContext?.suggestedSetup?.confidence == "high":
            step = intakeContext?.bodyProfile.completeForPlanning == true || requiredBodyProfileComplete ? .review : .profile
        case .week where intakeContext?.bodyProfile.completeForPlanning == true || requiredBodyProfileComplete:
            step = .review
        default:
            step = step.next
        }
    }

    private func goBack() {
        switch step {
        case .profile where draft.observedBaselineConfirmed == true && intakeContext?.suggestedSetup?.confidence == "high":
            step = .activities
        case .review where intakeContext?.bodyProfile.completeForPlanning == true || requiredBodyProfileComplete:
            step = draft.observedBaselineConfirmed == true && intakeContext?.suggestedSetup?.confidence == "high" ? .activities : .week
        default:
            step = step.previous
        }
    }

    private var shouldPresentSuggestedSetup: Bool {
        step == .activities
            && intakeContext?.suggestedSetup?.confidence == "high"
            && draft.observedBaselineConfirmed != false
    }

    private var shouldHideActivitiesFooter: Bool {
        shouldPresentSuggestedSetup || (step == .activities && isLoadingIntakeContext && intakeContext == nil)
    }

    private func acceptSuggestedSetup() {
        draft.observedBaselineConfirmed = true
        track(.planIntakeBaselineConfirmed, [.result: .string("accepted"), .sourceType: .string("recent_activity_setup")])
        advance()
    }

    private var setupActivitiesTitle: String {
        draft.activities
            .map(\.title)
            .joined(separator: " · ")
    }

    private func setupDaysTitle(_ setup: PlanIntakeSuggestedSetupDTO) -> String {
        setup.preferredDays.compactMap { code in
            Self.weekdays.first(where: { $0.code == code })?.label
        }.joined(separator: " · ")
    }

    private func smartSetupRow(_ title: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(OutboundPalette.companion)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.body.weight(.semibold))
            }
        }
    }

    private func coachMessage(_ text: String, detail: String? = nil, isError: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isError ? "exclamationmark" : "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(isError ? Color.red : OutboundPalette.companion)
                .frame(width: 34, height: 34)
                .background(
                    (isError ? Color.red : OutboundPalette.companion).opacity(0.12),
                    in: Circle()
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.headline)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: OutboundRadius.control))
            Spacer(minLength: 28)
        }
    }

    private func editableRunnerMessage(_ text: String, field: String, action: @escaping () -> Void) -> some View {
        HStack {
            Spacer(minLength: 48)
            Button {
                trackAnswerEdit(field)
                action()
            } label: {
                HStack(spacing: 7) {
                    Text(text)
                    Image(systemName: "pencil")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(OutboundPalette.companion, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                String(
                    format: String(localized: "plan_builder.conversation.edit_answer", defaultValue: "Edit %@"),
                    locale: .autoupdatingCurrent,
                    text
                )
            )
        }
    }

    private var coachTypingIndicator: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(OutboundPalette.companion)
                .frame(width: 34, height: 34)
                .background(OutboundPalette.companion.opacity(0.12), in: Circle())
            ProgressView()
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground), in: Capsule())
            Spacer()
        }
        .accessibilityLabel(String(localized: "plan_builder.conversation.thinking", defaultValue: "Understanding your goal"))
    }

    private func conversationChoiceButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.title2.weight(.semibold)); Text(subtitle).foregroundStyle(.secondary) }
    }
    private func optionTile(_ title: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .padding(12)
            .background(selected ? OutboundPalette.companion.opacity(0.14) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: OutboundRadius.control))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? OutboundPalette.companion : .primary)
    }
    private func selectionRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack { Text(title); Spacer(); Image(systemName: selected ? "checkmark.circle.fill" : "circle") }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading) }
            .buttonStyle(.bordered).tint(selected ? OutboundPalette.companion : .secondary)
    }
    private func toggleChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if selected { Image(systemName: "xmark").font(.caption2.weight(.bold)) }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(selected ? OutboundPalette.companion.opacity(0.18) : Color(.secondarySystemBackground), in: Capsule())
        }
            .buttonStyle(.plain)
    }
    private func trainingMeasurementField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField(title, text: text).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity)
    }
    private func summaryRow(_ label: String, _ value: String) -> some View {
        OutboundCard { VStack(alignment: .leading, spacing: 4) { Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Text(value).font(.headline) } }
    }

    private var validDisplayName: Bool { guard let value = authStore.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }; return !value.isEmpty && value.caseInsensitiveCompare("Runner") != .orderedSame }
    private var validEmail: Bool { Self.isValidEmail(authStore.user?.email ?? "") }
    private var shouldShowIdentityPrompt: Bool { isFirstUse && !identityCompleted && (!validDisplayName || !validEmail) }
    private var cleanedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var identityFormIsValid: Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-") )
        return !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (3...30).contains(cleanedUsername.count) && cleanedUsername.unicodeScalars.allSatisfy(allowed.contains) && (validEmail || Self.isValidEmail(email))
    }
    private static func isValidEmail(_ value: String) -> Bool { let parts = value.split(separator: "@", omittingEmptySubsequences: false); return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") }
    private var objectiveConversationProgress: String {
        [
            draft.objectiveConfirmed,
            draft.eventDistanceConfirmed,
            draft.eventDateConfirmed,
            draft.eventIntentConfirmed,
            draft.targetTimeConfirmed,
            draft.reviewHorizonConfirmed,
        ]
        .map { $0 == true ? "1" : "0" }
        .joined()
    }
    private var progressCount: Int { isFirstUse ? 7 : 6 }
    private var progressIndex: Int { max(1, isFirstUse ? step.rawValue + 1 : step.rawValue) }
    private static let weekdays: [(code: String, label: String)] = [
        ("mon", String(localized: "weekday.mon", defaultValue: "Mon")), ("tue", String(localized: "weekday.tue", defaultValue: "Tue")),
        ("wed", String(localized: "weekday.wed", defaultValue: "Wed")), ("thu", String(localized: "weekday.thu", defaultValue: "Thu")),
        ("fri", String(localized: "weekday.fri", defaultValue: "Fri")), ("sat", String(localized: "weekday.sat", defaultValue: "Sat")),
        ("sun", String(localized: "weekday.sun", defaultValue: "Sun")),
    ]
    private static let choiceColumns = [GridItem(.flexible()), GridItem(.flexible())]
    private static let dayColumns = Array(repeating: GridItem(.flexible()), count: 4)
    private static let apiDateFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter }()
    private static let birthDateFormatter: DateFormatter = { let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; return formatter }()
    private static let defaultBirthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    private static let defaultEventDate = Calendar.current.date(byAdding: .weekOfYear, value: 8, to: Date()) ?? Date()
    private static let conversationBottomID = "plan-builder-conversation-bottom"
}

private extension SimplifiedOnboardingFlow {
    enum ToastRetry {
        case skip
        case create
        case profile
    }

    enum Step: Int, CaseIterable {
        case welcome, objective, activities, baseline, week, profile, review, creating, result
        var next: Self { Self(rawValue: rawValue + 1) ?? self }
        var previous: Self { Self(rawValue: rawValue - 1) ?? self }
        var canGoBack: Bool { [.objective, .activities, .baseline, .week, .profile, .review].contains(self) }
        var analyticsValue: String {
            switch self { case .welcome: "welcome"; case .objective: "objective_conversation"; case .activities: "activities"; case .baseline: "baseline"; case .week: "week"; case .profile: "private_details"; case .review: "review"; case .creating: "creating"; case .result: "result" }
        }
    }
}

private extension View {
    func planBuilderCard() -> some View { padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: OutboundRadius.control)) }
}
