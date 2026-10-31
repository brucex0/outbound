import Foundation
import OSLog
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The model interprets language; these values never execute an app action directly.
struct LocalAssistantInterpretation: Codable, Sendable {
    var kind: String
    var capability: String
    var task: String
    var destination: String?
    var sport: String?
    var durationHours: Double?
    var durationMinutes: Double?
    var durationSeconds: Double?
    var distanceValue: Double?
    var distanceUnit: String?
    var paceMinutes: Double?
    var paceSeconds: Double?
    var paceUnit: String?
    var localDate: String?
    var localTime: String?
    var isIndoor: Bool?
    var clarification: String?

    var clarificationText: String? {
        let text = clarification?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : String(text.prefix(600))
    }

    var resolvedCapability: AssistantCapability { AssistantCapability(rawValue: capability) ?? .discover }
    var resolvedTask: CompanionTask { CompanionTask(rawValue: task) ?? .productHelp }
    var navigationTarget: AssistantNavigationTarget? {
        guard kind == "navigate", let destination,
              let id = AssistantDestinationID(rawValue: destination) else { return nil }
        return AssistantNavigationTarget(destination: id)
    }

    var resolvedDurationSeconds: Double? {
        guard durationHours != nil || durationMinutes != nil || durationSeconds != nil else { return nil }
        let seconds = (durationHours ?? 0) * 3_600 + (durationMinutes ?? 0) * 60 + (durationSeconds ?? 0)
        guard [durationHours, durationMinutes, durationSeconds].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }),
              seconds.isFinite, (1...2_592_000).contains(seconds) else { return nil }
        return seconds
    }

    var distanceMeters: Double? {
        guard let distanceValue, distanceValue.isFinite, (0...1_000_000).contains(distanceValue) else { return nil }
        switch distanceUnit {
        case "meters": return distanceValue
        case "kilometers": return distanceValue * 1_000
        case "miles": return distanceValue * 1_609.344
        default: return nil
        }
    }

    var diagnosticOperation: String {
        switch kind {
        case "manualWorkout", "prepareActivity", "navigate", "conversation", "cancelManualWorkout": return kind
        default: return "unknown"
        }
    }

    enum ValidationFailure: String, Error {
        case sport, duration, distance, pace, dateOrTime = "date_or_time"
        case conflictingGoals = "conflicting_goals", destination, operation
    }

    func updateResult(_ original: ManualWorkoutDraft) -> Result<ManualWorkoutDraft, ValidationFailure> {
        var draft = original
        if let sport {
            guard let type = SportType(rawValue: sport) else { return .failure(.sport) }
            draft.activityType = type.activityType
        }
        if durationHours != nil || durationMinutes != nil || durationSeconds != nil {
            guard let seconds = resolvedDurationSeconds else { return .failure(.duration) }
            draft.durationMinutes = max(1, Int((seconds / 60).rounded()))
        }
        if distanceValue != nil {
            guard let meters = distanceMeters else { return .failure(.distance) }
            draft.distanceMeters = meters
        }
        if draft.durationMinutes == nil, let distance = draft.distanceMeters,
           paceMinutes != nil || paceSeconds != nil {
            let pace = (paceMinutes ?? 0) * 60 + (paceSeconds ?? 0)
            guard [paceMinutes, paceSeconds].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }),
                  pace.isFinite, (1...36_000).contains(pace),
                  paceUnit == "kilometers" || paceUnit == "miles" else { return .failure(.pace) }
            let seconds = distance / (paceUnit == "miles" ? 1_609.344 : 1_000) * pace
            guard seconds.isFinite, (1...2_592_000).contains(seconds) else { return .failure(.pace) }
            draft.durationMinutes = max(1, Int((seconds / 60).rounded()))
        }
        if localDate != nil || localTime != nil {
            guard let date = resolvedDate(relativeTo: draft.startedAt) else { return .failure(.dateOrTime) }
            draft.startedAt = date
        }
        if let isIndoor { draft.isIndoor = isIndoor }
        return .success(draft)
    }

    func preparationResult(unitSystem: MeasurementUnitSystem) -> Result<SessionIntent, ValidationFailure> {
        guard kind == "prepareActivity", let sport, let type = SportType(rawValue: sport) else { return .failure(.sport) }
        let goal: ActivityGoal
        if distanceValue != nil {
            guard let meters = distanceMeters, (100...200_000).contains(meters) else { return .failure(.distance) }
            // The setup UI supports one goal. Ask rather than silently dropping a second one.
            guard durationHours == nil, durationMinutes == nil, durationSeconds == nil else { return .failure(.conflictingGoals) }
            goal = .distanceMeters(meters)
        } else if durationHours != nil || durationMinutes != nil || durationSeconds != nil {
            guard let seconds = resolvedDurationSeconds, (60...43_200).contains(seconds) else { return .failure(.duration) }
            goal = .timeSeconds(Int(seconds.rounded()))
        } else {
            guard distanceUnit == nil else { return .failure(.distance) }
            goal = .freestyle
        }
        return .success(SessionIntent(
            id: "assistant-\(UUID().uuidString)", sport: type, title: type.displayName,
            detail: String(format: String(localized: "activity.freestyle.detail.format", defaultValue: "%@ • no preset target"), locale: .autoupdatingCurrent, type.displayName),
            guideLine: String(localized: "activity.freestyle.companion", defaultValue: "Start easy and settle into a comfortable rhythm."),
            startLabel: String(localized: "Start activity")
        ).replacingGoal(goal, unitSystem: unitSystem))
    }

    func validationFailure(manualDraft: ManualWorkoutDraft?) -> ValidationFailure? {
        switch kind {
        case "manualWorkout":
            if case .failure(let reason) = updateResult(manualDraft ?? ManualWorkoutDraft()) { return reason }
        case "prepareActivity":
            if clarificationText == nil,
               case .failure(let reason) = preparationResult(unitSystem: .metric) { return reason }
        case "navigate":
            if clarificationText == nil, navigationTarget == nil { return .destination }
        case "conversation", "cancelManualWorkout": break
        default: return .operation
        }
        return nil
    }

    private func resolvedDate(relativeTo original: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: original)
        if let localDate {
            guard localDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
            let parts = localDate.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, (1900...2200).contains(parts[0]), (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
            components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
        }
        if let localTime {
            guard localTime.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil else { return nil }
            let parts = localTime.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
            components.hour = parts[0]; components.minute = parts[1]; components.second = 0
        }
        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard roundTrip.year == components.year, roundTrip.month == components.month, roundTrip.day == components.day,
              roundTrip.hour == components.hour, roundTrip.minute == components.minute else { return nil }
        return date
    }
}

