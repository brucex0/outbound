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

struct StretchRoutine: Sendable {
    let id: String
    let movements: [StretchMovement]
}

struct PostSavedStretchContext {
    let activityType: ActivityType
    let routine: StretchRoutine
}

enum PostWorkoutStretchCatalog {
    static func routine(for type: ActivityType) -> StretchRoutine? {
        guard PostWorkoutStretchEligibility.isEligible(type) else { return nil }
        let prefix = type.rawValue
        let base = [
            ("calf", "post_workout_stretch.movement.calf", "post_workout_stretch.instruction.calf", "post_workout_stretch.side.left", "figure.walk"),
            ("quad", "post_workout_stretch.movement.quad", "post_workout_stretch.instruction.quad", "post_workout_stretch.side.right", "figure.stand"),
            ("hip", "post_workout_stretch.movement.hip", "post_workout_stretch.instruction.hip", "post_workout_stretch.side.left", "figure.flexibility"),
            ("shoulder", "post_workout_stretch.movement.shoulder", "post_workout_stretch.instruction.shoulder", nil, "figure.arms.open")
        ]
        return StretchRoutine(
            id: "post_save_\(prefix)_v1",
            movements: base.map { id, titleKey, instructionKey, sideKey, icon in
                StretchMovement(
                    id: "\(prefix)_\(id)",
                    title: stretchText(titleKey, id.capitalized),
                    instruction: stretchText(instructionKey, "Move gently within your comfort.") ,
                    side: sideKey.map { stretchText($0, "Side") },
                    duration: 60,
                    icon: icon
                )
            }
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
    let routine: StretchRoutine
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
    let onExit: () -> Void
    @State private var chosen = false
    @State private var confirmEnd = false
    @State private var completedTracked = false
    @State private var speaksInstructions = true

    init(context: PostSavedStretchContext, onExit: @escaping () -> Void) {
        self.context = context
        self.onExit = onExit
        _timer = StateObject(wrappedValue: PostWorkoutStretchTimer(routine: context.routine))
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(stretchText("post_workout_stretch.activity_saved", "Activity saved")).font(.title2.bold())
                Spacer()
            }
            if !chosen {
                Spacer()
                Text(stretchText("post_workout_stretch.offer_title", "A gentle reset?")).font(.title.bold())
                Text(stretchText("post_workout_stretch.offer_body", "Take a few minutes for an optional, easy stretch routine.")).multilineTextAlignment(.center)
                Toggle(stretchText("post_workout_stretch.voice_over", "Speak instructions aloud"), isOn: $speaksInstructions)
                    .fixedSize(horizontal: false, vertical: true)
                Button(stretchText("post_workout_stretch.start", "Start stretching")) {
                    chosen = true
                    track(.postWorkoutStretchStarted)
                    timer.start()
                    speakCurrentMovement()
                }.buttonStyle(.borderedProminent).frame(minHeight: 52)
                Button(stretchText("post_workout_stretch.done", "Done")) { finish("not_started") }.frame(minHeight: 48)
                Text(stretchText("post_workout_stretch.disclaimer", "General wellness guidance. Stop if you feel pain, dizziness, or unusual discomfort.")).font(.footnote).foregroundStyle(.secondary)
                Spacer()
            } else if timer.complete {
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
                Text(stretchText("post_workout_stretch.complete", "Stretch complete")).font(.title.bold())
                Button(stretchText("post_workout_stretch.done", "Done")) { finish(nil) }.buttonStyle(.borderedProminent).frame(minHeight: 52)
                Spacer()
            } else {
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
        .padding(24)
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

    private func track(_ event: ProductEventName, result: String? = nil) {
        var properties: [ProductPropertyKey: AnalyticsValue] = [.activityType: .string(context.activityType.rawValue), .routineID: .string(context.routine.id)]
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
