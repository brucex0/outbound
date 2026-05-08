#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class AppleFoundationModelSessionAnalysisProvider: SessionAnalysisProvider {
    let identifier = "apple-foundation-model-session-analyzer"
    let displayName = "Apple Foundation Model"

    private let model: SystemLanguageModel
    private var session: LanguageModelSession?
    private var activeSessionKey: String?

    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    var isAvailable: Bool {
        guard case .available = model.availability else { return false }
        return true
    }

    func beginSession(profile: CoachProfile?, persona: CoachPersona?) {
        guard isAvailable else {
            session = nil
            activeSessionKey = nil
            return
        }

        activeSessionKey = Self.sessionKey(profile: profile, persona: persona)
        let instructions = Self.instructions(for: profile, persona: persona)
        session = LanguageModelSession(model: model) {
            instructions
        }
    }

    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult {
        guard isAvailable else {
            throw AppleFoundationModelSessionAnalysisError.unavailable(model.availability)
        }

        if session == nil || activeSessionKey != Self.sessionKey(profile: request.profile, persona: request.persona) {
            beginSession(profile: request.profile, persona: request.persona)
        }

        guard let session else {
            throw AppleFoundationModelSessionAnalysisError.sessionUnavailable
        }

        let response = try await session.respond(
            to: Self.prompt(for: request),
            generating: AppleSessionAnalysisOutput.self,
            options: GenerationOptions(
                sampling: .greedy,
                temperature: 0.65,
                maximumResponseTokens: 120
            )
        )
        let output = response.content
        let message = Self.clean(output.message)

        return SessionAnalysisResult(
            message: message.isEmpty ? "Keep this effort smooth and controlled." : message,
            urgency: SessionAnalysisUrgency(rawValue: output.urgency.lowercased()) ?? .steady,
            shouldSpeak: output.shouldSpeak,
            generatedAt: Date(),
            providerID: identifier
        )
    }

    func endSession() {
        session = nil
        activeSessionKey = nil
    }

    private static func instructions(for profile: CoachProfile?, persona: CoachPersona?) -> String {
        var lines = [
            "You are Outbound's on-device live session analyst.",
            "Analyze only the active workout data supplied in each prompt.",
            "Return concise, actionable coaching for the athlete during the session.",
            "Sound like a real coach speaking naturally, not a dashboard reading stats.",
            "Do not repeat the same phrasing across nudges.",
            "Avoid always recapping elapsed time, distance, or pace unless it materially helps the cue.",
            "Assume the app separately speaks elapsed time, distance, and current pace before your coaching advice.",
            "Do not repeat elapsed time, distance, or pace unless it is necessary for safety or clarity.",
            "Do not claim medical certainty. If heart-rate data looks concerning, suggest easing effort and checking how they feel.",
            "Keep spoken messages under 24 words."
        ]

        if let persona {
            lines.append("Coach persona: \(persona.template.displayName).")
            lines.append("Sport focus: \(persona.template.sport.displayName).")
            lines.append("Persona traits: \(persona.template.personality).")
            lines.append("Coaching style: \(persona.template.coachingStyle).")
            lines.append("User-selected intensity: \(persona.intensity.displayName).")
            lines.append("System persona seed: \(persona.template.systemPromptSeed).")
        }

        if let profile {
            lines.append("Coach name: \(profile.coachName).")
            lines.append("Coach personality: \(profile.personality).")
            lines.append("Athlete fitness level: \(profile.athlete.fitnessLevel).")

            if let preferredPace = profile.athlete.preferredPaceSecs {
                lines.append("Preferred pace: \(preferredPace.paceString).")
            }

            if !profile.goals.isEmpty {
                let goals = profile.goals.map(\.description).joined(separator: "; ")
                lines.append("Current goals: \(goals).")
            }

            if !profile.memorySnapshot.recentInsight.isEmpty {
                lines.append("Recent coaching memory: \(profile.memorySnapshot.recentInsight).")
            }

            if !profile.systemPrompt.isEmpty {
                lines.append("Coach system context: \(profile.systemPrompt).")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func sessionKey(profile: CoachProfile?, persona: CoachPersona?) -> String {
        "\(profile?.id ?? "no-profile")|\(persona?.id ?? "no-persona")"
    }

    private static func prompt(for request: SessionAnalysisRequest) -> String {
        let snapshot = request.snapshot
        let pace = snapshot.currentPaceSecsPerKm?.paceString ?? "unknown"
        let heartRate = snapshot.heartRate.map { "\($0) bpm" } ?? "unknown"
        let intent = request.sessionIntent.map(describeIntent) ?? "No planned session intent supplied."
        let location = snapshot.location.map {
            String(
                format: "%.5f, %.5f, accuracy %.0fm, speed %@",
                $0.latitude,
                $0.longitude,
                $0.horizontalAccuracyMeters,
                $0.speedMetersPerSecond.map { String(format: "%.1f m/s", $0) } ?? "unknown"
            )
        } ?? "unknown"
        let recent = request.recentSnapshots.suffix(6).map(describe).joined(separator: "\n")

        return """
        Active session snapshot:
        - activity: \(request.sessionIntent?.title ?? "Freestyle run")
        - plan: \(intent)
        - elapsed: \(snapshot.elapsedSeconds.formatted())
        - distance: \(String(format: "%.2f km", snapshot.distanceKilometers))
        - current pace: \(pace)
        - heart rate: \(heartRate)
        - location: \(location)

        Recent trend:
        \(recent.isEmpty ? "No trend data yet." : recent)

        Use the activity name and any target distance, duration, route, or planned step when it materially improves the nudge.
        Decide whether the athlete needs a spoken nudge now. Return one useful nudge, urgency steady/opportunity/caution, and shouldSpeak.
        """
    }

    private static func describeIntent(_ intent: SessionIntent) -> String {
        var parts = [intent.detail]

        if let distance = intent.resolvedTargetDistanceMeters {
            parts.append(String(format: "target distance %.2f km", distance / 1000))
        }
        if let duration = intent.resolvedTargetDurationSeconds {
            parts.append("target duration \(duration.formatted())")
        }
        if let routeName = intent.routeName, !routeName.isEmpty {
            parts.append("route \(routeName)")
        }
        if !intent.workoutSteps.isEmpty {
            let steps = intent.workoutSteps.prefix(5).map {
                "\($0.label) \($0.durationSeconds.formatted())"
            }
            parts.append("steps: \(steps.joined(separator: "; "))")
        }

        return parts.joined(separator: "; ")
    }

    private static func describe(_ snapshot: ActiveSessionSnapshot) -> String {
        let pace = snapshot.currentPaceSecsPerKm?.paceString ?? "unknown"
        let heartRate = snapshot.heartRate.map { "\($0) bpm" } ?? "unknown"
        return "- \(snapshot.elapsedSeconds.formatted()): \(String(format: "%.2f km", snapshot.distanceKilometers)), pace \(pace), HR \(heartRate)"
    }

    private static func clean(_ message: String) -> String {
        message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct AppleSessionAnalysisOutput {
    @Guide(description: "A single spoken coaching cue under 24 words. Do not repeat elapsed time, distance, or pace unless needed for safety.")
    let message: String

    @Guide(description: "One of: steady, opportunity, caution.")
    let urgency: String

    @Guide(description: "True only when this message is worth speaking aloud immediately.")
    let shouldSpeak: Bool
}

@available(iOS 26.0, macOS 26.0, *)
private enum AppleFoundationModelSessionAnalysisError: LocalizedError {
    case unavailable(SystemLanguageModel.Availability)
    case sessionUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable(let availability):
            "Apple Foundation Model is unavailable: \(availability)"
        case .sessionUnavailable:
            "Apple Foundation Model session could not be created."
        }
    }
}
#endif
