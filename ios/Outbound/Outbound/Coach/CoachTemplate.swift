import Foundation

enum SportType: String, Codable, CaseIterable, Identifiable {
    case run
    case bike

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .run: "Run"
        case .bike: "Bike"
        }
    }

    var systemImage: String {
        switch self {
        case .run: "figure.run"
        case .bike: "bicycle"
        }
    }
}

enum CoachGenderPresentation: String, Codable, CaseIterable, Identifiable {
    case female
    case male

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        }
    }
}

enum CoachingIntensity: String, Codable, CaseIterable, Identifiable {
    case calm
    case balanced
    case driven

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .calm: "Calm"
        case .balanced: "Balanced"
        case .driven: "Driven"
        }
    }
}

enum NudgeFrequency: String, Codable, CaseIterable, Identifiable {
    case low
    case normal
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }

    var analysisIntervalSeconds: Int {
        switch self {
        case .low: 120
        case .normal: 75
        case .high: 45
        }
    }
}

struct CoachVoice: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let locale: String
    let rate: Float
    let pitch: Float
    let volume: Float
    let avFoundationIdentifier: String?
}

struct CoachFace: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let symbolName: String
    let colorName: String
}

struct CoachTemplate: Codable, Hashable, Identifiable {
    let id: String
    let sport: SportType
    let genderPresentation: CoachGenderPresentation
    let displayName: String
    let tagline: String
    let personality: String
    let coachingStyle: String
    let defaultVoiceId: String
    let voiceOptions: [CoachVoice]
    let defaultFaceId: String
    let faceOptions: [CoachFace]
    let systemPromptSeed: String
    let sampleNudges: [String]

    var defaultVoice: CoachVoice {
        voiceOptions.first { $0.id == defaultVoiceId } ?? voiceOptions[0]
    }

    var defaultFace: CoachFace {
        faceOptions.first { $0.id == defaultFaceId } ?? faceOptions[0]
    }
}

struct CoachPersona: Codable, Hashable, Identifiable {
    let template: CoachTemplate
    let voice: CoachVoice
    let face: CoachFace
    let intensity: CoachingIntensity
    let nudgeFrequency: NudgeFrequency

    var id: String {
        [
            template.id,
            voice.id,
            face.id,
            intensity.rawValue,
            nudgeFrequency.rawValue
        ].joined(separator: ":")
    }
}

