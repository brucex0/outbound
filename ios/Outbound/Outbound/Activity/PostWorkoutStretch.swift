import SwiftUI
import Combine
import AVFoundation
import AudioToolbox

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
    var cue: String { id.split(separator: "_").dropFirst().joined(separator: "_") }
}

struct StretchRoutine: Sendable, Identifiable {
    let id: String
    let title: String
    let durationLabel: String
    var isStanding: Bool { id.contains("_standing_") }
    var preferenceID: String {
        if id.contains("_standing_quick_") { return "standing_quick" }
        if isStanding { return "standing_standard" }
        return id.contains("_hips_hamstrings_") ? "mat_quick" : "mat_standard"
    }
    var requirements: String {
        stretchText(isStanding ? (preferenceID == "standing_quick" ? "post_workout_stretch.requirements.standing_quick" : "post_workout_stretch.requirements.standing_standard") : "post_workout_stretch.requirements.mat", "")
    }
    let movements: [StretchMovement]
    var totalSeconds: Int { movements.reduce(0) { $0 + $1.duration } + 3 + max(0, movements.count - 1) * 5 }
    var calculatedDuration: String { "≈ " + Duration.seconds(totalSeconds).formatted(.time(pattern: .minuteSecond)) }
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

        let quickStanding = ["calf", "soleus", "standing_hamstring"].flatMap {
            bilateralSteps(prefix: prefix, id: $0, titleKey: $0, instructionKey: $0, seconds: 15, icon: "figure.stand")
        }
        let standardStanding = ["calf", "soleus", "standing_hamstring", "quad", "shoulder"].flatMap {
            bilateralSteps(prefix: prefix, id: $0, titleKey: $0, instructionKey: $0, seconds: 25, icon: "figure.stand")
        }
        return [
            StretchRoutine(id: "post_save_\(prefix)_standing_quick_v1",
                title: stretchText("post_workout_stretch.routine.standing_quick", "Standing reset"), durationLabel: "", movements: quickStanding),
            StretchRoutine(id: "post_save_\(prefix)_standing_standard_v1",
                title: stretchText("post_workout_stretch.routine.standing_standard", "Standing stretch"), durationLabel: "", movements: standardStanding),
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

    static func initialRoutine(_ routines: [StretchRoutine], isIndoor: Bool, lastRoutine: String?, lastStanding: String?) -> StretchRoutine {
        let preference = isIndoor ? lastRoutine : lastStanding
        return routines.first { $0.preferenceID == preference && (isIndoor || $0.isStanding) } ?? routines[0]
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
    @Published var skipped = 0
    @Published var heldSeconds = 0
    var audioPlaying: () -> Bool = { false }
    var onStepEnded: ((Bool, Int) -> Void)?
    private var stepHeld = 0
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
                if audioPlaying() && remaining <= 1 && (phase == .preparing || phase == .transitioning) { continue }
                if phase == .holding { heldSeconds += 1; stepHeld += 1 }
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
        skipped = 0
        heldSeconds = 0
        stepHeld = 0
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
            beginNextMovement(skipped: true)
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

    private func beginNextMovement(skipped wasSkipped: Bool = false) {
        if wasSkipped { skipped += 1 }
        onStepEnded?(wasSkipped, stepHeld)
        stepHeld = 0
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
    @StateObject private var narrator: StretchNarrator
    let context: PostSavedStretchContext
    let activity: SavedActivity
    let onExit: () -> Void
    @State private var chosen = false
    @State private var confirmEnd = false
    @State private var completedTracked = false
    @State private var speaksInstructions = true
    @State private var transitionFeedback = false
    @State private var showMoreRoutines = false

    init(context: PostSavedStretchContext, activity: SavedActivity, voiceProfileID: String, onExit: @escaping () -> Void) {
        self.context = context
        self.activity = activity
        self.onExit = onExit
        let initial = PostWorkoutStretchCatalog.initialRoutine(context.routines,
            isIndoor: activity.indoor?.isIndoor == true,
            lastRoutine: UserDefaults.standard.string(forKey: "stretch_last_routine_v1"),
            lastStanding: UserDefaults.standard.string(forKey: "stretch_last_standing_routine_v1"))
        _timer = StateObject(wrappedValue: PostWorkoutStretchTimer(routine: initial))
        _showMoreRoutines = State(initialValue: !initial.isStanding)
        _narrator = StateObject(wrappedValue: StretchNarrator(voice: voiceProfileID))
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
                            ForEach(context.routines.filter(\.isStanding)) { routine in
                                stretchProgramOption(routine)
                            }
                            DisclosureGroup(stretchText("post_workout_stretch.more_routines", "More routines"), isExpanded: $showMoreRoutines) {
                                ForEach(context.routines.filter { !$0.isStanding }) { routine in
                                    stretchProgramOption(routine)
                                }
                            }
                        }

                        DisclosureGroup(stretchText("post_workout_stretch.preview", "Preview movements")) {
                            ForEach(timer.routine.movements) { movement in
                                HStack {
                                    StretchPostureIllustration(cue: movement.cue).frame(width: 56, height: 56)
                                    VStack(alignment: .leading) {
                                        Text(movement.title + " · " + (movement.side ?? ""))
                                        Text(movement.instruction).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Toggle(stretchText("post_workout_stretch.voice_over", "Speak posture titles"), isOn: $speaksInstructions)
                            .fixedSize(horizontal: false, vertical: true)

                        Toggle(stretchText("post_workout_stretch.feedback", "Transition sound & haptics"), isOn: $transitionFeedback)
                        Button(stretchText("post_workout_stretch.start", "Start stretching")) {
                            UserDefaults.standard.set(timer.routine.preferenceID, forKey: "stretch_last_routine_v1")
                            if timer.routine.isStanding {
                                UserDefaults.standard.set(timer.routine.preferenceID, forKey: "stretch_last_standing_routine_v1")
                            }
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
                activePlayer
            }
        }
        .safeAreaPadding(.vertical)
        .background(Color(.systemBackground))
        .onAppear {
            timer.audioPlaying = { narrator.isPlaying }
            track(.postWorkoutStretchOffered)
            timer.onStepEnded = { skipped, seconds in
                track(.postWorkoutStretchStepEnded, result: skipped ? "skipped" : "held", seconds: seconds)
            }
        }
        .task(id: timer.routine.id) { await narrator.preload(timer.routine.movements.map(\.cue)) }
        .onChange(of: timer.remaining) { _, seconds in
            guard chosen, timer.running, timer.phase == .holding, (1...5).contains(seconds) else { return }
            if speaksInstructions { narrator.tick() }
        }
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
                if speaksInstructions { narrator.play("release") }
                if !completedTracked {
                    completedTracked = true
                    track(.postWorkoutStretchCompleted, result: timer.skipped == 0 ? "fully_held" : "with_skips", seconds: timer.heldSeconds)
                }
            }
        }
        .onDisappear {
            timer.leave()
            timer.onStepEnded = nil
            timer.audioPlaying = { false }
            narrator.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: timer.running) { _, running in UIApplication.shared.isIdleTimerDisabled = running }
        .alert(stretchText("post_workout_stretch.end_title", "End stretching?"), isPresented: $confirmEnd) {
            Button(stretchText("post_workout_stretch.end_confirm", "End"), role: .destructive) { finish("ended_early") }
            Button(stretchText("post_workout_stretch.cancel", "Cancel"), role: .cancel) {}
        } message: { Text(stretchText("post_workout_stretch.end_message", "You can stop whenever you want.")) }
    }

    private var activePlayer: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer()
                StretchPostureIllustration(cue: timer.movement.cue).frame(height: 150)
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
                        Button(stretchText("post_workout_stretch.start_now", "Start now")) { narrator.stop(); timer.startMovementNow() }.buttonStyle(.bordered)
                    } else if timer.phase == .holding {
                        Button(stretchText("post_workout_stretch.next", "Next")) { timer.next() }.buttonStyle(.bordered)
                    }
                }
                if timer.index + 1 < timer.routine.movements.count {
                    Text(nextMovementLabel)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Toggle(stretchText("post_workout_stretch.voice_over", "Speak posture titles"), isOn: $speaksInstructions)
                Button(stretchText("post_workout_stretch.end", "End")) { timer.running ? (confirmEnd = true) : finish("ended_early") }.frame(minHeight: 48)
                Spacer()
            }.padding(24)
        }
    }

    private var nextMovementLabel: String {
        guard timer.index + 1 < timer.routine.movements.count else { return "" }
        let next = timer.routine.movements[timer.index + 1]
        return stretchText("post_workout_stretch.up_next", "Up next") + ": " + next.title + " · " + (next.side ?? "")
    }

    private func finish(_ result: String?) {
        timer.leave()
        narrator.stop()
        if let result { track(.postWorkoutStretchDismissed, result: result, seconds: timer.heldSeconds) }
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
                    Text(routine.calculatedDuration).font(.caption).foregroundStyle(.secondary)
                    Text(routine.requirements).font(.caption).foregroundStyle(.secondary)
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
            if timer.phase != .holding { speakCurrentMovement(announceRelease: timer.phase == .transitioning) }
        }
    }

    private func speakCurrentMovement(announceRelease: Bool = false) {
        guard phase == .active else { return }
        if transitionFeedback && announceRelease {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            AudioServicesPlaySystemSound(1104)
        }
        guard speaksInstructions else { return }
        narrator.play(timer.movement.cue, releaseFirst: announceRelease)
    }

    private func track(_ event: ProductEventName, result: String? = nil, routineID: String? = nil, seconds: Int? = nil) {
        var properties: [ProductPropertyKey: AnalyticsValue] = [
            .activityType: .string(context.activityType.rawValue),
            .routineID: .string(routineID ?? timer.routine.id)
        ]
        if event == .postWorkoutStretchStarted { properties[.control] = .string("clock_tick") }
        if let result { properties[.result] = .string(result) }
        if let seconds { properties[.countBucket] = .string(seconds == 0 ? "zero" : seconds < 20 ? "under_20" : seconds < 60 ? "20_to_59" : "60_plus") }
        Task { await analytics?.track(.init(event, properties: properties)) }
    }
}

