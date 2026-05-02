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
    private var messageCounter = 0

    func beginSession(profile: CoachProfile?, persona: CoachPersona?) {
        messageCounter = 0
    }

    func endSession() {
        messageCounter = 0
    }

    func analyze(_ request: SessionAnalysisRequest) async throws -> SessionAnalysisResult {
        messageCounter += 1
        return SessionAnalysisResult(
            message: buildMessage(for: request),
            urgency: urgency(for: request),
            shouldSpeak: true,
            generatedAt: Date(),
            providerID: identifier
        )
    }

    private func buildMessage(for request: SessionAnalysisRequest) -> String {
        let snapshot = request.snapshot
        let sport = request.persona?.template.sport ?? .run
        let urgency = urgency(for: request)
        var parts: [String] = []

        if let opener = openingLine(for: request, urgency: urgency) {
            parts.append(opener)
        }

        if let pace = snapshot.currentPaceSecsPerKm {
            if let target = request.profile?.athlete.preferredPaceSecs {
                let delta = pace - target
                if delta > 15 {
                    parts.append(slowerThanTargetCue(for: request))
                } else if delta < -15 {
                    parts.append(fasterThanTargetCue(for: request))
                } else {
                    parts.append(alignedTargetCue(for: request))
                }
            } else if paceTrendIsSlowing(request.recentSnapshots) {
                parts.append(
                    sport == .bike
                        ? variant([
                            "Cadence is drifting a little. Smooth the pedal stroke and settle the breath.",
                            "The spin is getting choppy. Round it out and breathe deeper.",
                            "Bring the cadence back under you and make the effort smoother."
                        ])
                        : variant([
                            "Cadence is drifting. Reset the form and breathe low.",
                            "Your rhythm is getting a little loose. Quiet the upper body and reset.",
                            "Bring the stride back under control and let the breath settle."
                        ])
                )
            } else {
                parts.append(defaultSteadyCue(for: request))
            }
        } else {
            parts.append(
                sport == .bike
                    ? variant([
                        "Settle in first. Let the ride data stabilize before you chase speed.",
                        "Give the sensors a second and keep the opening smooth.",
                        "No rush. Let the ride settle before you push the pace."
                    ])
                    : variant([
                        "Settle in first. Let the GPS lock before you chase pace.",
                        "No rush. Let the opening minute smooth itself out.",
                        "Stay patient for a beat while the pace settles."
                    ])
            )
        }

        if let heartRate = snapshot.heartRate, heartRate > 185 {
            parts.append(variant([
                "Heart rate is up. Ease the effort and get the breathing back under you.",
                "That effort looks hot. Back off a touch and regain control.",
                "Bring it down slightly here and let the breath catch up."
            ]))
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
            return variant([
                "Ease toward target gradually over the next minute.",
                "Nudge the effort up a little, not all at once.",
                "Gently build from here and let the pace come to you."
            ])
        case .balanced:
            return variant([
                "Ease into a stronger rhythm over the next minute.",
                "Bring the effort up a notch and reconnect with the pace.",
                "There is room to press a little here. Build into it."
            ])
        case .driven:
            return variant([
                "Close the gap with control. Lift cadence now.",
                "You can give this more. Sharpen the rhythm and go get it.",
                "Bring the pace up with purpose. Quicken the turnover now."
            ])
        }
    }

    private func fasterThanTargetCue(for request: SessionAnalysisRequest) -> String {
        switch request.persona?.intensity ?? .balanced {
        case .calm:
            return variant([
                "Back off a touch and keep the effort sustainable.",
                "Soften this slightly and make it feel easier again.",
                "Take half a step back and keep the effort smooth."
            ])
        case .balanced:
            return variant([
                "Back off slightly so you have enough left late.",
                "Dial it back a fraction and save the stronger effort for later.",
                "Control the pace here so the back half stays strong."
            ])
        case .driven:
            return variant([
                "Do not burn the match early. Control this pace.",
                "Strong is fine. Wasteful is not. Bring it under control.",
                "Too hot right now. Settle it before it costs you later."
            ])
        }
    }

    private func defaultSteadyCue(for request: SessionAnalysisRequest) -> String {
        let sport = request.persona?.template.sport ?? .run
        switch request.persona?.intensity ?? .balanced {
        case .calm:
            return sport == .bike
                ? variant([
                    "Keep the pedals smooth.",
                    "Nice and even through the pedal stroke.",
                    "Stay relaxed and keep the spin tidy."
                ])
                : variant([
                    "Keep the effort relaxed and smooth.",
                    "Stay easy and let the stride stay quiet.",
                    "This is good. Keep it loose and steady."
                ])
        case .balanced:
            return variant([
                "Keep the effort smooth.",
                "This rhythm works. Stay right here.",
                "Settle into this pace and keep it clean."
            ])
        case .driven:
            return sport == .bike
                ? variant([
                    "Hold pressure through the pedals.",
                    "Stay loaded and keep the power clean.",
                    "Keep driving, but keep it smooth."
                ])
                : variant([
                    "Stay sharp and keep moving well.",
                    "Hold the rhythm and keep the stride snappy.",
                    "You are in a good place. Stay switched on."
                ])
        }
    }

    private func personaStyleCue(for request: SessionAnalysisRequest) -> String? {
        guard let persona = request.persona else { return nil }

        switch (persona.template.sport, persona.intensity) {
        case (.run, .calm):
            return variant(["Light feet, quiet shoulders.", "Easy shoulders. Light steps.", "Keep the feet quick and the shoulders soft."])
        case (.run, .driven):
            return variant(["Stay tall and commit to the stride.", "Tall posture. Strong stride.", "Stand up into the stride and keep it decisive."])
        case (.bike, .calm):
            return variant(["Quiet upper body, even pedal stroke.", "Keep the torso calm and the cadence even.", "Relax the upper body and make the spin smooth."])
        case (.bike, .driven):
            return variant(["Stay loaded and drive clean power.", "Strong legs, quiet upper body.", "Keep the pressure on without getting ragged."])
        default:
            return nil
        }
    }

    private func alignedTargetCue(for request: SessionAnalysisRequest) -> String {
        let sport = request.persona?.template.sport ?? .run
        return sport == .bike
            ? variant([
                "That is right where you want it. Keep the ride flowing.",
                "Good line. Hold this effort.",
                "You are right on it. Keep the pressure smooth."
            ])
            : variant([
                "You are right where you want to be. Stay with it.",
                "That pace is landing well. Hold the rhythm.",
                "Good line. Keep this effort smooth."
            ])
    }

    private func openingLine(for request: SessionAnalysisRequest, urgency: SessionAnalysisUrgency) -> String? {
        let minutes = max(1, request.snapshot.elapsedSeconds / 60)
        let distance = String(format: "%.1f", request.snapshot.distanceKilometers)
        let sport = request.persona?.template.sport ?? .run

        if request.snapshot.elapsedSeconds <= 90 {
            return sport == .bike
                ? variant([
                    "Nice easy start.",
                    "Good, you are rolling now.",
                    "Settle into the ride."
                ])
                : variant([
                    "Good, you are underway.",
                    "Nice easy start.",
                    "You are in it now."
                ])
        }

        guard messageCounter.isMultiple(of: 3) else { return nil }

        switch urgency {
        case .steady:
            return variant([
                "\(minutes) minutes in. Stay with the rhythm.",
                "\(distance) k done. Keep it smooth.",
                "This is a good point to reset and stay tidy."
            ])
        case .opportunity:
            return variant([
                "\(minutes) minutes in. There is room to move here.",
                "\(distance) k in. This is your chance to sharpen it.",
                "You are far enough in now to work a little more."
            ])
        case .caution:
            return variant([
                "Check in with the effort here.",
                "This is a good time to steady things down.",
                "Settle first, then rebuild."
            ])
        }
    }

    private func variant(_ options: [String]) -> String {
        guard !options.isEmpty else { return "" }
        return options[messageCounter % options.count]
    }
}
