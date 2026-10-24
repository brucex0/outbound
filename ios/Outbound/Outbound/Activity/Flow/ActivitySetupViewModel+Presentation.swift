import SwiftUI
import CoreLocation

extension ActivitySetupViewModel {
    var showsManualGoalPills: Bool {
        self.selectedWorkoutChoice != .planned
    }

    var selectedManualSport: SportType? {
        guard case .sport(let sport) = self.selectedWorkoutChoice else { return nil }
        return sport
    }

    var setupActivityType: ActivityType {
        if case .sport(let sport) = self.selectedWorkoutChoice {
            return sport.activityType
        }
        return (self.plannedIntent ?? .freestyleRun).resolvedActivityType
    }

    var isCompanionControlAvailable: Bool {
        (self.plannedIntent ?? .freestyleRun).resolvedActivityType.ineligibleForCompanion == false
    }

    var launchGoalValue: String {
        if self.selectedGoalMode == .planned {
            return self.plannedWorkoutIntent?.title ?? String(localized: "From your training plan")
        }
        if self.selectedGoalMode == .curated {
            return self.curatedWorkoutIntent?.title ?? String(localized: "record.goal.choose_workout", defaultValue: "Choose a workout")
        }
        if self.selectedGoalMode == .race {
            return self.plannedIntent?.raceIntent.map(self.racePlanSummary)
                ?? String(localized: "race.planner.start", defaultValue: "Plan a race effort")
        }
        if self.selectedGoalMode == .freestyle {
            return String(localized: "record.goal.no_target", defaultValue: "No target")
        }
        return self.currentActivityGoal.label(unitSystem: self.dependencies.measurementPreferences.unitSystem)
    }

    var launchGoalHint: String {
        switch self.selectedGoalMode {
        case .planned:
            return String(localized: "From your training plan")
        case .curated:
            return String(localized: "record.goal.tap_change_workout", defaultValue: "Tap to change workout")
        case .freestyle:
            return String(localized: "record.goal.freestyle.short_hint", defaultValue: "Start and move by feel")
        case .race:
            return String(localized: "race.planner.tap_change", defaultValue: "Tap to adjust race strategy")
        case .calories:
            return self.calorieEditorEstimateLabel
                ?? ""
        case .distance, .time:
            return ""
        }
    }

    func resetCuratedStructureForManualGoalIfNeeded() {
        guard self.selectedGoalMode == .curated, let sport = self.selectedManualSport else { return }
        let selectedRoute = self.plannedIntent?.preparedRoute
        let baseIntent = self.freestyleFallback(for: sport)

        if let selectedRoute {
            self.intentBeforeSelectedRoute = baseIntent
            self.plannedIntent = self.routeIntent(selectedRoute, appliedTo: baseIntent)
        } else {
            self.plannedIntent = baseIntent
            self.intentBeforeSelectedRoute = nil
            self.selectedRouteDistanceMeters = nil
        }
    }

    var musicSetupValue: String {
        if self.dependencies.musicStore.playback.isPlaying { return self.dependencies.musicStore.playback.title }
        if let first = self.dependencies.musicStore.selectedCustomItems.first {
            return self.dependencies.musicStore.selectedCustomItems.count > 1
                ? String(localized: "record.music.song_count", defaultValue: "\(self.dependencies.musicStore.selectedCustomItems.count) songs")
                : first.title
        }
        return self.dependencies.musicStore.selectedQuickPick?.title ?? String(localized: "common.off", defaultValue: "Off")
    }

    var musicIsConfigured: Bool { self.dependencies.musicStore.selectedQuickPick != nil || !self.dependencies.musicStore.selectedCustomItems.isEmpty || self.dependencies.musicStore.playback.isPlaying }

    var musicSelectionSummary: String {
        guard let first = self.dependencies.musicStore.selectedCustomItems.first else {
            return self.dependencies.musicStore.selectedQuickPick?.title
                ?? String(localized: "record.music.choose_first", defaultValue: "Choose music to enable playback options")
        }
        if self.dependencies.musicStore.selectedCustomItems.count == 1 { return first.title }
        return String(localized: "record.music.selected_count", defaultValue: "\(self.dependencies.musicStore.selectedCustomItems.count) songs selected")
    }