@MainActor
private final class StretchNarrator: ObservableObject {
    private let player = GuideAudioPlayer()
    var isPlaying: Bool { player.isSpeaking }
    private var clips: [String: Data] = [:]
    private lazy var tickData: Data? = {
        guard let url = Bundle.main.url(forResource: "stretch_tick", withExtension: "wav") else {
            ActivityDiagnosticLog.error(.lifecycle, "Stretch clock tick resource missing")
            return nil
        }
        do { return try Data(contentsOf: url) }
        catch {
            ActivityDiagnosticLog.error(.lifecycle, "Stretch clock tick load failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            return nil
        }
    }()

    func tick() {
        guard let tickData else { return }
        if !player.play(tickData, interrupt: true) {
            ActivityDiagnosticLog.error(.lifecycle, "Stretch clock tick playback failed")
        }
    }
    private let voice: String

    init(voice: String) {
        self.voice = voice
    }
    private var locale: String { AppLanguage.currentIdentifier }
    private var directory: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("StretchAudio-v1") }

    func preload(_ movementCues: [String]) async {
        var seen = Set<String>()
        let cues = (movementCues + ["release"]).filter { seen.insert($0).inserted }
        for cue in cues {
            guard !Task.isCancelled else { return }
            let url = directory.appendingPathComponent("\(locale)-\(voice)-\(cue).wav")
            if let data = try? Data(contentsOf: url), (try? AVAudioPlayer(data: data)) != nil { clips[cue] = data; continue }
            do {
                let data = try await APIClient.shared.fetchStretchAudio(cue: cue, locale: locale, voice: voice)
                guard (try? AVAudioPlayer(data: data)) != nil else {
                    ActivityDiagnosticLog.error(.lifecycle, "Stretch audio decode failed cue=\(cue)")
                    continue
                }
                clips[cue] = data
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch is CancellationError { return }
            catch {
                ActivityDiagnosticLog.error(.lifecycle, "Stretch audio preload failed cue=\(cue) error=\(ActivityDiagnosticLog.errorCategory(error))")
            }
        }
    }

    func play(_ cue: String, releaseFirst: Bool = false, completion: (() -> Void)? = nil) {
        let sequence = (releaseFirst ? ["release", cue] : [cue]).compactMap { clips[$0] }
        guard !sequence.isEmpty else {
            ActivityDiagnosticLog.error(.lifecycle, "Stretch audio unavailable cue=\(cue)")
            completion?()
            return
        }
        if !player.playSequence(sequence, completion: completion) { completion?() }
    }
    func stop() { player.stopSpeaking(at: .immediate) }
}

/// Schematic setup reference; the orange limb marks the working side.
private struct StretchPostureIllustration: View {
    let cue: String
    var body: some View {
        Canvas { context, size in
            let points: [[CGPoint]] = posturePoints(cue)
            let scale = min(size.width / 100, size.height / 100)
            let offset = CGPoint(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
            if let first = points.first?.first {
                let lying = cue.hasPrefix("glute") || cue.hasPrefix("hamstring")
                let center = CGPoint(x: offset.x + (first.x + (lying ? -7 : 0)) * scale, y: offset.y + (first.y + (lying ? 0 : -7)) * scale)
                context.stroke(Path(ellipseIn: CGRect(x: center.x - 6 * scale, y: center.y - 6 * scale, width: 12 * scale, height: 12 * scale)), with: .color(.primary), lineWidth: 3 * scale)
            }
            for (index, line) in points.enumerated() {
                var path = Path()
                for (i, point) in line.enumerated() {
                    let p = CGPoint(x: offset.x + point.x * scale, y: offset.y + point.y * scale)
                    if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                context.stroke(path, with: .color(index == points.count - 1 ? .orange : .primary), style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round, lineJoin: .round))
            }
        }.accessibilityHidden(true)
    }
    private func posturePoints(_ cue: String) -> [[CGPoint]] {
        let raw: [[(Double, Double)]]
        if cue.hasPrefix("standing_hamstring") { raw = [[(65,30),(50,55)],[(60,40),(45,60),(35,75)],[(50,55),(35,75),(35,90)],[(50,55),(80,90),(88,82)]] }
        else if cue.hasPrefix("shoulder") { raw = [[(50,20),(50,60)],[(50,60),(35,90)],[(50,60),(65,90)],[(35,35),(55,50),(50,40)],[(65,35),(30,40)]] }
        else if cue.hasPrefix("soleus") { raw = [[(60,20),(50,55)],[(60,30),(70,50),(72,70)],[(50,55),(72,70),(80,90),(90,90)],[(50,55),(25,70),(20,90),(10,90)]] }
        else if cue.hasPrefix("glute") { raw = [[(15,75),(35,75),(55,60),(75,60)],[(35,75),(45,45),(60,55)],[(45,45),(70,40),(75,60)],[(55,60),(55,80),(80,80)]] }
        else if cue.hasPrefix("hamstring") { raw = [[(15,80),(45,80)],[(30,80),(50,55),(57,50)],[(45,80),(80,80)],[(45,80),(60,35)]] }
        else if cue.hasPrefix("inner") { raw = [[(50,20),(50,55)],[(50,35),(30,60)],[(50,55),(30,80),(50,75)],[(50,55),(70,80),(50,75)]] }
        else if cue.hasPrefix("calf") { raw = [[(65,20),(50,55)],[(60,30),(70,50),(70,70)],[(50,55),(70,70),(80,90),(90,90)],[(50,55),(20,90),(10,90)]] }
        else if cue.hasPrefix("quad") { raw = [[(50,20),(50,55)],[(50,55),(50,90)],[(50,30),(20,35)],[(20,25),(20,90)],[(50,35),(70,55),(70,65)],[(50,55),(80,85),(70,65)]] }
        else { raw = [[(50,15),(50,55)],[(50,35),(70,55)],[(50,55),(70,60),(70,85)],[(50,55),(30,85),(15,85)]] }
        return raw.map { $0.map { x, y in CGPoint(x: cue.hasSuffix("right") ? 100 - x : x, y: y) } }
    }
}
