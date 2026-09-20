import SwiftUI
import Combine

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
    @Published var index = 0
    @Published var remaining = 60
    @Published var running = false
    @Published var complete = false
    let routine: StretchRoutine
    private var task: Task<Void, Never>?

    init(routine: StretchRoutine) {
        self.routine = routine
        remaining = routine.movements.first?.duration ?? 60
    }

    var movement: StretchMovement { routine.movements[index] }
    func toggle() { running ? pause() : start() }
    func start() {
        guard !complete else { return }
        running = true
        task?.cancel()
        task = Task { @MainActor in
            while running && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if remaining > 0 { remaining -= 1 } else { next() }
            }
        }
    }
    func pause() { running = false; task?.cancel() }
    func next() {
        if index == routine.movements.count - 1 { complete = true; pause() }
        else { index += 1; remaining = movement.duration }
    }
    func leave() { pause() }
}

struct PostWorkoutStretchView: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.analyticsManager) private var analytics
    @StateObject private var timer: PostWorkoutStretchTimer
    let context: PostSavedStretchContext
    let onExit: () -> Void
    @State private var chosen = false
    @State private var confirmEnd = false
    @State private var completedTracked = false

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
                Button(stretchText("post_workout_stretch.done", "Done")) { finish("not_started") }.frame(minHeight: 48)
            }
            if !chosen {
                Spacer()
                Text(stretchText("post_workout_stretch.offer_title", "A gentle reset?")).font(.title.bold())
                Text(stretchText("post_workout_stretch.offer_body", "Take a few minutes for an optional, easy stretch routine.")).multilineTextAlignment(.center)
                Button(stretchText("post_workout_stretch.start", "Start stretching")) { chosen = true; track(.postWorkoutStretchStarted); timer.start() }.buttonStyle(.borderedProminent).frame(minHeight: 52)
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
                Text(timer.movement.title).font(.title.bold())
                if let side = timer.movement.side { Text(side).foregroundStyle(.orange) }
                Text(timer.movement.instruction).multilineTextAlignment(.center)
                Text(timer.remaining.formatted()).font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit()
                ProgressView(value: Double(timer.index), total: Double(timer.routine.movements.count))
                Text(stretchText("post_workout_stretch.safety", "Move only into gentle tension. Stop if you feel pain.")).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Button(timer.running ? stretchText("post_workout_stretch.pause", "Pause") : stretchText("post_workout_stretch.resume", "Resume")) { timer.toggle() }.buttonStyle(.borderedProminent)
                    Button(timer.index == timer.routine.movements.count - 1 ? stretchText("post_workout_stretch.finish", "Finish") : stretchText("post_workout_stretch.next", "Next")) { timer.next() }.buttonStyle(.bordered)
                }
                Button(stretchText("post_workout_stretch.end", "End")) { timer.running ? (confirmEnd = true) : finish("ended_early") }.frame(minHeight: 48)
                Spacer()
            }
        }
        .padding(24)
        .safeAreaPadding(.vertical)
        .background(Color(.systemBackground))
        .onAppear { track(.postWorkoutStretchOffered) }
        .onChange(of: phase) { _, value in if value != .active { timer.pause() } }
        .onChange(of: timer.complete) { _, done in if done && !completedTracked { completedTracked = true; track(.postWorkoutStretchCompleted) } }
        .onDisappear { timer.leave(); UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: timer.running) { _, running in UIApplication.shared.isIdleTimerDisabled = running }
        .alert(stretchText("post_workout_stretch.end_title", "End stretching?"), isPresented: $confirmEnd) {
            Button(stretchText("post_workout_stretch.end_confirm", "End"), role: .destructive) { finish("ended_early") }
            Button(stretchText("post_workout_stretch.cancel", "Cancel"), role: .cancel) {}
        } message: { Text(stretchText("post_workout_stretch.end_message", "You can stop whenever you want.")) }
    }

    private func finish(_ result: String?) {
        timer.leave()
        if let result { track(.postWorkoutStretchDismissed, result: result) }
        onExit()
    }

    private func track(_ event: ProductEventName, result: String? = nil) {
        var properties: [ProductPropertyKey: AnalyticsValue] = [.activityType: .string(context.activityType.rawValue), .routineID: .string(context.routine.id)]
        if let result { properties[.result] = .string(result) }
        Task { await analytics?.track(.init(event, properties: properties)) }
    }
}