struct LocalAssistantInterpretRequest: Encodable {
    let prompt: String
    let context: String
    let messages: [CompanionPriorMessageDTO]
}

struct LocalAssistantInterpretResult {
    let interpretation: LocalAssistantInterpretation?
    let source: String
    let result: String
}

@MainActor
enum LocalIntelligence {
    private static let logger = Logger(subsystem: "com.plainstride", category: "LocalIntelligence")

    private static let routingInstructions = """
    The JSON prompt field is the latest user message. The context and messages fields are reference only.
    Route ONLY that latest message. Never treat reference context or history as a new command.
    Choose manualWorkout for a request to log an already completed workout, or a follow-up supplying a field of
    the supplied pending manual draft (for example Swim or one hour). Missing workout fields do not make routing ambiguous.
    Choose prepareActivity only for an explicit request to prepare a NEW workout.
    Choose navigate for an explicit request to open one allowed destination.
    Choose cancelManualWorkout only when the person asks to cancel the pending workout draft.
    All questions, negated/hypothetical/quoted commands, requests to change today's existing workout, and plan
    reviews are conversation. For conversation, choose the appropriate capability and task; the server owns plan changes.
    Examples: Make today's workout easier -> conversation(plan, adapt_today).
    Log a workout I already completed -> manualWorkout. With a pending draft, Swim -> manualWorkout.
    With a pending draft, Swim one hour -> manualWorkout. Start a one hour swim -> prepareActivity.
    Only use clarification for truly ambiguous intent, not for missing workout details. Use the app language.
    Never execute an action or claim that an action succeeded.
    """

