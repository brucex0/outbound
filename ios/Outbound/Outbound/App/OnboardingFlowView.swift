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
        case .intent:
            intentStep
        case .context:
            contextStep
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
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                Text("Outbound")
                    .font(.largeTitle.bold())
                Text("Start with one small win, then let your coach shape the next move.")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                onboardingPromiseRow(
                    systemImage: "sparkles",
                    title: "Personal setup",
                    detail: "A short path based on why you are here."
                )
                onboardingPromiseRow(
                    systemImage: "play.circle.fill",
                    title: "Real first action",
                    detail: "A suggested session you can start right away."
                )
                onboardingPromiseRow(
                    systemImage: "checkmark.seal.fill",
                    title: "Momentum saved",
                    detail: "Your choices stay local and tune the first day."
                )
            }
        }
    }

    private var intentStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            stepTitle(
                "What should Outbound help with first?",
                subtitle: "Pick the reason that would make today feel useful."
            )

            VStack(spacing: 12) {
                ForEach(OnboardingIntent.allCases) { intent in
                    OnboardingOptionButton(
                        title: intent.title,
                        detail: intent.detail,
                        systemImage: intent.systemImage,
                        isSelected: onboardingStore.draft.intent == intent,
                        accentColor: accentColor
                    ) {
                        onboardingStore.selectIntent(intent)
                    }
                }
            }
        }
    }

    private var contextStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            stepTitle(
                "Make the first session fit.",
                subtitle: "A tiny bit of context is enough."
            )

            choiceSection(title: "First sport") {
                LazyVGrid(columns: optionColumns, spacing: 10) {
                    ForEach([SportType.run, SportType.bike]) { sport in
                        CompactChoiceButton(
                            title: sport.displayName,
                            detail: sport.onboardingDetail,
                            systemImage: sport.systemImage,
                            isSelected: onboardingStore.draft.sport == sport,
                            accentColor: accentColor
                        ) {
                            onboardingStore.selectSport(sport)
                        }
                    }
                }
            }

            choiceSection(title: "Starting point") {
                LazyVGrid(columns: optionColumns, spacing: 10) {
                    ForEach(OnboardingExperience.allCases) { experience in
                        CompactChoiceButton(
                            title: experience.title,
                            detail: experience.detail,
                            systemImage: experience.systemImage,
                            isSelected: onboardingStore.draft.experience == experience,
                            accentColor: accentColor
                        ) {
                            onboardingStore.selectExperience(experience)
                        }
                    }
                }
            }

            choiceSection(title: "Today") {
                LazyVGrid(columns: optionColumns, spacing: 10) {
                    ForEach(OnboardingSessionLength.allCases) { length in
                        CompactChoiceButton(
                            title: length.title,
                            detail: length.detail,
                            systemImage: "timer",
                            isSelected: onboardingStore.draft.sessionLength == length,
                            accentColor: accentColor
                        ) {
                            onboardingStore.selectSessionLength(length)
                        }
                    }
                }
            }

            choiceSection(title: "Weekly rhythm") {
                LazyVGrid(columns: optionColumns, spacing: 10) {
                    ForEach(OnboardingWeeklyRhythm.allCases) { rhythm in
                        CompactChoiceButton(
                            title: rhythm.title,
                            detail: "Starting target",
                            systemImage: "calendar",
                            isSelected: onboardingStore.draft.weeklyRhythm == rhythm,
                            accentColor: accentColor
                        ) {
                            onboardingStore.selectWeeklyRhythm(rhythm)
                        }
                    }
                }
            }
        }
    }

    private var setupStep: some View {
        let profile = onboardingStore.previewProfile
        let session = profile.suggestedSession

        return VStack(alignment: .leading, spacing: 20) {
            stepTitle(
                "Your first win is ready.",
                subtitle: "Start small enough that finishing feels clean."
            )

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: session.sport.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .frame(width: 42, height: 42)
                        .background(accentColor.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.title)
                            .font(.title3.bold())
                        Text(session.framing)
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
                Button("Go to Me") {
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
        case .welcome: return "Set up my first win"
        case .intent, .context: return "Continue"
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
        [GridItem(.adaptive(minimum: 148), spacing: 10)]
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
}

private struct OnboardingOptionButton: View {
    let title: String
    let detail: String
    let systemImage: String
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isSelected ? accentColor : .secondary)
                    .frame(width: 34, height: 34)
                    .background((isSelected ? accentColor.opacity(0.12) : Color(.systemBackground)), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? accentColor : Color.secondary.opacity(0.45))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? accentColor : Color.clear, lineWidth: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
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

private extension OnboardingExperience {
    var systemImage: String {
        switch self {
        case .new: return "leaf.fill"
        case .returning: return "arrow.clockwise.heart"
        case .steady: return "flame.fill"
        }
    }
}

private extension SportType {
    var onboardingDetail: String {
        switch self {
        case .run: return "Run or walk-run"
        case .bike: return "Indoor or outdoor"
        }
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
