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

struct PostSavedStretchContext {
    let activityType: ActivityType
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
    @Published private(set) var routine: StretchRoutine
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

/// Post-save adapter: the reusable session owns no recording, sharing, or celebration state.
struct PostWorkoutStretchView: View {
    let context: PostSavedStretchContext
    let activity: SavedActivity
    let voiceProfileID: String
    let onExit: () -> Void
    var body: some View {
        StretchSessionView(launch: StretchLaunchContext(entryPoint: .postSave, activityType: context.activityType, isIndoor: activity.indoor?.isIndoor == true), voiceProfileID: voiceProfileID, onExit: onExit) { finish in
            PostSaveCelebrationCard(activity: activity).id(activity.id).frame(height: 205)
            Text(String(localized: "activity.post_save.message", defaultValue: "You made time for this today."))
                .font(.title3.weight(.semibold)).multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            PostSaveActivityActions(activity: activity, onDone: finish)
        }
    }
}

/// Reuse from Today with StretchLaunchContext(entryPoint: .today), without a SavedActivity.
struct StretchSessionView<Header: View>: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.analyticsManager) private var analytics
    @StateObject private var timer: PostWorkoutStretchTimer
    @StateObject private var narrator: StretchNarrator
    let launch: StretchLaunchContext
    let onExit: () -> Void
    let header: (@escaping () -> Void) -> Header
    @State private var routines: [StretchRoutine]
    @State private var chosen = false
    @State private var confirmEnd = false
    @State private var completedTracked = false
    @State private var speaksInstructions = true
    @State private var transitionFeedback = false
    @State private var showMoreRoutines = false
    @State private var editing = false
    @State private var toast: String?

    init(launch: StretchLaunchContext = StretchLaunchContext(), voiceProfileID: String, onExit: @escaping () -> Void, @ViewBuilder header: @escaping (@escaping () -> Void) -> Header) {
        self.launch = launch
        self.onExit = onExit
        self.header = header
        let routines = StretchCatalog.routines(activityType: launch.activityType)
        let initial = StretchCatalog.initial(routines, isIndoor: launch.isIndoor,
            last: UserDefaults.standard.string(forKey: "stretch_last_routine_v1"),
            lastStanding: UserDefaults.standard.string(forKey: "stretch_last_standing_routine_v1"), sport: launch.activityType)
        _routines = State(initialValue: routines)
        _timer = StateObject(wrappedValue: PostWorkoutStretchTimer(routine: initial))
        _showMoreRoutines = State(initialValue: !initial.isStanding)
        _narrator = StateObject(wrappedValue: StretchNarrator(voice: voiceProfileID))
    }

    var body: some View {
        Group {
            if !chosen {
                ScrollView {
                    VStack(spacing: 16) {
                        header { finish("not_started") }
                        if launch.entryPoint != .postSave { Button(stretchCatalogText("ui.done")) { finish("not_started") } }

                        Text(stretchText("post_workout_stretch.offer_title", "A gentle reset?"))
                            .font(.title2.bold())
                            .padding(.top, 4)
                        Text(stretchText("post_workout_stretch.offer_body", "Take a few minutes for an optional, easy stretch routine."))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(String(localized: "activity.post_save.program.title", defaultValue: "Choose a stretch"))
                                .font(.headline)
                            if !routines.contains(where: { $0.id == timer.routine.id }) { stretchProgramOption(timer.routine) }
                            ForEach(routines.filter(\.isStanding)) { routine in
                                stretchProgramOption(routine)
                            }
                            DisclosureGroup(stretchText("post_workout_stretch.more_routines", "More routines"), isExpanded: $showMoreRoutines) {
                                ForEach(routines.filter { !$0.isStanding }) { routine in
                                    stretchProgramOption(routine)
                                }
                            }
                        }

                        Button(stretchCatalogText("ui.customize")) { editing = true; track(.stretchRoutineEdited, result: "opened") }
                        Text(timer.routine.calculatedDuration + " · " + timer.routine.requirements).font(.caption)
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
        .sheet(isPresented: $editing) {
            StretchRoutineEditor(routine: timer.routine, onSave: saveCustomization) { action in track(.stretchRoutineEdited, result: action) }
        }
        .overlay(alignment: .bottom) {
            if let toast { Text(toast).padding().background(.regularMaterial, in: Capsule()).padding().accessibilityAddTraits(.updatesFrequently) }
        }
        .task(id: toast) { if toast != nil { try? await Task.sleep(for: .seconds(3)); toast = nil } }
        .safeAreaPadding(.vertical)
        .background(Color(.systemBackground))
        .onAppear {
            timer.audioPlaying = { narrator.isPlaying }
            track(.postWorkoutStretchOffered)
            timer.onStepEnded = { skipped, seconds in
                track(.postWorkoutStretchStepEnded, result: skipped ? "skipped" : "held", seconds: seconds)
            }
        }
        .task(id: timer.routine.movements.map(\.cue)) { await narrator.preload(timer.routine.movements.map(\.cue)) }
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
                    if routine.customized { Text(stretchCatalogText("ui.your_version")).font(.caption) }
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

    private func saveCustomization(_ entries: [StretchEntry]?) -> Bool {
        let id = timer.routine.preferenceID
        let store = StretchCustomizationStore()
        do {
            if let entries { try store.save(entries, templateID: id) } else { store.reset(id) }
            routines = StretchCatalog.routines(activityType: launch.activityType)
            if let routine = routines.first(where: { $0.preferenceID == id }) { timer.select(routine); showMoreRoutines = !routine.isStanding }
            toast = stretchCatalogText("ui.saved")
            track(.stretchRoutineEdited, result: entries == nil ? "reset" : "saved")
            return true
        } catch {
            ActivityDiagnosticLog.error(.lifecycle, "Stretch customization save failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            return false
        }
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
            .sourceType: .string(launch.entryPoint.rawValue),
            .routineID: .string(routineID ?? timer.routine.id)
        ]
        if let type = launch.activityType { properties[.activityType] = .string(type.rawValue) }
        if event == .postWorkoutStretchStarted { properties[.control] = .string("clock_tick") }
        properties[.stretchCustomized] = .boolean(timer.routine.customized)
        if event == .postWorkoutStretchStarted || event == .stretchRoutineEdited && ["saved", "reset"].contains(result ?? "") {
            let count = timer.routine.entries.count
            properties[.countBucket] = .string(count <= 3 ? "one_to_three" : count <= 6 ? "four_to_six" : "seven_plus")
            let duration = timer.routine.totalSeconds
            properties[.durationBucket] = .string(duration < 180 ? "under_3_min" : duration < 360 ? "3_to_6_min" : "6_plus_min")
        }
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
struct StretchPostureIllustration: View {
    let cue: String
    var body: some View {
        Canvas { context, size in
            let id = cue.replacingOccurrences(of: "_left", with: "").replacingOccurrences(of: "_right", with: "").replacingOccurrences(of: "_both", with: "")
            guard let definition = StretchCatalog.definition(id), let first = definition.paths.first?.first else { return }
            let mirror = cue.hasSuffix("_right")
            let scale = min(size.width, size.height) / 100
            let offset = CGPoint(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
            func point(_ p: CGPoint) -> CGPoint { CGPoint(x: offset.x + (mirror ? 100 - p.x : p.x) * scale, y: offset.y + p.y * scale) }
            let head = point(CGPoint(x: first.x + (definition.lying ? -7 : 0), y: first.y + (definition.lying ? 0 : -7)))
            context.stroke(Path(ellipseIn: CGRect(x: head.x - 6 * scale, y: head.y - 6 * scale, width: 12 * scale, height: 12 * scale)), with: .color(.primary), lineWidth: 3 * scale)
            for (index, line) in definition.paths.enumerated() {
                var path = Path()
                for (i, p) in line.enumerated() { if i == 0 { path.move(to: point(p)) } else { path.addLine(to: point(p)) } }
                context.stroke(path, with: .color(index == definition.paths.count - 1 ? .orange : .primary), style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round, lineJoin: .round))
            }
        }.accessibilityHidden(true)
    }
}

extension StretchSessionView where Header == EmptyView {
    init(launch: StretchLaunchContext = StretchLaunchContext(), voiceProfileID: String, onExit: @escaping () -> Void) {
        self.init(launch: launch, voiceProfileID: voiceProfileID, onExit: onExit) { _ in EmptyView() }
    }
}
