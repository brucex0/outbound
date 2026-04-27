import Foundation

enum SessionAnalysisUrgency: String {
    case steady
    case opportunity
    case caution
}

struct SessionAnalysisRequest {
    let profile: CoachProfile?
    let persona: CoachPersona?
    let snapshot: ActiveSessionSnapshot
    let recentSnapshots: [ActiveSessionSnapshot]
}

struct SessionAnalysisResult: Equatable {
    let message: String
    let urgency: SessionAnalysisUrgency
    let shouldSpeak: Bool
    let generatedAt: Date
    let providerID: String
}

@MainActor
protocol SessionAnalysisProvider: AnyObject {
    var identifier: String { get }
    var displayName: String { get }

    func beginSession(profile: CoachProfile?, persona: CoachPersona?)
    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult
    func endSession()
}

extension SessionAnalysisProvider {
    func beginSession(profile: CoachProfile?, persona: CoachPersona?) {}
    func endSession() {}
}

enum SessionAnalysisProviderFactory {
    @MainActor
    static func makePreferredProvider() -> any SessionAnalysisProvider {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return AppleFoundationModelSessionAnalysisProvider()
        }
        #endif

        return RuleBasedSessionAnalysisProvider()
    }
}

@MainActor
final class RuleBasedSessionAnalysisProvider: SessionAnalysisProvider {
    let identifier = "rule-based-session-analyzer"
    let displayName = "Rule-Based Session Analyzer"

    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult {
        SessionAnalysisResult(
            message: buildMessage(for: request),
            urgency: urgency(for: request),
            shouldSpeak: true,
            generatedAt: Date(),
            providerID: identifier
        )
    }

    private func buildMessage(for request: SessionAnalysisRequest) -> String {
        let snapshot = request.snapshot
        let minutes = max(1, snapshot.elapsedSeconds / 60)
        let distance = String(format: "%.1f", snapshot.distanceKilometers)
        let sport = request.persona?.template.sport ?? .run
        var parts = ["\(minutes) minutes in, \(distance) k done."]

        if let pace = snapshot.currentPaceSecsPerKm {
            parts.append("Current pace \(pace.paceString).")

            if let target = request.profile?.athlete.preferredPaceSecs {
                let delta = pace - target
                if delta > 15 {
                    parts.append(slowerThanTargetCue(for: request))
                } else if delta < -15 {
                    parts.append(fasterThanTargetCue(for: request))
                } else {
                    parts.append("You are right on target.")
                }
            } else if paceTrendIsSlowing(request.recentSnapshots) {
                parts.append(sport == .bike
                             ? "Cadence is drifting; smooth the pedal stroke and reset your breathing."
                             : "Cadence is drifting; reset your form and breathe low.")
            } else {
                parts.append(defaultSteadyCue(for: request))
            }
        } else {
            parts.append(sport == .bike
                         ? "Settle in and let the ride data stabilize before chasing speed."
                         : "Settle in and let the GPS lock before chasing pace.")
        }

        if let heartRate = snapshot.heartRate, heartRate > 185 {
            parts.append("Heart rate is high; check effort and control your breathing.")
        } else if let insight = request.profile?.memorySnapshot.recentInsight, !insight.isEmpty {
            parts.append(insight)
        } else if let cue = personaStyleCue(for: request) {
            parts.append(cue)
        }

        return parts.joined(separator: " ")
    }

    private func urgency(for request: SessionAnalysisRequest) -> SessionAnalysisUrgency {
        if let heartRate = request.snapshot.heartRate, heartRate > 185 {
            return .caution
        }

        guard let pace = request.snapshot.currentPaceSecsPerKm,
              let target = request.profile?.athlete.preferredPaceSecs
        else {
            return .steady
        }

        return abs(pace - target) > 15 ? .opportunity : .steady
    }

    private func paceTrendIsSlowing(_ snapshots: [ActiveSessionSnapshot]) -> Bool {
        let paces = snapshots.compactMap(\.currentPaceSecsPerKm)
        guard paces.count >= 4 else { return false }

        let midpoint = paces.count / 2
        let firstAverage = paces[..<midpoint].reduce(0, +) / Double(midpoint)
        let secondAverage = paces[midpoint...].reduce(0, +) / Double(paces.count - midpoint)
        return secondAverage - firstAverage > 20
    }

    private func slowerThanTargetCue(for request: SessionAnalysisRequest) -> String {
        switch request.persona?.intensity ?? .balanced {
        case .calm:
            "Ease toward target gradually over the next minute."
        case .balanced:
            "Ease into a stronger rhythm over the next minute."
        case .driven:
            "Close the gap with control. Lift cadence now."
        }
    }

    private func fasterThanTargetCue(for request: SessionAnalysisRequest) -> String {
        switch request.persona?.intensity ?? .balanced {
        case .calm:
            "Back off a touch and keep the effort sustainable."
        case .balanced:
            "Back off slightly so you have enough left late."
        case .driven:
            "Do not burn the match early. Control this pace."
        }
    }

    private func defaultSteadyCue(for request: SessionAnalysisRequest) -> String {
        let sport = request.persona?.template.sport ?? .run
        switch request.persona?.intensity ?? .balanced {
        case .calm:
            return sport == .bike ? "Keep the pedals smooth." : "Keep the effort relaxed and smooth."
        case .balanced:
            return "Keep the effort smooth."
        case .driven:
            return sport == .bike ? "Hold pressure through the pedals." : "Stay sharp and keep moving well."
        }
    }

    private func personaStyleCue(for request: SessionAnalysisRequest) -> String? {
        guard let persona = request.persona else { return nil }

        switch (persona.template.sport, persona.intensity) {
        case (.run, .calm):
            return "Light feet, quiet shoulders."
        case (.run, .driven):
            return "Stay tall and commit to the stride."
        case (.bike, .calm):
            return "Quiet upper body, even pedal stroke."
        case (.bike, .driven):
            return "Stay loaded and drive clean power."
        default:
            return nil
        }
    }
}