    private static let workoutInstructions = """
    The JSON prompt field is the latest user message. The context and messages fields are reference only.
    Extract workout fields ONLY from prompt. The operation is already chosen; do not classify again.
    Use notMentioned for EVERY field not explicitly supplied or unambiguously corrected in that message.
    Never copy values from history, the current instant, or the pending draft into missing fields.
    Examples: Swim -> sport swim; every other field notMentioned.
    One hour -> duration components(hours:1, minutes:0, seconds:0); every other field notMentioned.
    Swim one hour -> sport swim and duration components(1,0,0); every other field notMentioned.
    One hour thirty minutes -> duration components(1,30,0). One minute thirty seconds -> components(0,1,30).
    Only when a duration is mentioned, unused components are zero. Otherwise the whole duration is notMentioned.
    Zero minutes is an explicit quantity, not notMentioned. Keep explicitly supplied values for app validation.
    Preserve distance and pace units; do not convert units or compute duration from pace.
    A pace without a per-unit uses the stated distance unit or the measurement preference.
    Resolve an explicitly supplied relative date against the local calendar dates in context; otherwise date notMentioned.
    Use clock time only if explicitly supplied. Indoor/outdoor must also be explicit.
    Clarification is notNeeded for clear input, including input missing required fields: the app asks for missing fields.
    Only ask a brief clarification for genuinely ambiguous details; write it in the app language.
    """

