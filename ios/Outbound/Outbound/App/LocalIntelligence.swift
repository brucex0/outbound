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

    func updating(_ original: ManualWorkoutDraft) -> ManualWorkoutDraft? {
        var draft = original
        if let sport {
            guard let type = SportType(rawValue: sport) else { return nil }
            draft.activityType = type.activityType
        }
        if durationHours != nil || durationMinutes != nil || durationSeconds != nil {
            guard let seconds = resolvedDurationSeconds else { return nil }
            draft.durationMinutes = max(1, Int((seconds / 60).rounded()))
        }
        if distanceValue != nil {
            guard let meters = distanceMeters else { return nil }
            draft.distanceMeters = meters
        }
        if draft.durationMinutes == nil, let distance = draft.distanceMeters,
           paceMinutes != nil || paceSeconds != nil {
            let pace = (paceMinutes ?? 0) * 60 + (paceSeconds ?? 0)
            guard [paceMinutes, paceSeconds].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }),
                  pace.isFinite, (1...36_000).contains(pace),
                  paceUnit == "kilometers" || paceUnit == "miles" else { return nil }
            let seconds = distance / (paceUnit == "miles" ? 1_609.344 : 1_000) * pace
            guard seconds.isFinite, (1...2_592_000).contains(seconds) else { return nil }
            draft.durationMinutes = max(1, Int((seconds / 60).rounded()))
        }
        if localDate != nil || localTime != nil {
            guard let date = resolvedDate(relativeTo: draft.startedAt) else { return nil }
            draft.startedAt = date
        }
        if let isIndoor { draft.isIndoor = isIndoor }
        return draft
    }

    func preparedActivity(unitSystem: MeasurementUnitSystem) -> SessionIntent? {
        guard kind == "prepareActivity", let sport, let type = SportType(rawValue: sport) else { return nil }
        let goal: ActivityGoal
        if distanceValue != nil {
            guard let meters = distanceMeters, (100...200_000).contains(meters) else { return nil }
            // The setup UI supports one goal. Ask rather than silently dropping a second one.
            guard durationHours == nil, durationMinutes == nil, durationSeconds == nil else { return nil }
            goal = .distanceMeters(meters)
        } else if durationHours != nil || durationMinutes != nil || durationSeconds != nil {
            guard let seconds = resolvedDurationSeconds, (60...43_200).contains(seconds) else { return nil }
            goal = .timeSeconds(Int(seconds.rounded()))
        } else {
            guard distanceUnit == nil else { return nil }
            goal = .freestyle
        }
        return SessionIntent(
            id: "assistant-\(UUID().uuidString)", sport: type, title: type.displayName,
            detail: String(format: String(localized: "activity.freestyle.detail.format", defaultValue: "%@ • no preset target"), locale: .autoupdatingCurrent, type.displayName),
            guideLine: String(localized: "activity.freestyle.companion", defaultValue: "Start easy and settle into a comfortable rhythm."),
            startLabel: String(localized: "Start activity")
        ).replacingGoal(goal, unitSystem: unitSystem)
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

    static let instructions = """
    Interpret one Plainstride assistant turn into the supplied schema. Never execute actions or claim success.
    Understand the user's language, number words, negation, corrections, and follow-up references.
    kind: manualWorkout to log an already completed activity or continue the supplied manual draft;
    prepareActivity only for an explicit request to prepare a NEW activity, not past activity or a question;
    navigate only for an explicit request to open an allowed destination; cancelManualWorkout only to cancel the draft;
    otherwise conversation. Questions, negated commands, hypothetical commands, and quoted commands are not requests to start or log an activity.
    Capability: discover, navigate, support, brainstorm, plan. Task: answer_training_question, adapt_today,
    prepare_week, post_run_reflection, live_guidance, inspect_memory, product_help.
    Requests to change today's existing workout or review a training plan are conversation; the server owns these mutations.
    Extract only quantities, dates, and indoor/outdoor settings explicitly supplied or unambiguously corrected.
    Extract new or corrected values only from the latest prompt; history is reference context, not new input.
    Missing values MUST be null. Do not fill unspecified values from typical workouts or prior drafts.
    Preserve duration components: one hour thirty minutes = durationHours 1, durationMinutes 30.
    Extract distanceValue and distanceUnit (meters/kilometers/miles); do not convert units or compute pace-derived duration.
    Pace uses paceMinutes and paceSeconds per paceUnit (kilometers/miles). An unspecified pace unit uses the stated distance unit or measurement preference. Resolve relative dates using today's date and time zone.
    localDate is YYYY-MM-DD, localTime is HH:mm, both in the person's time zone. Leave unspecified time null.
    Sports: run, bike, walk, hike, swim, strength, mobility. Destination must be an ID from the supplied catalog.
    If ambiguous, use conversation (or manualWorkout with missing fields for an ongoing log) and a short clarification.
    clarification must be in the requested app language. Never diagnose health issues or invent workout/plan data.
    """

    static func interpret(_ request: LocalAssistantInterpretRequest) async -> LocalAssistantInterpretResult {
        guard request.prompt.count <= 4_000 else { return .init(interpretation: nil, source: "none", result: "invalid_input") }
        guard !Task.isCancelled else { return .init(interpretation: nil, source: "none", result: "cancelled") }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability, model.supportsLocale(AppLanguage.speechLocale) {
                do {
                    let data = try JSONEncoder().encode(request)
                    let value = try await generate(
                        prompt: String(decoding: data, as: UTF8.self), instructions: instructions,
                        generating: GeneratedAssistantInterpretation.self, maximumTokens: 600
                    ).value
                    try Task.checkCancellation()
                    return .init(interpretation: value, source: "apple", result: "success")
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
private struct GeneratedAssistantInterpretation: Sendable {
    var kind: Kind
    var capability: Capability
    var task: TaskKind
    var destination: Destination?
    var sport: Sport?
    @Guide(description: "Hours component explicitly supplied in the latest turn; nil if missing.")
    var durationHours: Double?
    @Guide(description: "Minutes component, excluding any hours component; nil if missing.")
    var durationMinutes: Double?
    var durationSeconds: Double?
    var distanceValue: Double?
    var distanceUnit: DistanceUnit?
    var paceMinutes: Double?
    var paceSeconds: Double?
    var paceUnit: PaceUnit?
    var localDate: String?
    var localTime: String?
    var isIndoor: Bool?
    @Guide(description: "A brief question only for ambiguous input; nil for clear input or routine missing draft fields.")
    var clarification: String?

    @Generable enum Kind: String, Sendable { case manualWorkout, prepareActivity, navigate, conversation, cancelManualWorkout }
    @Generable enum Capability: String, Sendable { case discover, navigate, support, brainstorm, plan }
    @Generable enum TaskKind: String, Sendable {
        case answer_training_question, adapt_today, prepare_week, post_run_reflection, live_guidance, inspect_memory, product_help
    }
    @Generable enum Sport: String, Sendable { case run, bike, walk, hike, swim, strength, mobility }
    @Generable enum DistanceUnit: String, Sendable { case meters, kilometers, miles }
    @Generable enum PaceUnit: String, Sendable { case kilometers, miles }
    @Generable enum Destination: String, Sendable {
        case social, today, me, settings, appearance, settingsAppleMusic, settingsAppleHealth, guideSettings, activityHistory
    }

    var value: LocalAssistantInterpretation {
        .init(kind: kind.rawValue, capability: capability.rawValue, task: task.rawValue,
              destination: destination?.rawValue, sport: sport?.rawValue,
              durationHours: durationHours, durationMinutes: durationMinutes, durationSeconds: durationSeconds,
              distanceValue: distanceValue, distanceUnit: distanceUnit?.rawValue,
              paceMinutes: paceMinutes, paceSeconds: paceSeconds, paceUnit: paceUnit?.rawValue,
              localDate: localDate, localTime: localTime, isIndoor: isIndoor, clarification: clarification)
    }
}
@available(iOS 26.0, *)
@Generable
private struct GeneratedAssistantReply: Sendable {
    @Guide(description: "A concise reply in the requested app language using only supplied facts.")
    var text: String
}
#endif
