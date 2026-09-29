import SwiftUI
import Combine
import AVFoundation

nonisolated enum PostWorkoutStretchEligibility {
    static func isEligible(_ type: ActivityType) -> Bool { [.running, .cycling, .hiking, .swimming].contains(type) }
}

private func stretchText(_ key: String, _ defaultValue: String) -> String {
    NSLocalizedString(key, comment: defaultValue)
}

struct StretchMovement: Identifiable, Sendable {
    let id: String
    let title: String
    let instruction: String
    let side: String?
    let duration: Int
    let icon: String
}

struct StretchRoutine: Sendable, Identifiable {
    let id: String
    let title: String
    let durationLabel: String
    let movements: [StretchMovement]
}

struct PostSavedStretchContext {
    let activityType: ActivityType
    let routines: [StretchRoutine]
}

enum PostWorkoutStretchCatalog {
    static func routines(for type: ActivityType) -> [StretchRoutine]? {
        guard PostWorkoutStretchEligibility.isEligible(type) else { return nil }
        let prefix = type.rawValue
        let cooldown = bilateralSteps(prefix: prefix, id: "glute", titleKey: "glute", instructionKey: "glute", seconds: 30, icon: "figure.flexibility")
            + bilateralSteps(prefix: prefix, id: "hamstring", titleKey: "hamstring", instructionKey: "hamstring", seconds: 30, icon: "figure.flexibility")
            + [singleStep(prefix: prefix, id: "inner_thigh", titleKey: "inner_thigh", instructionKey: "inner_thigh", side: "both", seconds: 30, icon: "figure.flexibility")]
            + bilateralSteps(prefix: prefix, id: "calf", titleKey: "calf", instructionKey: "calf", seconds: 30, icon: "figure.walk")
            + bilateralSteps(prefix: prefix, id: "quad", titleKey: "quad", instructionKey: "quad", seconds: 30, icon: "figure.stand")
        let hipsAndHamstrings = bilateralSteps(prefix: prefix, id: "hip_flexor", titleKey: "hip_flexor", instructionKey: "hip_flexor", seconds: 20, icon: "figure.flexibility")
            + bilateralSteps(prefix: prefix, id: "hamstring", titleKey: "hamstring", instructionKey: "hamstring", seconds: 20, icon: "figure.flexibility")
            + bilateralSteps(prefix: prefix, id: "glute", titleKey: "glute", instructionKey: "glute", seconds: 20, icon: "figure.flexibility")

        return [
            StretchRoutine(
                id: "post_save_\(prefix)_cooldown_v2",
                title: stretchText("activity.post_save.program.full_body", "Full-body cooldown"),
                durationLabel: stretchText("activity.post_save.program.full_body.duration", "About 5 min"),
                movements: cooldown
            ),
            StretchRoutine(
                id: "post_save_\(prefix)_hips_hamstrings_v2",
                title: stretchText("activity.post_save.program.hips_hamstrings", "Hips & hamstrings"),
                durationLabel: stretchText("activity.post_save.program.hips_hamstrings.duration", "About 2½ min"),
                movements: hipsAndHamstrings
            )
        ]
    }

    private static func bilateralSteps(
        prefix: String,
        id: String,
        titleKey: String,
        instructionKey: String,
        seconds: Int,
        icon: String
    ) -> [StretchMovement] {
        ["left", "right"].map { side in
            singleStep(prefix: prefix, id: id, titleKey: titleKey, instructionKey: instructionKey, side: side, seconds: seconds, icon: icon)
        }
    }

    private static func singleStep(
        prefix: String,
        id: String,
        titleKey: String,
        instructionKey: String,
        side: String,
        seconds: Int,
        icon: String
    ) -> StretchMovement {
        let sideKey = "post_workout_stretch.side.\(side)"
        return StretchMovement(
            id: "\(prefix)_\(id)_\(side)",
            title: stretchText("post_workout_stretch.movement.\(titleKey)", titleKey.capitalized),
            instruction: stretchText("post_workout_stretch.instruction.\(instructionKey)", "Move gently within your comfort."),
            side: stretchText(sideKey, "Side"),
            duration: seconds,
            icon: icon
        )
    }
}