extension CoachTemplate {
    nonisolated static let fixtures: [CoachTemplate] = [
        CoachTemplate(
            id: "run-maya-tempo",
            sport: .run,
            genderPresentation: .female,
            displayName: "Maya Tempo",
            tagline: "Smooth miles, sharper habits.",
            personality: "warm, tactical, form-focused",
            coachingStyle: "Steady encouragement with short form cues and realistic pacing.",
            defaultVoiceId: "maya-clear",
            voiceOptions: [
                CoachVoice(id: "maya-clear", displayName: "Clear", locale: "en-US", rate: 0.49, pitch: 1.08, volume: 0.9, avFoundationIdentifier: nil),
                CoachVoice(id: "maya-calm", displayName: "Calm", locale: "en-US", rate: 0.45, pitch: 1.02, volume: 0.85, avFoundationIdentifier: nil),
                CoachVoice(id: "maya-bright", displayName: "Bright", locale: "en-US", rate: 0.53, pitch: 1.14, volume: 0.92, avFoundationIdentifier: nil)
            ],
            defaultFaceId: "maya-sunrise",
            faceOptions: [
                CoachFace(id: "maya-sunrise", displayName: "Sunrise", symbolName: "sun.max.fill", colorName: "orange"),
                CoachFace(id: "maya-spark", displayName: "Spark", symbolName: "sparkles", colorName: "pink"),
                CoachFace(id: "maya-leaf", displayName: "Leaf", symbolName: "leaf.fill", colorName: "green")
            ],
            systemPromptSeed: "Coach like Maya: warm, practical, concise. Prioritize sustainable pacing, posture, breathing, and consistency.",
            sampleNudges: [
                "Relax your shoulders and keep the cadence light.",
                "This is a good rhythm. Hold it without forcing.",
                "Check your breath, then settle into the next block."
            ]
        ),
        CoachTemplate(
            id: "run-theo-stride",
            sport: .run,
            genderPresentation: .male,
            displayName: "Theo Stride",
            tagline: "Direct cues for faster running.",
            personality: "direct, competitive, pace-aware",
            coachingStyle: "Race-minded prompts with clear effort targets and controlled urgency.",
            defaultVoiceId: "theo-direct",
            voiceOptions: [
                CoachVoice(id: "theo-direct", displayName: "Direct", locale: "en-US", rate: 0.52, pitch: 0.94, volume: 0.95, avFoundationIdentifier: nil),
                CoachVoice(id: "theo-measured", displayName: "Measured", locale: "en-US", rate: 0.48, pitch: 0.9, volume: 0.9, avFoundationIdentifier: nil),
                CoachVoice(id: "theo-race", displayName: "Race", locale: "en-US", rate: 0.56, pitch: 0.98, volume: 0.98, avFoundationIdentifier: nil)
            ],
            defaultFaceId: "theo-bolt",
            faceOptions: [
                CoachFace(id: "theo-bolt", displayName: "Bolt", symbolName: "bolt.fill", colorName: "yellow"),
                CoachFace(id: "theo-track", displayName: "Track", symbolName: "flag.checkered", colorName: "blue"),
                CoachFace(id: "theo-flame", displayName: "Flame", symbolName: "flame.fill", colorName: "red")
            ],
            systemPromptSeed: "Coach like Theo: direct, race-aware, and controlled. Give precise pace and effort cues without overtalking.",
            sampleNudges: [
                "Stay tall. Quick feet, no wasted motion.",
                "You are close to target. Lock this in.",
                "Press with control, then recover your breathing."
            ]
        ),
        CoachTemplate(
            id: "bike-iris-cadence",
            sport: .bike,
            genderPresentation: .female,
            displayName: "Iris Cadence",
            tagline: "Endurance rides with calm control.",
            personality: "calm, precise, endurance-minded",
            coachingStyle: "Steady ride guidance focused on cadence, fueling, and smooth effort.",
            defaultVoiceId: "iris-smooth",
            voiceOptions: [
                CoachVoice(id: "iris-smooth", displayName: "Smooth", locale: "en-US", rate: 0.47, pitch: 1.04, volume: 0.88, avFoundationIdentifier: nil),
                CoachVoice(id: "iris-soft", displayName: "Soft", locale: "en-US", rate: 0.43, pitch: 1.0, volume: 0.82, avFoundationIdentifier: nil),
                CoachVoice(id: "iris-crisp", displayName: "Crisp", locale: "en-US", rate: 0.5, pitch: 1.07, volume: 0.9, avFoundationIdentifier: nil)
            ],
            defaultFaceId: "iris-river",
            faceOptions: [
                CoachFace(id: "iris-river", displayName: "River", symbolName: "water.waves", colorName: "teal"),
                CoachFace(id: "iris-compass", displayName: "Compass", symbolName: "location.north.fill", colorName: "blue"),
                CoachFace(id: "iris-cloud", displayName: "Cloud", symbolName: "cloud.sun.fill", colorName: "cyan")
            ],
            systemPromptSeed: "Coach like Iris: calm, efficient, and endurance-first. Emphasize cadence, fueling, posture, and smooth power.",
            sampleNudges: [
                "Keep the pedals round and the upper body quiet.",
                "Check your cadence and keep the effort even.",
                "Fuel early, stay relaxed, and let the pace come to you."
            ]
        ),
        CoachTemplate(
            id: "bike-marco-gear",
            sport: .bike,
            genderPresentation: .male,
            displayName: "Marco Gear",
            tagline: "Punchy cues for climbs and intervals.",
            personality: "energetic, sharp, power-focused",
            coachingStyle: "High-energy prompts for surges, climbs, and structured interval work.",
            defaultVoiceId: "marco-punch",
            voiceOptions: [
                CoachVoice(id: "marco-punch", displayName: "Punch", locale: "en-US", rate: 0.54, pitch: 0.96, volume: 0.96, avFoundationIdentifier: nil),
                CoachVoice(id: "marco-deep", displayName: "Deep", locale: "en-US", rate: 0.49, pitch: 0.88, volume: 0.92, avFoundationIdentifier: nil),
                CoachVoice(id: "marco-attack", displayName: "Attack", locale: "en-US", rate: 0.58, pitch: 0.98, volume: 1.0, avFoundationIdentifier: nil)
            ],
            defaultFaceId: "marco-peak",
            faceOptions: [
                CoachFace(id: "marco-peak", displayName: "Peak", symbolName: "mountain.2.fill", colorName: "purple"),
                CoachFace(id: "marco-gear", displayName: "Gear", symbolName: "gearshape.2.fill", colorName: "gray"),
                CoachFace(id: "marco-bolt", displayName: "Bolt", symbolName: "bolt.circle.fill", colorName: "yellow")
            ],
            systemPromptSeed: "Coach like Marco: energetic, concise, and power-focused. Use punchy cues for controlled attacks and climbs.",
            sampleNudges: [
                "Stay seated, load the gear, and drive smooth power.",
                "This is the work. Keep pressure through the pedals.",
                "Recover the breath, then be ready for the next push."
            ]
        )
    ]
}