    static func interpret(_ request: LocalAssistantInterpretRequest, manualDraft: ManualWorkoutDraft? = nil) async -> LocalAssistantInterpretResult {
        guard request.prompt.count <= 4_000 else { return .init(interpretation: nil, source: "none", result: "invalid_input") }
        guard !Task.isCancelled else { return .init(interpretation: nil, source: "none", result: "cancelled") }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability, model.supportsLocale(AppLanguage.speechLocale) {
                do {
                    let data = try JSONEncoder().encode(request)
                    let prompt = String(decoding: data, as: UTF8.self)
                    let route = try await generate(prompt: prompt, instructions: routingInstructions,
                        generating: GeneratedAssistantRoute.self, maximumTokens: 200)
                    var value = route.value
                    if value.kind == "manualWorkout" || value.kind == "prepareActivity" {
                        let fields = try await generate(prompt: prompt, instructions: workoutInstructions,
                            generating: GeneratedWorkoutFields.self, maximumTokens: 450)
                        fields.apply(to: &value)
                    }
                    try Task.checkCancellation()
                    if let failure = value.validationFailure(manualDraft: manualDraft) {
                        logger.warning("Assistant interpretation rejected provider=apple operation=\(value.diagnosticOperation, privacy: .public) field=\(failure.rawValue, privacy: .public); using server")
                    } else {
                        return .init(interpretation: value, source: "apple", result: "success")
                    }
                } catch is CancellationError {
                    return .init(interpretation: nil, source: "apple", result: "cancelled")
                } catch {
                    if Task.isCancelled { return .init(interpretation: nil, source: "apple", result: "cancelled") }
                    // Do not log error descriptions: model errors may contain prompt or response content.
                    logger.warning("Assistant interpretation failed provider=apple error_type=\(String(reflecting: type(of: error)), privacy: .public)")
                }
            } else {
                logger.notice("Assistant interpretation unavailable provider=apple; using server")
            }
        }
        #endif
        guard !Task.isCancelled else { return .init(interpretation: nil, source: "none", result: "cancelled") }
        do {
            let interpretation = try await APIClient.shared.interpretAssistant(request)
            try Task.checkCancellation()
            if let failure = interpretation.validationFailure(manualDraft: manualDraft) {
                logger.warning("Assistant interpretation rejected provider=server operation=\(interpretation.diagnosticOperation, privacy: .public) field=\(failure.rawValue, privacy: .public)")
                return .init(interpretation: nil, source: "server", result: "invalid_output")
            }
            return .init(interpretation: interpretation, source: "server", result: "success")
        } catch is CancellationError {
            return .init(interpretation: nil, source: "server", result: "cancelled")
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                return .init(interpretation: nil, source: "server", result: "cancelled")
            }
            let code = (error as NSError).code
            let status: Int
            if let apiError = error as? APIError, case .http(let statusCode, _, _) = apiError { status = statusCode } else { status = 0 }
            logger.warning("Assistant interpretation failed provider=server error_type=\(String(reflecting: type(of: error)), privacy: .public) code=\(code) http_status=\(status)")
            return .init(interpretation: nil, source: "server", result: "unavailable")
        }
    }

    static func generateReply(prompt: String, capability: AssistantCapability, context: AssistantContext,
                              messages: [AssistantChatAPIPriorMessage]) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability,
                  SystemLanguageModel.default.supportsLocale(AppLanguage.speechLocale) else { return nil }
            do {
                let reply = try await generate(prompt: """
                    Capability: \(capability.rawValue)
                    Current screen: \(context.currentScreen ?? "unknown"); recording: \(context.isRecordingActive)
                    Saved activities: \(context.activityCount); weekly distance km: \(context.weeklyDistanceKilometers)
                    Goal: \(context.currentGoalSummary ?? "none")
                    Feature catalog:
                    \(AssistantDestinationRegistry.productContext)
                    Recent conversation:
                    \(messages.suffix(4).map { "\($0.role): \(String($0.text.prefix(400)))" }.joined(separator: "\n"))
                    User request: \(String(prompt.prefix(4_000)))
                    """, instructions: """
                    You are Plainstride's concise in-app assistant. Answer using only supplied facts and the current feature catalog.
                    Do not invent screens, facts, diagnoses, training plans, or capabilities. Ask when information is missing.
                    Never claim that an activity was saved, started, or changed; actions require explicit app execution.
                    Avoid internal implementation details. Answer in two to four short paragraphs.
                    """, generating: GeneratedAssistantReply.self, maximumTokens: 250)
                try Task.checkCancellation()
                return reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch is CancellationError {
                return nil
            } catch {
                if Task.isCancelled { return nil }
                logger.warning("Assistant reply failed provider=apple error_type=\(String(reflecting: type(of: error)), privacy: .public)")
            }
        }
        #endif
        return nil
    }

    #if canImport(FoundationModels)
    private enum GenerationFailure: Error { case deadlineExceeded }

    @available(iOS 26.0, *)
    private static func generate<Value: Generable & Sendable>(prompt: String, instructions: String,
                                                             generating: Value.Type, maximumTokens: Int) async throws -> Value {
        let session = LanguageModelSession(model: .default, instructions: instructions
            + "\nThe person's locale is \(AppLanguage.speechLocale.identifier). You MUST respond in \(AppLanguage.currentIdentifier).")
        let generation = Task { @MainActor in
            do {
                let response = try await session.respond(to: prompt, generating: generating,
                    options: GenerationOptions(sampling: .greedy, maximumResponseTokens: maximumTokens))
                try Task.checkCancellation()
                return response.content
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
        }
        let deadline = Task { @MainActor in
            // Cancelling the deadline on completion is expected control flow.
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            generation.cancel()
        }
        defer { deadline.cancel() }
        do {
            return try await withTaskCancellationHandler {
                try await generation.value
            } onCancel: {
                generation.cancel()
            }
        } catch is CancellationError {
            if Task.isCancelled { throw CancellationError() }
            throw GenerationFailure.deadlineExceeded
        }
    }
    #endif

}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct GeneratedAssistantRoute: Sendable {
    var intent: Intent

    @Generable enum Intent: Sendable {
        case manualWorkout
        case prepareActivity
        case navigate(destination: Destination)
        case conversation(capability: Capability, task: TaskKind)
        case cancelManualWorkout
        case clarify(question: String)
    }
    @Generable enum Capability: String, Sendable { case discover, navigate, support, brainstorm, plan }
    @Generable enum TaskKind: String, Sendable {
        case answer_training_question, adapt_today, prepare_week, post_run_reflection, live_guidance, inspect_memory, product_help
    }
    @Generable enum Destination: String, Sendable {
        case social, today, me, settings, appearance, settingsAppleMusic, settingsAppleHealth, guideSettings, activityHistory
    }

    var value: LocalAssistantInterpretation {
        var value = LocalAssistantInterpretation(kind: "conversation", capability: "discover", task: "product_help")
        switch intent {
        case .manualWorkout: value.kind = "manualWorkout"; value.capability = "plan"
        case .prepareActivity: value.kind = "prepareActivity"; value.capability = "plan"
        case .navigate(let destination):
            value.kind = "navigate"; value.capability = "navigate"; value.destination = destination.rawValue
        case .conversation(let capability, let task):
            value.capability = capability.rawValue; value.task = task.rawValue
        case .cancelManualWorkout: value.kind = "cancelManualWorkout"; value.capability = "plan"
        case .clarify(let question): value.clarification = question
        }
        return value
    }
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedWorkoutFields: Sendable {
    @Guide(description: "Only a sport explicitly supplied in the latest message; otherwise notMentioned.")
    var sport: Sport
    @Guide(description: "Only a duration explicitly supplied in the latest message; otherwise notMentioned.")
    var duration: Duration
    var distance: Distance
    var pace: Pace
    var date: WorkoutDate
    var time: WorkoutTime
    var setting: Setting
    var clarification: Clarification

    @Generable enum Sport: String, Sendable { case notMentioned, run, bike, walk, hike, swim, strength, mobility }
    @Generable enum Duration: Sendable {
        case notMentioned
        case components(hours: Double, minutes: Double, seconds: Double)
    }
    @Generable enum Distance: Sendable {
        case notMentioned
        case meters(Double)
        case kilometers(Double)
        case miles(Double)
    }
    @Generable enum Pace: Sendable {
        case notMentioned
        case perKilometer(minutes: Double, seconds: Double)
        case perMile(minutes: Double, seconds: Double)
    }
    @Generable enum WorkoutDate: Sendable {
        case notMentioned
        case calendarDate(year: Int, month: Int, day: Int)
    }
    @Generable enum WorkoutTime: Sendable {
        case notMentioned
        case clock(hour: Int, minute: Int)
    }
    @Generable enum Setting: Sendable { case notMentioned, indoor, outdoor }
    @Generable enum Clarification: Sendable { case notNeeded, question(String) }

    func apply(to value: inout LocalAssistantInterpretation) {
        if sport != .notMentioned { value.sport = sport.rawValue }
        switch duration {
        case .notMentioned: break
        case .components(let hours, let minutes, let seconds):
            value.durationHours = hours; value.durationMinutes = minutes; value.durationSeconds = seconds
        }
        switch distance {
        case .notMentioned: break
        case .meters(let amount): value.distanceValue = amount; value.distanceUnit = "meters"
        case .kilometers(let amount): value.distanceValue = amount; value.distanceUnit = "kilometers"
        case .miles(let amount): value.distanceValue = amount; value.distanceUnit = "miles"
        }
        switch pace {
        case .notMentioned: break
        case .perKilometer(let minutes, let seconds): value.paceMinutes = minutes; value.paceSeconds = seconds; value.paceUnit = "kilometers"
        case .perMile(let minutes, let seconds): value.paceMinutes = minutes; value.paceSeconds = seconds; value.paceUnit = "miles"
        }
        if case .calendarDate(let year, let month, let day) = date {
            value.localDate = (1900...2200).contains(year) && (1...12).contains(month) && (1...31).contains(day)
                ? String(format: "%04d-%02d-%02d", year, month, day) : "invalid"
        }
        if case .clock(let hour, let minute) = time {
            value.localTime = (0...23).contains(hour) && (0...59).contains(minute)
                ? String(format: "%02d:%02d", hour, minute) : "invalid"
        }
        switch setting {
        case .notMentioned: break
        case .indoor: value.isIndoor = true
        case .outdoor: value.isIndoor = false
        }
        if case .question(let question) = clarification { value.clarification = question }
    }
}
@available(iOS 26.0, *)
@Generable
private struct GeneratedAssistantReply: Sendable {
    @Guide(description: "A concise reply in the requested app language using only supplied facts.")
    var text: String
}
#endif