@MainActor final class PostWorkoutStretchTimer: ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing
        case holding
        case transitioning
    }

    static let preparationDuration = 3
    static let transitionDuration = 5

    @Published var index = 0
    @Published var remaining = 0
    @Published var running = false
    @Published var complete = false
    @Published var phase: Phase = .idle
    private(set) var routine: StretchRoutine
    private var task: Task<Void, Never>?

    init(routine: StretchRoutine) {
        self.routine = routine
    }

    var movement: StretchMovement { routine.movements[index] }
    func start() {
        guard !complete, !running else { return }
        if phase == .idle {
            phase = .preparing
            remaining = Self.preparationDuration
        }
        running = true
        task?.cancel()
        task = Task { @MainActor in
            while running && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard running, !Task.isCancelled else { return }
                if remaining > 1 {
                    remaining -= 1
                } else {
                    advanceInterval()
                }
            }
        }
    }
    func pause() { running = false; task?.cancel() }

    func select(_ routine: StretchRoutine) {
        guard !running, phase == .idle else { return }
        self.routine = routine
        index = 0
        remaining = 0
        complete = false
    }

    func startMovementNow() {
        guard phase == .preparing || phase == .transitioning else { return }
        phase = .holding
        remaining = movement.duration
    }

    func next() {
        if phase == .preparing || phase == .transitioning {
            startMovementNow()
        } else if phase == .holding {
            beginNextMovement()
        }
    }

    private func advanceInterval() {
        switch phase {
        case .preparing, .transitioning:
            phase = .holding
            remaining = movement.duration
        case .holding:
            beginNextMovement()
        case .idle:
            pause()
        }
    }

    private func beginNextMovement() {
        guard index < routine.movements.count - 1 else {
            complete = true
            pause()
            return
        }
        index += 1
        phase = .transitioning
        remaining = Self.transitionDuration
    }

    func leave() { pause() }
}