    func musicSearchSymbol(for category: MusicSearchCategory) -> String {
        switch category {
        case .songs: "music.note"
        case .albums: "square.stack"
        case .playlists: "music.note.list"
        }
    }

    func searchMusic() {
        Task { await self.dependencies.musicStore.searchCatalog(self.musicSearchText, category: self.musicSearchCategory) }
    }

    func prepareMusicPicker() {
        if self.musicSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let intent = self.plannedIntent ?? .freestyleRun
            let text = "\(intent.title) \(intent.detail)".lowercased()
            if text.contains("easy") || text.contains("recovery") || text.contains("walk") {
                self.musicSearchText = String(localized: "record.music.search.recovery", defaultValue: "chill recovery workout")
            } else if text.contains("tempo") || text.contains("threshold") || text.contains("interval") || text.contains("speed") {
                self.musicSearchText = String(localized: "record.music.search.speed", defaultValue: "electronic running workout")
            } else {
                self.musicSearchText = String(localized: "record.music.search.default", defaultValue: "upbeat workout")
            }
        }
        Task { await self.dependencies.musicStore.preloadCatalog(self.musicSearchText) }
    }

    func dismissMusicDiscoveryTip(result: String) {
        self.dependencies.tooltipCoordinator.dismiss(.musicDiscovery, outcome: result)
    }

    func applyWorkoutMusicSuggestion() {
        let intent = self.plannedIntent ?? .freestyleRun
        self.dependencies.musicStore.applyWorkoutSuggestion(title: intent.title, detail: intent.detail, sport: intent.sport)
    }

    var liveTrackValue: String { self.dependencies.liveShareStore.isArmedForNextActivity ? (self.dependencies.liveShareStore.selectedConnections.first?.person.displayName ?? String(localized: "record.live_track.on", defaultValue: "On")) : String(localized: "common.off", defaultValue: "Off") }

    var indoorOutdoorLabel: String {
        self.isIndoorSession
            ? String(localized: "record.setup.indoor", defaultValue: "Indoor")
            : String(localized: "record.setup.outdoor", defaultValue: "Outdoor")
    }

    var preActivityPhotoActionTitle: String {
        if self.dependencies.liveGroupStore.isSharing {
            return String(localized: "record.photo.take_group", defaultValue: "Take group photo")
        }
        return String(localized: "record.photo.take", defaultValue: "Take photo")
    }

    func groupParticipantStatus(_ participant: LiveGroupParticipant) -> String {
        guard let lastLocationAt = participant.lastLocationAt else {
            return participant.statusLabel
        }
        let seconds = max(0, Int(Date().timeIntervalSince(lastLocationAt)))
        let age = seconds < 60 ? "\(seconds)s ago" : "\(seconds / 60)m ago"
        return participant.isFresh ? "Live - \(age)" : "\(participant.statusLabel) - \(age)"
    }

    var selectedSessionShoe: GearItem? {
        if let selectedSessionShoeID = self.selectedSessionShoeID,
           let selectedShoe = self.dependencies.gearStore.activeShoes.first(where: { $0.id == selectedSessionShoeID }) {
            return selectedShoe
        }
        return self.dependencies.gearStore.defaultShoe
    }

    var sessionShoeMenuItems: [GearItem] {
        var shoes = self.dependencies.gearStore.activeShoes
        guard let selectedShoeID = self.selectedSessionShoe?.id,
              let selectedIndex = shoes.firstIndex(where: { $0.id == selectedShoeID }) else {
            return shoes
        }
        let selectedShoe = shoes.remove(at: selectedIndex)
        shoes.insert(selectedShoe, at: 0)
        return shoes
    }

    func applyDefaultSessionShoeIfNeeded() {
        guard !self.didApplyDefaultSessionShoe else { return }
        self.selectedSessionShoeID = self.dependencies.gearStore.defaultShoe?.id
        self.didApplyDefaultSessionShoe = true
    }

    var goalEditorKind: CustomGoalKind? {
        switch self.selectedGoalMode {
        case .distance: .distance
        case .time: .time
        case .calories: .calories
        default: nil
        }
    }

    var goalEditorGoal: ActivityGoal? {
        guard let kind = self.goalEditorKind else { return nil }
        return self.goalEditorSelection ?? self.customActivityGoal(for: kind)
    }

    func goalEditorPresetGoals(for kind: CustomGoalKind) -> [ActivityGoal] {
        switch kind {
        case .distance: self.distanceGoalPresets.map { .distanceMeters($0.meters) }
        case .time: self.timeGoalPresets.map { .timeSeconds($0.seconds) }
        case .calories: self.calorieGoalPresets.map(ActivityGoal.calories)
        }
    }

    func goalEditorPresetTitle(_ goal: ActivityGoal) -> String {
        switch goal {
        case .distanceMeters(let meters):
            self.dependencies.measurementPreferences.unitSystem.distanceString(meters: meters, fractionDigits: 1)
        case .timeSeconds(let seconds):
            String(format: String(localized: "today.time.format", defaultValue: "%d min"), locale: .autoupdatingCurrent, seconds / 60)
        case .calories(let calories): self.calorieGoalLabel(calories)
        case .freestyle: ""
        }
    }

    func plannedWorkoutDurationLabel(for intent: SessionIntent) -> String {
        let stepDuration = intent.workoutSteps.reduce(0) { $0 + $1.durationSeconds }
        return self.workoutStepDurationLabel(stepDuration > 0 ? stepDuration : intent.resolvedTargetDurationSeconds ?? 0)
    }

    func workoutStepDurationLabel(_ seconds: Int) -> String {
        guard seconds > 0 else { return "Open" }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes == 0 { return "\(remainingSeconds)s" }
        if remainingSeconds == 0 { return "\(minutes) min" }
        return "\(minutes)m \(remainingSeconds)s"
    }

    var currentActivityGoal: ActivityGoal {
        (self.plannedIntent ?? .freestyleRun).activityGoal
    }

    var hasWeightForCalories: Bool {
        guard let weightKilograms = self.dependencies.onboardingStore.latestWeightKilograms,
              weightKilograms.isFinite else { return false }
        return (25...350).contains(weightKilograms)
    }

    var weightPromptFieldLabel: String {
        self.dependencies.measurementPreferences.unitSystem == .metric
            ? String(localized: "Weight (kg)")
            : String(localized: "Weight (lb)")
    }

    var promptedWeightKilograms: Double? {
        guard let value = Double(
            self.caloriesWeightText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
        ), value.isFinite else { return nil }
        let kilograms = self.dependencies.measurementPreferences.unitSystem == .metric ? value : value * 0.45359237
        return (25...350).contains(kilograms) ? kilograms : nil
    }

    func resolvedManualSetupDraft(for sport: SportType) -> ActivityManualSetupDraft {
        self.manualSetupDrafts[sport] ?? self.launchPreferenceStore.draft(for: sport)
    }

    func resolvedGoal(
        for draft: ActivityManualSetupDraft,
        mode: SessionGoalMode
    ) -> ActivityGoal {
        draft.goal(
            for: mode,
            defaultDistanceMeters: self.distanceGoalPresets.first?.meters ?? 5_000,
            defaultTimeSeconds: self.timeGoalPresets.first?.seconds ?? 30 * 60,
            defaultCalories: self.calorieGoalPresets.first ?? 300
        )
    }

    func manualDraftGoal(for mode: SessionGoalMode) -> ActivityGoal? {
        guard mode.isLearnableManualMode, let sport = self.selectedManualSport else { return nil }
        return self.resolvedGoal(for: self.resolvedManualSetupDraft(for: sport), mode: mode)
    }

    var distanceGoalPresets: [DistanceGoalPreset] {
        DistanceGoalPreset.recommended(from: self.dependencies.activityStore.activities)
    }

    var timeGoalPresets: [TimeGoalPreset] {
        TimeGoalPreset.recommended(from: self.dependencies.activityStore.activities)
    }

    var calorieGoalPresets: [Int] {
        [150, 250, 300, 400, 500]
    }

    var availableManualGoalModes: [SessionGoalMode] {
        if self.selectedManualSport == .run { return SessionGoalMode.manualCases }
        if self.selectedManualSport == .walk { return SessionGoalMode.manualCases.filter { $0 != .race } }
        return SessionGoalMode.manualCases.filter { $0 != .calories && $0 != .race }
    }

    func racePlanSummary(_ race: RaceExecutionIntent) -> String {
        let distance = self.dependencies.measurementPreferences.unitSystem.distanceString(meters: race.distanceMeters, fractionDigits: 1)
        guard let seconds = race.goalTimeSeconds else {
            return String(
                format: String(localized: "race.planner.finish_summary", defaultValue: "%@ · finish by feel"),
                locale: .autoupdatingCurrent,
                distance
            )
        }
        return "\(distance) · \(Self.raceDurationLabel(seconds))"
    }

    static func raceDurationLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }

    func calorieGoalLabel(_ calories: Int) -> String {
        String(
            format: String(localized: "activity.goal.calories.format", defaultValue: "%d kcal"),
            locale: .autoupdatingCurrent,
            calories
        )
    }

    var calorieEditorEstimateLabel: String? {
        let target = self.currentActivityGoal.targetCalories ?? self.calorieGoalPresets.first ?? 300
        guard let weightKilograms = self.dependencies.onboardingStore.latestWeightKilograms else { return nil }
        let estimate: PlannedCalorieEstimate?
        switch self.selectedManualSport ?? self.plannedIntent?.sport ?? .run {
        case .run:
            let pace = WorkoutCalorieEstimator.resolveLearnedRunPace(
                activities: self.dependencies.activityStore.activities,
                calibrationCompleted: self.dependencies.personalizationStore.snapshot.calibration.status == .completed
            ).secondsPerKilometer
            estimate = WorkoutCalorieEstimator.plannedRun(
                targetCalories: target,
                weightKilograms: weightKilograms,
                paceSecondsPerKilometer: pace
            )
        case .walk:
            estimate = WorkoutCalorieEstimator.plannedWalk(
                targetCalories: target,
                weightKilograms: weightKilograms
            )
        case .bike, .hike, .swim, .strength, .mobility:
            estimate = nil
        }
        guard let estimate else { return nil }
        return self.calorieEstimateLabel(distanceMeters: estimate.distanceMeters, durationSeconds: estimate.durationSeconds)
    }

    func calorieEstimateLabel(for intent: SessionIntent) -> String? {
        guard intent.targetCalories != nil,
              let distanceMeters = intent.estimatedDistanceMeters,
              let durationSeconds = intent.estimatedDurationSeconds else { return nil }
        return self.calorieEstimateLabel(distanceMeters: distanceMeters, durationSeconds: durationSeconds)
    }

    func calorieEstimateLabel(distanceMeters: Double, durationSeconds: Int) -> String {
        let distance = self.dependencies.measurementPreferences.unitSystem.distanceString(meters: distanceMeters, fractionDigits: 1)
        let minutes = max(1, Int((Double(durationSeconds) / 60).rounded()))
        return String(
            format: String(localized: "record.goal.calories.estimate_format", defaultValue: "About %@ · %d min"),
            locale: .autoupdatingCurrent,
            distance,
            minutes
        )
    }

    func customGoalUnitLabel(for kind: CustomGoalKind) -> String {
        switch kind {
        case .distance:
            return self.dependencies.measurementPreferences.unitSystem.distanceUnit
        case .time:
            return String(localized: "record.goal.unit.minutes", defaultValue: "min")
        case .calories:
            return String(localized: "record.goal.unit.calories", defaultValue: "kcal")
        }
    }

    func routeIntent(_ route: PreparedRoute, appliedTo baseIntent: SessionIntent) -> SessionIntent {
        let resolvedSport = route.activityType.map { SportType(activityType: $0) }
            ?? baseIntent.sport
        let preservesBaseStructure = route.activityType == nil
            || route.activityType == baseIntent.resolvedActivityType
        return SessionIntent(
            id: baseIntent.id,
            sport: resolvedSport,
            title: route.name,
            detail: String(localized: "route.guidance.setup.detail", defaultValue: "Follow the selected route with on-device guidance"),
            guideLine: String(localized: "route.guidance.setup.companion", defaultValue: "Keep the route visible and follow it at your own pace."),
            startLabel: String(localized: "route.guidance.start", defaultValue: "Start Route Guidance"),
            targetDistanceMeters: baseIntent.targetDistanceMeters,
            targetDurationSeconds: baseIntent.targetDurationSeconds,
            targetCalories: baseIntent.targetCalories,
            estimatedDistanceMeters: baseIntent.estimatedDistanceMeters,
            estimatedDurationSeconds: baseIntent.estimatedDurationSeconds,
            allowsCalorieGoal: preservesBaseStructure && baseIntent.allowsCalorieGoal,
            routeName: route.name,
            preparedRoute: route,
            activityTypeOverride: route.activityType,
            workoutSteps: preservesBaseStructure ? baseIntent.workoutSteps : [],
            coachingTarget: preservesBaseStructure ? baseIntent.coachingTarget : nil,
            workoutReference: preservesBaseStructure ? baseIntent.workoutReference : nil,
            workoutCues: preservesBaseStructure ? baseIntent.workoutCues : [],
            raceIntent: preservesBaseStructure ? baseIntent.raceIntent : nil,
            activityEvent: preservesBaseStructure ? baseIntent.activityEvent : nil
        )
    }

    func routeFreeIntent(from intent: SessionIntent) -> SessionIntent {
        guard intent.preparedRoute != nil else { return intent }
        return self.freestyleFallback(for: intent.sport)
            .replacingGoal(intent.activityGoal, unitSystem: self.dependencies.measurementPreferences.unitSystem)
    }

    func freestyleFallback(for sport: SportType) -> SessionIntent {
        guard sport != .run else { return .freestyleRun }
        return SessionIntent(
            id: "freestyle-\(sport.rawValue)",
            sport: sport,
            title: sport.displayName,
            detail: String(
                format: String(localized: "activity.freestyle.detail.format", defaultValue: "%@ • no preset target"),
                locale: .autoupdatingCurrent,
                sport.displayName
            ),
            guideLine: String(localized: "activity.freestyle.companion", defaultValue: "Start easy and settle into a comfortable rhythm."),
            startLabel: String(
                format: String(localized: "activity.goal.start.freestyle.format", defaultValue: "Start %@"),
                locale: .autoupdatingCurrent,
                sport.displayName
            )
        )
    }

    func customActivityGoal(for kind: CustomGoalKind) -> ActivityGoal? {
        switch kind {
        case .distance:
            guard let value = Double(self.customDistanceText.replacingOccurrences(of: ",", with: ".")),
                  value.isFinite,
                  value > 0
            else { return nil }
            return .distanceMeters(self.dependencies.measurementPreferences.unitSystem.distanceMeters(from: value))
        case .time:
            guard let minutes = Int(self.customTimeText),
                  minutes > 0,
                  minutes <= Int.max / 60
            else { return nil }
            return .timeSeconds(minutes * 60)
        case .calories:
            guard let calories = Int(self.customCaloriesText), calories > 0 else { return nil }
            return .calories(calories)
        }
    }

    func customGoalAlertTitle(for kind: CustomGoalKind) -> String {
        switch kind {
        case .distance:
            return String(localized: "record.goal.custom_distance", defaultValue: "Custom distance")
        case .time:
            return String(localized: "record.goal.custom_time", defaultValue: "Custom time")
        case .calories:
            return String(localized: "record.goal.custom_calories", defaultValue: "Custom calories")
        }
    }

    var sessionOptionsSummary: String {
        let values = [
            self.selectedSessionShoe?.displayName,
            self.isIndoorSession ? "Treadmill" : nil,
            self.dependencies.liveShareStore.isArmedForNextActivity ? "Live sharing" : nil,
            self.dependencies.liveGroupStore.isSharing ? "Group run" : nil,
            self.selectedGuidanceChallenge == .off ? nil : self.selectedGuidanceChallenge.displayName,
        ].compactMap { $0 }.joined(separator: " · ")
        return values.isEmpty ? "Outdoor · No extras" : values
    }
}
