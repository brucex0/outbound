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
                    ScrollView {
                        VStack(alignment: .leading, spacing: OutboundSpacing.standard) { content }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(OutboundSpacing.screen)
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
        .onAppear { configure() }
        .onChange(of: draft) { _, value in onboardingStore.savePlanBuilderDraft(value) }
        .onChange(of: step) { _, value in
            if value == .profile { trackProfileViewIfNeeded() }
        }
        .animation(.snappy, value: toastMessage)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if step.canGoBack {
                Button(String(localized: "onboarding.action.back", defaultValue: "Back"), systemImage: "chevron.left") { step = step.previous }
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
        VStack(alignment: .leading, spacing: 14) {
            heading(
                String(localized: "plan_builder.objective.title", defaultValue: "What do you want this plan to help you achieve?"),
                String(localized: "plan_builder.objective.subtitle", defaultValue: "Choose the one outcome that matters most right now.")
            )
            LazyVGrid(columns: Self.choiceColumns, spacing: 10) {
                ForEach(PlanObjective.availableInBuilder) { objective in
                    optionTile(objective.title, systemImage: objective.systemImage, selected: draft.objective == objective) {
                        draft.objective = objective
                    }
                }
            }
            if draft.objective == .other {
                TextField(String(localized: "plan_builder.objective.other_prompt", defaultValue: "Describe your objective"), text: $draft.otherObjective, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }
            if draft.objective == .eventPreparation { eventFields }
        }
    }

    private var activitiesContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(
                String(localized: "plan_builder.activities.title", defaultValue: "Which activities should your plan use?"),
                String(localized: "plan_builder.activities.subtitle", defaultValue: "Choose one or more. Plainstride will balance them across your week.")
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

    private var baselineContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(
                String(localized: "plan_builder.baseline.title", defaultValue: "Where are you starting from?"),
                String(localized: "plan_builder.baseline.subtitle", defaultValue: "A rough starting point is enough. Your first three relevant sessions will refine it.")
            )
            ForEach(PlanBaselineContext.allCases) { context in
                selectionRow(context.title, selected: draft.baselineContext == context) { draft.baselineContext = context }
            }
            Stepper(String(format: String(localized: "plan_builder.baseline.frequency", defaultValue: "Recent sessions: %d per week"), locale: .autoupdatingCurrent, draft.recentSessionsPerWeek), value: $draft.recentSessionsPerWeek, in: 0...6)
                .planBuilderCard()
            Stepper(String(format: String(localized: "plan_builder.baseline.duration", defaultValue: "Comfortable session: %d min"), locale: .autoupdatingCurrent, draft.comfortableMinutes), value: $draft.comfortableMinutes, in: 10...120, step: 5)
                .planBuilderCard()
        }
    }

    private var weekContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(
                String(localized: "plan_builder.week.title", defaultValue: "What can most weeks support?"),
                String(localized: "plan_builder.week.subtitle", defaultValue: "Choose what is realistic. Preferred days are optional.")
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
            if needsLongSessionDay {
                Picker(String(localized: "plan_builder.week.long_day", defaultValue: "Long-session day (optional)"), selection: $draft.preferredLongSessionDay) {
                    Text(String(localized: "common.no_preference", defaultValue: "No preference")).tag(nil as String?)
                    ForEach(Self.weekdays, id: \.code) { Text($0.label).tag($0.code as String?) }
                }
                .planBuilderCard()
            }
            TextField(String(localized: "plan_builder.week.constraints", defaultValue: "Injury, illness, travel, or schedule constraints (optional)"), text: $draft.constraints, axis: .vertical)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var privateDetailsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(
                String(localized: "onboarding.profile.title", defaultValue: "Optional private details"),
                String(localized: "onboarding.profile.subtitle", defaultValue: "Connect Apple Health if you want Plainstride to use available activity and profile details.")
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
                            in: oldestBirthDate...Date(),
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
        }
    }

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading(
                String(localized: "plan_builder.review.title", defaultValue: "Ready to create your plan"),
                String(localized: "plan_builder.review.subtitle", defaultValue: "Plainstride will schedule the next 7–14 days and adapt what comes after.")
            )
            summaryRow(String(localized: "plan_builder.review.objective", defaultValue: "Goal"), draft.objective.title)
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

    private var footer: some View {
        VStack(spacing: 10) {
            OutboundPrimaryButton(title: primaryButtonTitle, systemImage: step == .result ? "arrow.right" : "sparkles") { primaryAction() }
                .disabled(primaryDisabled)
            if isFirstUse, step == .welcome {
                Button(String(localized: "plan_builder.explore", defaultValue: "Explore first")) { exploreFirst() }
                    .font(.headline).disabled(isResolvingSkip)
            } else if step == .profile {
                Button(String(localized: "onboarding.profile.skip", defaultValue: "Skip for now")) { skipTrainingProfile() }
                    .font(.subheadline.weight(.semibold))
                    .disabled(isConnectingHealth || isSavingTrainingProfile)
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
            || draft.activities.isEmpty
            || (draft.objective == .other && draft.otherObjective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func primaryAction() {
        if shouldShowIdentityPrompt { Task { await saveIdentity() }; return }
        switch step {
        case .welcome: step = .objective
        case .profile: Task { await saveTrainingProfileAndContinue() }
        case .review: createPlan()
        case .result: onboardingStore.finishLater(); onComplete()
        default: step = step.next
        }
    }

    private func configure() {
        draft = onboardingStore.loadPlanBuilderDraft()
        normalizeBuilderChoices()
        step = isFirstUse ? .welcome : .objective
        displayName = validDisplayName ? (authStore.user?.displayName ?? "") : ""
        username = authStore.user?.username == "runner" ? "" : (authStore.user?.username ?? "")
        email = validEmail ? (authStore.user?.email ?? "") : ""
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
                trackCreation(result: "failure")
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
            priority: draft.objective == .eventPreparation ? "finish" : "generalHealth",
            preferredDays: draft.preferredDays,
            preferredLongSessionDay: needsLongSessionDay ? draft.preferredLongSessionDay : nil,
            daysPerWeekTarget: draft.sessionsPerWeek,
            maxSessionMinutes: draft.availableMinutes,
            riskTolerance: draft.baselineContext == .returningAfterBreak ? "conservative" : "balanced",
            constraints: ["notes": draft.constraints, "otherObjective": draft.otherObjective].filter { !$0.value.isEmpty }
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
        guard trainingMeasurementsAreValid, !isSavingTrainingProfile else { return }
        guard hasTrainingProfileDetails else {
            skipTrainingProfile()
            return
        }

        isSavingTrainingProfile = true
        do {
            let profile = try await APIClient.shared.updateTrainingProfile(trainingProfileRequest)
            onboardingStore.applyTrainingProfile(profile)
            isSavingTrainingProfile = false
            await trackTrainingProfileCompletion(result: "saved", source: didConnectHealth ? "health" : "manual")
            step = .review
        } catch {
            isSavingTrainingProfile = false
            showToast(String(localized: "Could not save profile. Try again."), retry: .profile)
        }
    }

    private func skipTrainingProfile() {
        track(
            .onboardingTrainingProfileCompleted,
            [.result: .string("skipped"), .sourceType: .string(didConnectHealth ? "health" : "manual")]
        )
        step = .review
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

    private func trackCreation(result: String) {
        let seconds = Date().timeIntervalSince(creationStartedAt ?? Date())
        let bucket = seconds < 2 ? "under_2s" : seconds < 5 ? "2s_5s" : seconds < 10 ? "5s_10s" : "10s_plus"
        track(.planCreationCompleted, [
            .result: .string(result),
            .latencyBucket: .string(bucket),
            .goalType: .string(draft.objective.rawValue),
            .countBucket: .string("activities_\(draft.activities.count)"),
        ])
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
    private var needsLongSessionDay: Bool { draft.sessionsPerWeek > 1 }

    private var usesMetric: Bool { measurementPreferences.unitSystem == .metric }
    private var heightLabel: String { usesMetric ? String(localized: "Height (cm)") : String(localized: "Height (in)") }
    private var weightLabel: String { usesMetric ? String(localized: "Weight (kg)") : String(localized: "Weight (lb)") }
    private var healthConnectionTitle: String {
        if didConnectHealth { return String(localized: "onboarding.health.connected", defaultValue: "Apple Health connected") }
        if isConnectingHealth { return String(localized: "onboarding.health.connecting", defaultValue: "Connecting…") }
        return String(localized: "onboarding.health.connect", defaultValue: "Connect Apple Health")
    }
    private var oldestBirthDate: Date { Calendar.current.date(byAdding: .year, value: -120, to: Date()) ?? .distantPast }
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
        case .fitnessMaintenance: .weightMaintenance
        case .strength, .healthEnergy, .other: .generalFitness
        }
    }
    private var preferredRunGoalType: PreferredRunGoalType {
        switch draft.objective {
        case .eventPreparation, .endurance: .distance
        case .weightLoss: .calories
        case .speed, .strength, .fitnessMaintenance, .healthEnergy, .other: .time
        }
    }

    private func parsedMeasurement(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private func formattedMeasurement(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func normalizeBuilderChoices() {
        if !PlanObjective.availableInBuilder.contains(draft.objective) { draft.objective = .endurance }
        draft.activities = PlanActivity.availableInBuilder.filter(draft.activities.contains)
        if draft.activities.isEmpty { draft.activities = [.run] }
    }

    private var eventFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(String(localized: "plan_builder.event.distance", defaultValue: "Event distance"), selection: $draft.eventDistanceMeters) {
                Text("5K").tag(5_000.0 as Double?)
                Text("10K").tag(10_000.0 as Double?)
                Text(String(localized: "plan_builder.event.half", defaultValue: "Half marathon")).tag(21_097.5 as Double?)
                Text(String(localized: "plan_builder.event.marathon", defaultValue: "Marathon")).tag(42_195.0 as Double?)
            }.planBuilderCard()
            DatePicker(String(localized: "plan_builder.event.date", defaultValue: "Event date"), selection: Binding(get: { draft.eventDate ?? Date().addingTimeInterval(60 * 60 * 24 * 56) }, set: { draft.eventDate = $0 }), in: Date()..., displayedComponents: .date).planBuilderCard()
        }
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
            switch self { case .welcome: "welcome"; case .objective: "objective"; case .activities: "activities"; case .baseline: "baseline"; case .week: "week"; case .profile: "private_details"; case .review: "review"; case .creating: "creating"; case .result: "result" }
        }
    }
}

private extension View {
    func planBuilderCard() -> some View { padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: OutboundRadius.control)) }
}
