import SwiftUI

struct SimplifiedOnboardingFlow: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var onboardingStore: OnboardingStore
    @EnvironmentObject private var personalizationStore: PersonalizationStore
    @EnvironmentObject private var trainingPlanStore: TrainingPlanStore
    @EnvironmentObject private var healthAuthorizationStore: HealthAuthorizationStore
    @EnvironmentObject private var healthImportStore: HealthImportStore
    let onComplete: (OnboardingProfile) -> Void

    @State private var step: Step = .goal
    @State private var goal = Goal.consistency
    @State private var frequency = Frequency.oneOrTwo
    @State private var comfortableMinutes = 30
    @State private var runsPerWeek = 3
    @State private var availableMinutes = 30
    @State private var isSavingIdentity = false
    @State private var identityError: String?
    @State private var identityPromptTracked = false
    @State private var identityCompleted = false
    @State private var promptedForMissingDisplayName = false
    @State private var promptedForMissingEmail = false
    @State private var displayName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var isImportingHealth = false
    @State private var healthImportSummary: String?
    @State private var healthImportError: String?
    @State private var isCompleting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(progressIndex), total: Double(progressCount))
                    .tint(OutboundPalette.companion)
                    .padding(.horizontal, OutboundSpacing.screen)
                ScrollView {
                    VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                        content
                    }
                    .padding(OutboundSpacing.screen)
                }
                footer
                    .padding(OutboundSpacing.screen)
            }
            .background(OutboundPalette.background)
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step != .goal {
                        Button(String(localized: "onboarding.action.back", defaultValue: "Back"), systemImage: "chevron.left") { step = step.previous }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            promptedForMissingDisplayName = !validDisplayName
            promptedForMissingEmail = !validEmail
            displayName = validDisplayName ? (authStore.user?.displayName ?? "") : ""
            username = authStore.user?.username == "runner" ? "" : (authStore.user?.username ?? "")
            email = validEmail ? (authStore.user?.email ?? "") : ""
            trackIdentityPromptIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        if shouldShowIdentityPrompt {
            identityContent
        } else {
        switch step {
        case .goal:
            heading("What are you working toward?", "Your companion will turn this into a realistic first week.")
            choices(Goal.allCases, selection: $goal)
        case .baseline:
            heading("What does running look like lately?", "A starting estimate is enough. Your runs will make it more accurate.")
            Text(String(localized: "onboarding.baseline.recent_frequency", defaultValue: "RECENT FREQUENCY")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            choices(Frequency.allCases, selection: $frequency)
            Stepper(String(localized: "Comfortable run · \(comfortableMinutes) min"), value: $comfortableMinutes, in: 10...90, step: 5)
                .padding().background(.background, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
        case .week:
            heading("What can most weeks support?", "Choose what feels realistic, not ideal.")
            Stepper(String(localized: "\(runsPerWeek) runs per week"), value: $runsPerWeek, in: 2...6)
                .padding().background(.background, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
            Stepper(String(localized: "About \(availableMinutes) min on weekdays"), value: $availableMinutes, in: 15...90, step: 5)
                .padding().background(.background, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
        case .understanding:
            heading("Here’s what I understand", "Correct anything by going back. Plainstride will keep learning after setup.")
            summaryRow("Goal", goal.title)
            summaryRow("Starting point", localizedStartingPoint)
            summaryRow("Realistic week", localizedWeekSummary)
            AIExplanationView(text: String(localized: "Your first runs will tune effort, endurance, and recovery. These are starting estimates, not judgments."))
        case .calibration:
            heading("We’ll learn as you run", "No all-out test is required. These are normal training runs.")
            calibrationRow(1, "Comfortable run", "Learn your natural easy effort")
            calibrationRow(2, "Easy + pickups", "Observe controlled faster running")
            calibrationRow(3, "Longer relaxed run", "Learn endurance and recovery")
            AIExplanationView(text: String(localized: "After each run, one optional tap tells Plainstride what the numbers alone cannot."))
        case .health:
            healthContent
        }
        }
    }

    private var footer: some View {
        OutboundPrimaryButton(
            title: shouldShowIdentityPrompt
                ? (isSavingIdentity ? String(localized: "onboarding.identity.saving", defaultValue: "Saving…") : String(localized: "onboarding.identity.continue", defaultValue: "Continue"))
                : footerTitle,
            systemImage: step == .health ? "heart.fill" : "arrow.right"
        ) {
            if shouldShowIdentityPrompt {
                Task { await saveIdentity() }
            } else if step == .health {
                Task { await connectHealth() }
            } else { step = step.next }
        }
        .disabled((shouldShowIdentityPrompt && (!identityFormIsValid || isSavingIdentity)) || isImportingHealth || isCompleting)
    }

    private var footerTitle: String {
        if step == .health {
            if isImportingHealth { return String(localized: "onboarding.health.connecting", defaultValue: "Connecting…") }
            if healthImportSummary != nil { return String(localized: "onboarding.health.finish", defaultValue: "Build my first week") }
            return String(localized: "onboarding.health.connect", defaultValue: "Connect Apple Health")
        }
        return String(localized: "onboarding.action.continue", defaultValue: "Continue")
    }

    private var healthContent: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
            heading(
                "onboarding.health.title",
                "onboarding.health.subtitle"
            )
            Label(String(localized: "onboarding.health.workouts", defaultValue: "Recent workouts help set a realistic starting load."), systemImage: "figure.run")
            Label(String(localized: "onboarding.health.body", defaultValue: "Height, weight, birthday, and biological sex improve private training estimates."), systemImage: "person.text.rectangle")
            Label(String(localized: "onboarding.health.private", defaultValue: "Your health details stay private and are never shared in Together."), systemImage: "lock.shield")

            if let healthImportSummary {
                AIExplanationView(text: healthImportSummary)
            }
            if let healthImportError {
                Text(healthImportError).font(.footnote).foregroundStyle(.red)
            }
            if healthImportSummary == nil {
                Button(String(localized: "onboarding.health.not_now", defaultValue: "Not now")) { complete() }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.bordered)
            }
        }
    }

    private var identityContent: some View {
        VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
            heading(
                "onboarding.identity.heading",
                "onboarding.identity.subtitle"
            )
            TextField(String(localized: "onboarding.identity.display_name", defaultValue: "Display name"), text: $displayName)
                .textContentType(.name)
                .textFieldStyle(.roundedBorder)
            TextField(String(localized: "onboarding.identity.username", defaultValue: "Username"), text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            if !validEmail {
                TextField(String(localized: "onboarding.identity.email", defaultValue: "Email"), text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
            }
            Text(String(localized: "onboarding.identity.username_help", defaultValue: "Use 3–30 letters, numbers, underscores, or hyphens."))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let identityError {
                Text(identityError).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var validDisplayName: Bool {
        guard let value = authStore.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !value.isEmpty && value.caseInsensitiveCompare("Runner") != .orderedSame
    }

    private var validEmail: Bool { Self.isValidEmail(authStore.user?.email ?? "") }
    private var shouldShowIdentityPrompt: Bool { !identityCompleted && (!validDisplayName || !validEmail) }
    private var progressCount: Int { Step.allCases.count + (shouldShowIdentityPrompt ? 1 : 0) }
    private var progressIndex: Int { shouldShowIdentityPrompt ? 1 : step.rawValue + 1 + ((!validDisplayName || !validEmail) ? 1 : 0) }
    private var cleanedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private var identityFormIsValid: Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let nameIsValid = !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let usernameIsValid = (3...30).contains(cleanedUsername.count) && cleanedUsername.unicodeScalars.allSatisfy(allowed.contains)
        return nameIsValid && usernameIsValid && (validEmail || Self.isValidEmail(email))
    }

    private func saveIdentity() async {
        guard identityFormIsValid else { return }
        isSavingIdentity = true
        identityError = nil
        defer { isSavingIdentity = false }
        do {
            let profile = try await APIClient.shared.updateMyProfile(.init(
                username: cleanedUsername,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                bio: nil,
                contactEmail: validEmail ? nil : email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                contactPhone: nil
            ))
            authStore.applyProfileIdentity(username: profile.username, displayName: profile.displayName)
            identityCompleted = true
            if let analyticsManager {
                await analyticsManager.track(.init(.onboardingIdentityCompleted, properties: identityAnalyticsProperties))
            }
        } catch {
            identityError = String(localized: "onboarding.identity.error", defaultValue: "That username may already be taken. Try another one.")
        }
    }

    private func trackIdentityPromptIfNeeded() {
        guard shouldShowIdentityPrompt, !identityPromptTracked else { return }
        identityPromptTracked = true
        guard let analyticsManager else { return }
        Task { await analyticsManager.track(.init(.onboardingIdentityPromptViewed, properties: identityAnalyticsProperties)) }
    }

    private var identityAnalyticsProperties: [ProductPropertyKey: AnalyticsValue] {
        [.missingDisplayName: .boolean(promptedForMissingDisplayName), .missingEmail: .boolean(promptedForMissingEmail)]
    }

    private static func isValidEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
    }

    private func complete() {
        guard !isCompleting else { return }
        isCompleting = true
        onboardingStore.updateGoalText(goal.intakeText)
        onboardingStore.updateBaselineText(localizedBaselineText)
        onboardingStore.updateScheduleText(localizedScheduleText)
        onboardingStore.selectEffortPreference(.balanced)
        let profile = onboardingStore.complete()
        Task {
            await personalizationStore.completeProfile(
                RunnerProfileRequestDTO(
                    goalSummary: goal.title,
                    scheduleSummary: localizedScheduleSummary,
                    comfortableDurationMinutes: comfortableMinutes,
                    recentSessionsPerWeek: frequency.sessions,
                    targetSessionsPerWeek: runsPerWeek,
                    preferredLongRunDay: "Saturday",
                    guidanceDetail: "balanced",
                    constraints: [:],
                    complete: true
                )
            )
            if let recommendation = trainingPlanStore.planOptions.first {
                trainingPlanStore.acceptRecommendation(recommendation)
            }
            onComplete(profile)
        }
    }

    private func connectHealth() async {
        if healthImportSummary != nil {
            complete()
            return
        }
        isImportingHealth = true
        healthImportError = nil
        await trackHealth(.healthConnectionRequested)
        await healthAuthorizationStore.requestAuthorization()

        guard healthAuthorizationStore.lastErrorMessage == nil else {
            healthImportError = String(localized: "onboarding.health.error", defaultValue: "Apple Health could not be connected. You can try again or continue without it.")
            isImportingHealth = false
            await trackHealth(.healthConnectionCompleted, result: "failed")
            return
        }

        do {
            let since = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: Date()) ?? .distantPast
            let data = try await healthImportStore.personalizationData(since: since)
            applyHealthData(data)
            healthImportSummary = String(
                format: String(localized: "onboarding.health.imported.format", defaultValue: "Connected. Plainstride found %d recent running workouts and will use available profile details."),
                locale: .autoupdatingCurrent,
                data.recentWorkouts.filter(\.isRunning).count
            )
            await persistTrainingProfile(data)
            await trackHealth(.healthConnectionCompleted, result: "connected")
        } catch {
            healthImportError = String(localized: "onboarding.health.error", defaultValue: "Apple Health could not be connected. You can try again or continue without it.")
            await trackHealth(.healthConnectionCompleted, result: "failed")
        }
        isImportingHealth = false
    }

    private func applyHealthData(_ data: HealthPersonalizationData) {
        onboardingStore.applyHealthProfile(data)
        let runs = data.recentWorkouts.filter(\.isRunning)
        guard !runs.isEmpty else { return }
        let weeklyAverage = Double(runs.count) / 8.0
        frequency = weeklyAverage >= 2.5 ? .threePlus : weeklyAverage >= 1.5 ? .oneOrTwo : .occasional
        let sortedDurations = runs.map { $0.durationSeconds / 60 }.sorted()
        comfortableMinutes = min(90, max(10, sortedDurations[sortedDurations.count / 2] / 5 * 5))
    }

    private func persistTrainingProfile(_ data: HealthPersonalizationData) async {
        let sex: TrainingProfileSex? = switch data.biologicalSex {
        case .female: .female
        case .male: .male
        case .notSpecified: nil
        }
        let birthDate = data.dateOfBirth.map { Self.birthDateFormatter.string(from: $0) }
        guard sex != nil || birthDate != nil || data.heightCentimeters != nil || data.weightKilograms != nil else { return }
        _ = try? await APIClient.shared.updateTrainingProfile(.init(
            sexAtBirth: sex,
            birthDate: birthDate,
            heightCentimeters: data.heightCentimeters,
            weightKilograms: data.weightKilograms
        ))
    }

    private func trackHealth(_ name: ProductEventName, result: String? = nil) async {
        guard let analyticsManager else { return }
        let properties: [ProductPropertyKey: AnalyticsValue] = result.map { [.result: .string($0)] } ?? [:]
        await analyticsManager.track(.init(name, properties: properties))
    }

    private static let birthDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func heading(_ title: LocalizedStringResource, _ subtitle: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).foregroundStyle(.secondary)
        }
    }

    private func choices<T: Identifiable & Hashable & Titled>(_ values: [T], selection: Binding<T>) -> some View {
        VStack(spacing: OutboundSpacing.compact) {
            ForEach(values) { value in
                Button { selection.wrappedValue = value } label: {
                    HStack { Text(value.title); Spacer(); Image(systemName: selection.wrappedValue == value ? "checkmark.circle.fill" : "circle") }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(selection.wrappedValue == value ? OutboundPalette.companion : .secondary)
            }
        }
    }

    private func summaryRow(_ label: LocalizedStringResource, _ value: String) -> some View {
        OutboundCard { VStack(alignment: .leading, spacing: 4) { Text(label).textCase(.uppercase).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Text(value).font(.headline) } }
    }

    private func calibrationRow(_ number: Int, _ title: LocalizedStringResource, _ detail: LocalizedStringResource) -> some View {
        HStack(spacing: OutboundSpacing.standard) {
            Text("\(number)").font(.headline).frame(width: 34, height: 34).background(OutboundPalette.companion.opacity(0.14), in: Circle())
            VStack(alignment: .leading) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding().background(.background, in: RoundedRectangle(cornerRadius: OutboundRadius.control))
    }

    private var localizedBaselineText: String {
        switch AppLanguage.current {
        case .english: "I run \(frequency.intakeText) and feel comfortable for about \(comfortableMinutes) minutes."
        case .spanish: "Corro \(frequency.intakeText) y me siento cómodo durante unos \(comfortableMinutes) minutos."
        case .simplifiedChinese: "我\(frequency.intakeText)，舒适跑时长约为 \(comfortableMinutes) 分钟。"
        }
    }

    private var localizedStartingPoint: String {
        switch AppLanguage.current {
        case .english: "\(frequency.title) · \(comfortableMinutes) min comfortable"
        case .spanish: "\(frequency.title) · \(comfortableMinutes) min con comodidad"
        case .simplifiedChinese: "\(frequency.title) · 舒适跑 \(comfortableMinutes) 分钟"
        }
    }

    private var localizedWeekSummary: String {
        switch AppLanguage.current {
        case .english: "\(runsPerWeek) runs · about \(availableMinutes) min"
        case .spanish: "\(runsPerWeek) carreras · unos \(availableMinutes) min"
        case .simplifiedChinese: "\(runsPerWeek) 次跑步 · 约 \(availableMinutes) 分钟"
        }
    }

    private var localizedScheduleText: String {
        switch AppLanguage.current {
        case .english: "I can run \(runsPerWeek) times per week for about \(availableMinutes) minutes, with a longer run on Saturday."
        case .spanish: "Puedo correr \(runsPerWeek) veces por semana durante unos \(availableMinutes) minutos, con una carrera más larga el sábado."
        case .simplifiedChinese: "我每周可以跑 \(runsPerWeek) 次，每次约 \(availableMinutes) 分钟，周六可以安排一次更长的跑步。"
        }
    }

    private var localizedScheduleSummary: String {
        switch AppLanguage.current {
        case .english: "\(runsPerWeek) runs per week, Saturday longer"
        case .spanish: "\(runsPerWeek) carreras por semana, más larga el sábado"
        case .simplifiedChinese: "每周 \(runsPerWeek) 次，周六长跑"
        }
    }
}

private protocol Titled { var title: String { get } }

private extension SimplifiedOnboardingFlow {
    enum Step: Int, CaseIterable {
        case goal, baseline, week, understanding, calibration, health
        var title: String { "\(rawValue + 1) of \(Self.allCases.count)" }
        var next: Self { Self(rawValue: rawValue + 1) ?? self }
        var previous: Self { Self(rawValue: rawValue - 1) ?? self }
    }

    enum Goal: String, CaseIterable, Identifiable, Titled {
        case consistency, start, comeback, race, faster
        var id: Self { self }
        var title: String {
            switch self {
            case .consistency: String(localized: "Run consistently")
            case .start: String(localized: "Start running")
            case .comeback: String(localized: "Return after a break")
            case .race: String(localized: "Train for a race")
            case .faster: String(localized: "Run faster")
            }
        }
        var intakeText: String {
            switch AppLanguage.current {
            case .english: "My running goal is to \(title.lowercased()) in a realistic, sustainable way."
            case .spanish: "Mi objetivo de carrera es \(title.lowercased()) de una forma realista y sostenible."
            case .simplifiedChinese: "我的跑步目标是以现实且可持续的方式做到：\(title)。"
            }
        }
    }

    enum Frequency: String, CaseIterable, Identifiable, Titled {
        case none, occasional, oneOrTwo, threePlus
        var id: Self { self }
        var title: String {
            switch self {
            case .none: String(localized: "Not running yet")
            case .occasional: String(localized: "Occasionally")
            case .oneOrTwo: String(localized: "1–2 times a week")
            case .threePlus: String(localized: "3+ times a week")
            }
        }
        var sessions: Int { switch self { case .none: 0; case .occasional: 1; case .oneOrTwo: 2; case .threePlus: 3 } }
        var intakeText: String { title.lowercased() }
    }
}
