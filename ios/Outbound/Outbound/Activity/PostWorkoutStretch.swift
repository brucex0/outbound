import SwiftUI
import Combine

nonisolated enum PostWorkoutStretchEligibility {
    static func isEligible(_ type: ActivityType) -> Bool { [.running, .cycling, .hiking, .swimming].contains(type) }
}
struct StretchMovement: Identifiable, Sendable { let id: String; let title: String; let instruction: String; let side: String?; let duration: Int; let icon: String }
struct StretchRoutine: Sendable { let id: String; let movements: [StretchMovement] }
struct PostSavedStretchContext { let activityType: ActivityType; let routine: StretchRoutine }
enum PostWorkoutStretchCatalog {
    static func routine(for type: ActivityType) -> StretchRoutine? {
        guard PostWorkoutStretchEligibility.isEligible(type) else { return nil }
        let prefix = type.rawValue
        let base = [("calf", "Calf release", "Stand supported and gently lean into the stretch.", "Left side", "figure.walk"), ("quad", "Standing quad stretch", "Hold a wall or chair and keep your knees close.", "Right side", "figure.stand"), ("hip", "Supported hip stretch", "Keep your chest easy and move only within comfort.", "Left side", "figure.flexibility"), ("shoulder", "Shoulder and upper-back reach", "Reach softly and let your breathing stay relaxed.", nil, "figure.arms.open")]
        return StretchRoutine(id: "post_save_\(prefix)_v1", movements: base.map { StretchMovement(id: "\(prefix)_\($0.0)", title: $0.1, instruction: $0.2, side: $0.3, duration: 60, icon: $0.4) })
    }
}
@MainActor final class PostWorkoutStretchTimer: ObservableObject {
    @Published var index = 0; @Published var remaining = 60; @Published var running = false; @Published var complete = false
    let routine: StretchRoutine; private var task: Task<Void, Never>?
    init(routine: StretchRoutine) { self.routine = routine; remaining = routine.movements.first?.duration ?? 60 }
    var movement: StretchMovement { routine.movements[index] }
    func toggle() { running ? pause() : start() }
    func start() { guard !complete else { return }; running = true; task?.cancel(); task = Task { @MainActor in while running && !Task.isCancelled { try? await Task.sleep(for: .seconds(1)); if remaining > 0 { remaining -= 1 } else { next() } } } }
    func pause() { running = false; task?.cancel() }
    func next() { if index == routine.movements.count - 1 { complete = true; pause() } else { index += 1; remaining = movement.duration } }
    func leave() { pause() }
}
struct PostWorkoutStretchView: View {
    @Environment(\.scenePhase) private var phase; @Environment(\.analyticsManager) private var analytics
    @StateObject private var timer: PostWorkoutStretchTimer; let context: PostSavedStretchContext; let onExit: () -> Void
    @State private var chosen = false; @State private var confirmEnd = false; @State private var completedTracked = false
    init(context: PostSavedStretchContext, onExit: @escaping () -> Void) { self.context = context; self.onExit = onExit; _timer = StateObject(wrappedValue: PostWorkoutStretchTimer(routine: context.routine)) }
    var body: some View { VStack(spacing: 20) { HStack { Text("Activity saved").font(.title2.bold()); Spacer(); Button("Done") { finish("not_started") }.frame(minHeight: 48) }; if !chosen { Spacer(); Text("A gentle reset?").font(.title.bold()); Text("Take a few minutes for an optional, easy stretch routine.").multilineTextAlignment(.center); Button("Start stretching") { chosen = true; track(.postWorkoutStretchStarted); timer.start() }.buttonStyle(.borderedProminent).frame(minHeight: 52); Button("Done") { finish("not_started") }.frame(minHeight: 48); Text("General wellness guidance. Stop if you feel pain, dizziness, or unusual discomfort.").font(.footnote).foregroundStyle(.secondary); Spacer() } else if timer.complete { Spacer(); Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green); Text("Stretch complete").font(.title.bold()); Button("Done") { finish(nil) }.buttonStyle(.borderedProminent).frame(minHeight: 52); Spacer() } else { Spacer(); Image(systemName: timer.movement.icon).font(.system(size: 60)).foregroundStyle(.orange); Text(timer.movement.title).font(.title.bold()); if let side = timer.movement.side { Text(side).foregroundStyle(.orange) }; Text(timer.movement.instruction).multilineTextAlignment(.center); Text(timer.remaining.formatted()).font(.system(size: 56, weight: .bold, design: .rounded)).monospacedDigit(); ProgressView(value: Double(timer.index) / Double(timer.routine.movements.count)); Text("Move only into gentle tension. Stop if you feel pain.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center); HStack { Button(timer.running ? "Pause" : "Resume") { timer.toggle() }.buttonStyle(.borderedProminent); Button(timer.index == timer.routine.movements.count - 1 ? "Finish" : "Next") { timer.next() }.buttonStyle(.bordered) }; Button("End") { timer.running ? (confirmEnd = true) : finish("ended_early") }.frame(minHeight: 48); Spacer() } }.padding(24).safeAreaPadding(.vertical).background(Color(.systemBackground)).onAppear { track(.postWorkoutStretchOffered) }.onChange(of: phase) { _, p in if p != .active { timer.pause() } }.onChange(of: timer.complete) { _, done in if done && !completedTracked { completedTracked = true; track(.postWorkoutStretchCompleted) } }.onDisappear { timer.leave(); UIApplication.shared.isIdleTimerDisabled = false }.onChange(of: timer.running) { _, running in UIApplication.shared.isIdleTimerDisabled = running }.alert("End stretching?", isPresented: $confirmEnd) { Button("End", role: .destructive) { finish("ended_early") }; Button("Cancel", role: .cancel) {} } message: { Text("You can stop whenever you want.") } }
    private func finish(_ result: String?) { timer.leave(); if let result { track(.postWorkoutStretchDismissed, result: result) }; onExit() }
    private func track(_ event: ProductEventName, result: String? = nil) { var p: [ProductPropertyKey: AnalyticsValue] = [.activityType: .string(context.activityType.rawValue), .routineID: .string(context.routine.id)]; if let result { p[.result] = .string(result) }; Task { await analytics?.track(.init(event, properties: p)) } }
}
