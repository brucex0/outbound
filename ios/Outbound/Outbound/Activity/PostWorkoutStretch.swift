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
    @AppStorage("stretch_voice_enabled_v1") private var speaksInstructions = true
    @AppStorage("stretch_feedback_enabled_v1") private var transitionFeedback = false
    @State private var showingOptions = false
    @State private var showingLibrary = false
    @State private var showingDetails = false
    @State private var instruction: StretchMovement?
    @State private var editing = false
    @State private var toast: String?

    init(launch: StretchLaunchContext = StretchLaunchContext(), voiceProfileID: String, onExit: @escaping () -> Void, @ViewBuilder header: @escaping (@escaping () -> Void) -> Header) {
        self.launch = launch
        self.onExit = onExit
        self.header = header
        let routines = StretchCatalog.routines(activityType: launch.activityType, entryPoint: launch.entryPoint)
        let initial = StretchCatalog.initial(routines, isIndoor: launch.isIndoor,
            last: UserDefaults.standard.string(forKey: "stretch_last_routine_v1"),
            lastStanding: UserDefaults.standard.string(forKey: "stretch_last_standing_routine_v1"), sport: launch.activityType)
        _routines = State(initialValue: routines)
        _timer = StateObject(wrappedValue: PostWorkoutStretchTimer(routine: initial))
        _narrator = StateObject(wrappedValue: StretchNarrator(voice: voiceProfileID))
    }

    var body: some View {
        Group {
            if !chosen {
                VStack(spacing: 0) {
                    if launch.entryPoint != .postSave || showingDetails {
                        screenHeader
                    }
                    ScrollView {
                        VStack(spacing: 20) {
                            if launch.entryPoint == .postSave && !showingDetails {
                                header { finish("not_started") }
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(stretchText("post_workout_stretch.offer_title", "A gentle reset?")).font(.title2.bold())
                                    Text(timer.routine.title).font(.headline)
                                    Text(timer.routine.calculatedDuration + " · " + timer.routine.requirements)
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Button(stretchUI("change")) { showingDetails = true }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
                            } else {
                                routineDetails
                            }
                            Text(stretchText("post_workout_stretch.disclaimer", "General wellness guidance. Stop if you feel pain, dizziness, or unusual discomfort."))
                                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: 540).padding(24).frame(maxWidth: .infinity)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button(action: startRoutine) {
                        Text(stretchCatalogText("ui.start"))
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(.orange)
                    .padding(.horizontal, 24).padding(.vertical, 12).background(.bar)
                }
            } else if timer.complete {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(.green)
                    Text(stretchCatalogText("ui.complete")).font(.title.bold())
                    Button(stretchText("post_workout_stretch.done", "Done")) { finish(nil) }.buttonStyle(.borderedProminent).frame(minHeight: 52)
                    Spacer()
                }
            } else {
                activePlayer
            }
        }
        .onChange(of: showingLibrary) { _, visible in if visible { track(.stretchInterfaceUsed, result: "routines_opened") } }
        .sheet(isPresented: $showingLibrary) {
            NavigationStack {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !routines.contains(where: { $0.id == timer.routine.id }) { stretchProgramOption(timer.routine) }
                        ForEach(routines) { stretchProgramOption($0) }
                    }.padding(24)
                }
                .navigationTitle(stretchUI("routines"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(stretchCatalogText("ui.done")) { showingLibrary = false } } }
            }
        }
        .sheet(isPresented: $showingOptions) {
            NavigationStack {
                Form {
                    Toggle(stretchText("post_workout_stretch.voice_over", "Speak posture titles"), isOn: $speaksInstructions)
                    Toggle(stretchText("post_workout_stretch.feedback", "Transition sound & haptics"), isOn: $transitionFeedback)
                }
                .navigationTitle(stretchUI("options"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(stretchCatalogText("ui.done")) { showingOptions = false } } }
            }.presentationDetents([.medium, .large])
        }
        .sheet(item: $instruction) { movement in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        StretchPostureIllustration(cue: movement.cue).frame(height: 260).frame(maxWidth: .infinity)
                        Text(movement.title).font(.title2.bold())
                        Text(movement.instruction).font(.body)
                        Text(stretchText("post_workout_stretch.safety", "Move only into gentle tension. Stop if you feel pain.")).foregroundStyle(.secondary)
                    }.padding(24)
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(stretchCatalogText("ui.done")) { instruction = nil } } }
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
        .onChange(of: instruction?.id) { _, value in
            if value != nil {
                track(.stretchInterfaceUsed, result: "instructions_opened")
                if chosen { timer.pause(); narrator.stop() }
            }
        }
        .onChange(of: showingOptions) { _, visible in
            if visible {
                track(.stretchInterfaceUsed, result: "options_opened")
                if chosen { timer.pause(); narrator.stop() }
            }
        }
        .onChange(of: transitionFeedback) { _, enabled in track(.stretchInterfaceUsed, result: enabled ? "feedback_enabled" : "feedback_disabled") }
        .onChange(of: speaksInstructions) { _, enabled in
            track(.stretchInterfaceUsed, result: enabled ? "voice_enabled" : "voice_disabled")
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

    private var screenHeader: some View {
        HStack {
            Button {
                if chosen { timer.running ? (confirmEnd = true) : finish("ended_early") }
                else if launch.entryPoint == .postSave { showingDetails = false }
                else { finish("not_started") }
            } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
            .accessibilityLabel(stretchCatalogText("ui.done"))
            Spacer()
            if chosen {
                Text("\(timer.index + 1) / \(timer.routine.movements.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Text(timer.routine.title).font(.headline).lineLimit(2)
            }
            Spacer()
            Button { showingOptions = true } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .accessibilityLabel(stretchUI("options"))
        }.padding(.horizontal, 12)
    }

    private var routineDetails: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(timer.routine.calculatedDuration).font(.title2.bold())
                    Text(timer.routine.requirements).font(.subheadline).foregroundStyle(.secondary)
                    if timer.routine.customized { Text(stretchCatalogText("ui.your_version")).font(.caption).foregroundStyle(.orange) }
                }
                Spacer()
                Button(stretchUI("change")) { showingLibrary = true }
            }
            HStack {
                Text(stretchUI("movements")).font(.headline)
                Spacer()
                Button(stretchCatalogText("ui.customize")) { editing = true; track(.stretchRoutineEdited, result: "opened") }
            }
            VStack(spacing: 0) {
                ForEach(timer.routine.entries) { entry in
                    if let definition = StretchCatalog.definition(entry.movementID),
                       let movement = timer.routine.movements.first(where: { $0.cue.hasPrefix(entry.movementID + "_") }) {
                        Button { instruction = movement } label: {
                            HStack(spacing: 16) {
                                StretchPostureIllustration(cue: movement.cue).frame(width: 72, height: 80)
                                    .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(definition.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Text(Duration.seconds(entry.seconds).formatted(.time(pattern: .minuteSecond)) + (definition.bilateral ? " · " + stretchUI("each_side") : ""))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "info.circle").foregroundStyle(.secondary)
                            }.padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if entry.id != timer.routine.entries.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func startRoutine() {
        UserDefaults.standard.set(timer.routine.preferenceID, forKey: "stretch_last_routine_v1")
        if timer.routine.isStanding { UserDefaults.standard.set(timer.routine.preferenceID, forKey: "stretch_last_standing_routine_v1") }
        chosen = true
        track(.postWorkoutStretchStarted)
        timer.start()
        speakCurrentMovement()
    }

    private var activePlayer: some View {
        VStack(spacing: 0) {
            screenHeader
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 18) {
                        StretchPostureIllustration(cue: timer.movement.cue)
                            .frame(height: max(180, min(320, geometry.size.height * 0.43)))
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.05), in: RoundedRectangle(cornerRadius: 32))
                        if timer.phase != .holding {
                            Text(timer.phase == .preparing ? stretchText("post_workout_stretch.get_ready", "Get ready") : stretchText("post_workout_stretch.transition", "Transition"))
                                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        }
                        VStack(spacing: 6) {
                            Text(timer.movement.title).font(.title2.bold())
                            if let side = timer.movement.side { Text(side).font(.headline).foregroundStyle(.orange) }
                            Text(stretchCatalogText(timer.routine.isWarmup ? "ui.move" : "ui.hold")).font(.subheadline).foregroundStyle(.secondary)
                        }.multilineTextAlignment(.center)
                        Text(Duration.seconds(timer.remaining).formatted(.time(pattern: .minuteSecond)))
                            .font(.system(size: 60, weight: .semibold, design: .rounded)).monospacedDigit()
                        let progress = timer.phase == .holding ? 1 - Double(timer.remaining) / Double(max(timer.movement.duration, 1)) : 0
                        ProgressView(value: Double(timer.index) + progress, total: Double(timer.routine.movements.count)).tint(.orange)
                        if let definition = StretchCatalog.definition(timer.routine.entries.first(where: { timer.movement.cue.hasPrefix($0.movementID + "_") })?.movementID ?? ""), !definition.requirements.isEmpty {
                            Text(definition.requirements).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                        Text(stretchText("post_workout_stretch.safety", "Move only into gentle tension. Stop if you feel pain."))
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(.horizontal, 28).padding(.vertical, 12).frame(maxWidth: 540).frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 12) {
                if timer.index + 1 < timer.routine.movements.count { Text(nextMovementLabel).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                HStack(spacing: 32) {
                    Button { instruction = timer.movement } label: { Image(systemName: "info.circle").font(.title2).frame(width: 48, height: 48) }
                        .accessibilityLabel(stretchUI("instructions"))
                    Button(action: toggleTimer) {
                        Image(systemName: timer.running ? "pause.fill" : "play.fill").font(.title).frame(width: 76, height: 76)
                            .foregroundStyle(.white).background(.orange, in: Circle())
                    }.accessibilityLabel(timer.running ? stretchText("post_workout_stretch.pause", "Pause") : stretchText("post_workout_stretch.resume", "Resume"))
                    Button {
                        if timer.phase == .holding { timer.next() } else { narrator.stop(); timer.startMovementNow() }
                    } label: { Image(systemName: "forward.end.fill").font(.title2).frame(width: 48, height: 48) }
                    .accessibilityLabel(timer.phase == .holding ? stretchText("post_workout_stretch.next", "Next") : stretchText("post_workout_stretch.start_now", "Start now"))
                }.buttonStyle(.plain)
            }.padding(.horizontal, 24).padding(.bottom, 16)
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
            guard !isSelected else { showingLibrary = false; return }
            timer.select(routine)
            showingLibrary = false
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
            routines = StretchCatalog.routines(activityType: launch.activityType, entryPoint: launch.entryPoint)
            if let routine = routines.first(where: { $0.preferenceID == id }) { timer.select(routine) }
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
struct StretchSchematicIllustration: View {
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

/// Catalog artwork is vector PDF; mirroring follows the existing side contract.
struct StretchPostureIllustration: View {
    let cue: String
    var body: some View {
        let id = cue.replacingOccurrences(of: "_left", with: "").replacingOccurrences(of: "_right", with: "").replacingOccurrences(of: "_both", with: "")
        if let definition = StretchCatalog.definition(id), let artwork = definition.artwork {
            Image(artwork).resizable().scaledToFit()
                .scaleEffect(x: (definition.artworkSide == "right" ? cue.hasSuffix("_left") : cue.hasSuffix("_right")) ? -1 : 1, y: 1)
                .accessibilityHidden(true)
        } else {
            StretchSchematicIllustration(cue: cue)
        }
    }
}
