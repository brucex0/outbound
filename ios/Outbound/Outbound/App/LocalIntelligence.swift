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
    Classify the user's message into one category. Do not answer or extract workout fields.
    beginManualWorkout: asking to log a completed workout without supplying any workout facts.
    manualWorkout: supplying facts about a completed workout, or answering the pending completed-workout form.
    prepareActivity: an explicit request to start/begin/prepare a new activity.
    navigate: an explicit request to open an app page.
    cancelManualWorkout: an explicit request to cancel the pending completed-workout form.
    conversation: questions, negated/hypothetical/quoted commands, and changes to existing workouts or plans.
    A pending completed-workout form makes short sport/duration replies manualWorkout.
    A start request is prepareActivity, never manualWorkout. A negated command is conversation.
    """

    static func interpret(_ request: LocalAssistantInterpretRequest, manualDraft: ManualWorkoutDraft? = nil) async -> LocalAssistantInterpretResult {
        guard request.prompt.count <= 4_000 else { return .init(interpretation: nil, source: "none", result: "invalid_input") }
        guard !Task.isCancelled else { return .init(interpretation: nil, source: "none", result: "cancelled") }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability, model.supportsLocale(AppLanguage.speechLocale) {
                do {
                    let route = try await generate(prompt: """
                        Pending completed-workout form: \(manualDraft == nil ? "no" : "yes").
                        USER MESSAGE: \(request.prompt)
                        """, instructions: routingInstructions,
                        generating: GeneratedAssistantRoute.self, maximumTokens: 80)
                    var value = route.value
                    if (value.kind == "manualWorkout" && route.kind != .beginManualWorkout) || value.kind == "prepareActivity" {
                        let sport = try await generate(prompt: "Which specific sport, if any, is named in this message?\nMessage: \(request.prompt)",
                            instructions: "Identify the explicitly named sport only, including sport-specific verbs in the input language. Do not infer a sport from workout/activity or a duration.",
                            generating: GeneratedWorkoutSport.self, maximumTokens: 150)
                        if sport.sport != .none { value.sport = sport.sport.rawValue }
                        let durationPhrase = try await sourcePhrase(in: request.prompt, describing: "an amount of time")
                        if grounded(durationPhrase, in: request.prompt) {
                            let duration = try await generate(prompt: durationPhrase,
                                instructions: "Extract the stated duration as hour, minute and second components. Do not convert units. Unused components are zero.",
                                generating: GeneratedWorkoutDuration.self, maximumTokens: 100)
                            let isWholeMessage = durationPhrase.caseInsensitiveCompare(request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
                            var acceptDuration = !isWholeMessage
                            if !acceptDuration { acceptDuration = try await confirmsFact(in: durationPhrase, question: "express an amount of time") }
                            if acceptDuration {
                                value.durationHours = duration.hours; value.durationMinutes = duration.minutes; value.durationSeconds = duration.seconds
                            }
                        }
                        var presence = GeneratedWorkoutPresence()
                        let checks: [(WritableKeyPath<GeneratedWorkoutPresence, Bool>, String, String)] = [
                            (\.distance, "a distance quantity", "express a distance quantity"),
                            (\.pace, "a pace", "express a pace as time per distance"),
                            (\.date, "a calendar day", "specify a calendar day"),
                            (\.time, "a clock time of day", "specify a clock time of day rather than an elapsed duration"),
                            (\.setting, "an indoor or outdoor setting", "mean indoors or outdoors")
                        ]
                        for (field, description, question) in checks {
                            let phrase = try await sourcePhrase(in: request.prompt, describing: description)
                            // A whole sport request is not a citation for an independent optional fact.
                            if sport.sport != .none,
                               phrase.caseInsensitiveCompare(request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
                                continue
                            }
                            if grounded(phrase, in: request.prompt) {
                                presence[keyPath: field] = try await confirmsFact(in: phrase, question: question)
                            }
                        }
                        if presence.hasAdditionalFields {
                            let details = try await generate(prompt: "Reference context: \(request.context)\nUSER MESSAGE: \(request.prompt)", instructions: """
                                Extract only additional workout facts explicitly supplied in USER MESSAGE.
                                For every category, copy its exact source phrase from that message; use an empty phrase when absent.
                                Never copy reference context into source phrases. Never infer defaults.
                                Keep distance and pace units. Resolve explicitly stated relative dates against reference calendar dates.
                                Unused numeric values may be zero; they are ignored when the corresponding source phrase is empty.
                                Clarification is notNeeded for clear input or missing fields. Ask only about genuinely ambiguous input.
                                """, generating: GeneratedWorkoutDetails.self, maximumTokens: 650)
                            details.apply(to: &value, latestMessage: request.prompt, presence: presence)
                            // A duration cited from within the pace phrase is not an independent elapsed goal.
                            if presence.pace, grounded(details.pacePhrase, in: request.prompt),
                               grounded(durationPhrase, in: details.pacePhrase) {
                                value.durationHours = nil; value.durationMinutes = nil; value.durationSeconds = nil
                            }
                        }
                    } else if value.kind == "navigate" {
                        let target = try await generate(prompt: """
                            Allowed app destinations:
                            \(AssistantDestinationRegistry.productContext)
                            User message: \(request.prompt)
                            """, instructions: "Choose only the app destination explicitly requested. Use unknown if ambiguous.",
                            generating: GeneratedNavigationTarget.self, maximumTokens: 80)
                        value.destination = target.destination == .unknown ? nil : target.destination.rawValue
                    } else if value.kind == "conversation" {
                        let routing = try await generate(prompt: request.prompt, instructions: """
                            Choose a capability and task for this Plainstride conversation.
                            Changes or questions about today's existing workout: plan, adapt_today.
                            Weekly plans and plan reviews: plan, prepare_week.
                            App features/settings/support: discover or support, product_help.
                            General training questions: brainstorm, answer_training_question.
                            """, generating: GeneratedConversationRoute.self, maximumTokens: 100)
                        value.capability = routing.capability.rawValue
                        value.task = routing.task.rawValue
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
    private enum GenerationFailure: Error { case deadlineExceeded, invalidConfirmation }

    @available(iOS 26.0, *)
    private static func generate<Value: Generable & Sendable>(prompt: String, instructions: String,
                                                             generating: Value.Type, maximumTokens: Int) async throws -> Value {
        let session = LanguageModelSession(model: .default, instructions: instructions
            + "\nThe person's locale is \(AppLanguage.speechLocale.identifier). You MUST respond in \(AppLanguage.currentIdentifier).")
        return try await withGenerationDeadline {
            let response = try await session.respond(to: prompt, generating: generating,
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: maximumTokens))
            return response.content
        }
    }

    @available(iOS 26.0, *)
    private static func sourcePhrase(in message: String, describing fact: String) async throws -> String {
        // Text-span extraction avoids forcing absent facts into a numeric schema.
        let session = LanguageModelSession(instructions: "Extract text spans only. Copy original words exactly. Output NONE if no matching span exists.")
        return try await withGenerationDeadline {
            let response = try await session.respond(to: "Copy the words expressing \(fact) from this text.\nText: \(message)",
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 150))
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @available(iOS 26.0, *)
    private static func confirmsFact(in phrase: String, question: String) async throws -> Bool {
        let session = LanguageModelSession(instructions: "Answer the question with YES or NO only.")
        let reply = try await withGenerationDeadline {
            try await session.respond(to: "Does the phrase '\(phrase)' \(question)?",
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 20))
        }
        switch reply.content.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).uppercased() {
        case "YES": return true
        case "NO": return false
        default: throw GenerationFailure.invalidConfirmation
        }
    }

    @available(iOS 26.0, *)
    private static func withGenerationDeadline<Value: Sendable>(_ operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        let generation = Task { @MainActor in
            do {
                let value = try await operation()
                try Task.checkCancellation()
                return value
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
    @Guide(description: "The category of the user's current message, considering whether a completed-workout form is pending.")
    var kind: Kind
    @Generable enum Kind: String, Sendable { case beginManualWorkout, manualWorkout, prepareActivity, navigate, cancelManualWorkout, conversation }
    var value: LocalAssistantInterpretation {
        let operation = kind == .beginManualWorkout ? "manualWorkout" : kind.rawValue
        let capability = kind == .navigate ? "navigate" : (kind == .conversation ? "discover" : "plan")
        return .init(kind: operation, capability: capability, task: "product_help")
    }
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedConversationRoute: Sendable {
    var capability: Capability
    var task: TaskKind
    @Generable enum Capability: String, Sendable { case discover, navigate, support, brainstorm, plan }
    @Generable enum TaskKind: String, Sendable {
        case answer_training_question, adapt_today, prepare_week, post_run_reflection, live_guidance, inspect_memory, product_help
    }
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedNavigationTarget: Sendable {
    var destination: Destination
    @Generable enum Destination: String, Sendable {
        case unknown, social, today, me, settings, appearance, settingsAppleMusic, settingsAppleHealth, guideSettings, activityHistory
    }
}

/// Checks a model-provided citation against the input; it does not interpret user language.
private func grounded(_ phrase: String, in message: String) -> Bool {
    let quote = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
    return !quote.isEmpty && message.range(of: quote, options: .caseInsensitive) != nil
}

@available(iOS 26.0, *)
private struct GeneratedWorkoutPresence: Sendable {
    var distance = false
    var pace = false
    var date = false
    var time = false
    var setting = false
    var hasAdditionalFields: Bool { distance || pace || date || time || setting }
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedWorkoutSport: Sendable {
    @Guide(description: "Explain whether the message names a specific sport. Generic workout/activity and elapsed durations do not name a sport.")
    var analysis: String
    @Guide(description: "The explicitly named sport, or none when absent.")
    var sport: Sport
    @Generable enum Sport: String, Sendable { case none, swim, run, bike, walk, hike, strength, mobility }
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedWorkoutDuration: Sendable {
    var hours: Double
    var minutes: Double
    var seconds: Double
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedWorkoutDetails: Sendable {
    var distancePhrase: String
    var distanceAmount: Double
    var distanceUnit: DistanceUnit
    var pacePhrase: String
    var paceMinutes: Double
    var paceSeconds: Double
    var paceUnit: PaceUnit
    var datePhrase: String
    var date: WorkoutDate
    var timePhrase: String
    var time: WorkoutTime
    var settingPhrase: String
    var isIndoor: Bool
    var clarification: Clarification

    @Generable enum DistanceUnit: String, Sendable { case meters, kilometers, miles }
    @Generable enum PaceUnit: String, Sendable { case kilometers, miles }
    @Generable struct WorkoutDate: Sendable { var year: Int; var month: Int; var day: Int }
    @Generable struct WorkoutTime: Sendable { var hour: Int; var minute: Int }
    @Generable enum Clarification: Sendable { case notNeeded, question(String) }

    func apply(to value: inout LocalAssistantInterpretation, latestMessage: String, presence: GeneratedWorkoutPresence) {
        if presence.distance, grounded(distancePhrase, in: latestMessage) { value.distanceValue = distanceAmount; value.distanceUnit = distanceUnit.rawValue }
        if presence.pace, grounded(pacePhrase, in: latestMessage) { value.paceMinutes = paceMinutes; value.paceSeconds = paceSeconds; value.paceUnit = paceUnit.rawValue }
        if presence.date, grounded(datePhrase, in: latestMessage) {
            value.localDate = (1900...2200).contains(date.year) && (1...12).contains(date.month) && (1...31).contains(date.day)
                ? String(format: "%04d-%02d-%02d", date.year, date.month, date.day) : "invalid"
        }
        if presence.time, grounded(timePhrase, in: latestMessage) {
            value.localTime = (0...23).contains(time.hour) && (0...59).contains(time.minute)
                ? String(format: "%02d:%02d", time.hour, time.minute) : "invalid"
        }
        if presence.setting, grounded(settingPhrase, in: latestMessage) { value.isIndoor = isIndoor }
        // Required-field questions are owned by the app, not inferred from optional details.
    }
}
@available(iOS 26.0, *)
@Generable
private struct GeneratedAssistantReply: Sendable {
    @Guide(description: "A concise reply in the requested app language using only supplied facts.")
    var text: String
}
#endif