struct PostWorkoutStretchView: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.analyticsManager) private var analytics
    @StateObject private var timer: PostWorkoutStretchTimer
    @State private var narrator = StretchNarrator()
    let context: PostSavedStretchContext
    let activity: SavedActivity
    let onExit: () -> Void
    @State private var chosen = false
    @State private var confirmEnd = false
    @State private var completedTracked = false
    @State private var speaksInstructions = true

    init(context: PostSavedStretchContext, activity: SavedActivity, onExit: @escaping () -> Void) {
        self.context = context
        self.activity = activity
        self.onExit = onExit
        _timer = StateObject(wrappedValue: PostWorkoutStretchTimer(routine: context.routines[0]))
    }

    var body: some View {
        Group {
            if !chosen {
                ScrollView {
                    VStack(spacing: 16) {
                        PostSaveCelebrationCard(activity: activity)
                            .id(activity.id)
                            .frame(height: 205)

                        Text(String(localized: "activity.post_save.message", defaultValue: "You made time for this today."))
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)

                        Text(stretchText("post_workout_stretch.offer_title", "A gentle reset?"))
                            .font(.title2.bold())
                            .padding(.top, 4)
                        Text(stretchText("post_workout_stretch.offer_body", "Take a few minutes for an optional, easy stretch routine."))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(String(localized: "activity.post_save.program.title", defaultValue: "Choose a stretch"))
                                .font(.headline)
                            ForEach(context.routines) { routine in
                                stretchProgramOption(routine)
                            }
                        }

                        Toggle(stretchText("post_workout_stretch.voice_over", "Speak instructions aloud"), isOn: $speaksInstructions)
                            .fixedSize(horizontal: false, vertical: true)

                        Button(stretchText("post_workout_stretch.start", "Start stretching")) {
                            chosen = true
                            track(.postWorkoutStretchStarted)
                            timer.start()
                            speakCurrentMovement()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity, minHeight: 52)

                        Button(stretchText("post_workout_stretch.done", "Done")) { finish("not_started") }
                            .frame(minHeight: 48)

                        Text(stretchText("post_workout_stretch.disclaimer", "General wellness guidance. Stop if you feel pain, dizziness, or unusual discomfort."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 480)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            } else if timer.complete {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
                    Text(stretchText("post_workout_stretch.complete", "Stretch complete")).font(.title.bold())
                    Button(stretchText("post_workout_stretch.done", "Done")) { finish(nil) }.buttonStyle(.borderedProminent).frame(minHeight: 52)
                    Spacer()
                }
            } else {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: timer.movement.icon).font(.system(size: 60)).foregroundStyle(.orange)
                    if timer.phase == .preparing {
                        Text(stretchText("post_workout_stretch.get_ready", "Get ready")).font(.headline).foregroundStyle(.secondary)
                    } else if timer.phase == .transitioning {
                        Text(stretchText("post_workout_stretch.transition", "Transition")).font(.headline).foregroundStyle(.secondary)
                    }
                    Text(timer.movement.title).font(.title.bold())
                    if let side = timer.movement.side { Text(side).foregroundStyle(.orange) }
                    Text(timer.movement.instruction).multilineTextAlignment(.center)
                    Text(timer.remaining.formatted()).font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                    let movementProgress = timer.phase == .holding
                        ? 1 - Double(timer.remaining) / Double(max(timer.movement.duration, 1))
                        : 0
                    ProgressView(value: Double(timer.index) + movementProgress, total: Double(timer.routine.movements.count))
                    Text(stretchText("post_workout_stretch.safety", "Move only into gentle tension. Stop if you feel pain.")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack {
                        Button(timer.running ? stretchText("post_workout_stretch.pause", "Pause") : stretchText("post_workout_stretch.resume", "Resume")) { toggleTimer() }.buttonStyle(.borderedProminent)
                        if timer.phase == .preparing || timer.phase == .transitioning {
                            Button(stretchText("post_workout_stretch.start_now", "Start now")) { timer.startMovementNow() }.buttonStyle(.bordered)
                        } else if timer.index < timer.routine.movements.count - 1 {
                            Button(stretchText("post_workout_stretch.next", "Next")) { timer.next() }.buttonStyle(.bordered)
                        }
                    }
                    Button(stretchText("post_workout_stretch.end", "End")) { timer.running ? (confirmEnd = true) : finish("ended_early") }.frame(minHeight: 48)
                    Spacer()
                }
            }
        }
        .safeAreaPadding(.vertical)
        .background(Color(.systemBackground))
        .onAppear { track(.postWorkoutStretchOffered) }
        .onChange(of: phase) { _, value in
            if value != .active {
                timer.pause()
                narrator.stop()
            }
        }
        .onChange(of: timer.index) { _, _ in
            if chosen && timer.running { speakCurrentMovement(announceRelease: true) }
        }
        .onChange(of: speaksInstructions) { _, enabled in
            if !enabled { narrator.stop() }
        }
        .onChange(of: timer.complete) { _, done in
            if done {
                narrator.speak(stretchText("post_workout_stretch.release", "Release"), locale: AppLanguage.speechLocale)
                if !completedTracked {
                    completedTracked = true
                    track(.postWorkoutStretchCompleted)
                }
            }
        }
        .onDisappear { timer.leave(); narrator.stop(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: timer.running) { _, running in UIApplication.shared.isIdleTimerDisabled = running }
        .alert(stretchText("post_workout_stretch.end_title", "End stretching?"), isPresented: $confirmEnd) {
            Button(stretchText("post_workout_stretch.end_confirm", "End"), role: .destructive) { finish("ended_early") }
            Button(stretchText("post_workout_stretch.cancel", "Cancel"), role: .cancel) {}
        } message: { Text(stretchText("post_workout_stretch.end_message", "You can stop whenever you want.")) }
    }

    private func finish(_ result: String?) {
        timer.leave()
        narrator.stop()
        if let result { track(.postWorkoutStretchDismissed, result: result) }
        onExit()
    }

    @ViewBuilder
    private func stretchProgramOption(_ routine: StretchRoutine) -> some View {
        let isSelected = timer.routine.id == routine.id
        Button {
            guard !isSelected else { return }
            timer.select(routine)
            track(.postWorkoutStretchProgramSelected, routineID: routine.id)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.title).font(.subheadline.weight(.semibold))
                    Text(routine.durationLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.orange : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.orange.opacity(0.10) : Color(.secondarySystemBackground))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.orange : Color.clear, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("StretchProgramOption-\(routine.id)")
    }

    private func toggleTimer() {
        if timer.running {
            timer.pause()
            narrator.stop()
        } else {
            timer.start()
            speakCurrentMovement(announceRelease: timer.phase == .transitioning)
        }
    }

    private func speakCurrentMovement(announceRelease: Bool = false) {
        guard speaksInstructions, phase == .active else { return }
        let movement = timer.movement
        var spokenParts = [String]()
        if announceRelease {
            spokenParts.append(stretchText("post_workout_stretch.release", "Release"))
        }
        spokenParts.append(contentsOf: [movement.title, movement.side, movement.instruction].compactMap { $0 })
        let spokenText = spokenParts
            .joined(separator: ". ")
        narrator.speak(spokenText, locale: AppLanguage.speechLocale)
    }

    private func track(_ event: ProductEventName, result: String? = nil, routineID: String? = nil) {
        var properties: [ProductPropertyKey: AnalyticsValue] = [
            .activityType: .string(context.activityType.rawValue),
            .routineID: .string(routineID ?? timer.routine.id)
        ]
        if let result { properties[.result] = .string(result) }
        Task { await analytics?.track(.init(event, properties: properties)) }
    }
}

@MainActor
private final class StretchNarrator {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, locale: Locale) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: locale.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
