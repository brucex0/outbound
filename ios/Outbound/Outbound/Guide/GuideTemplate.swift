import AVFoundation
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

extension SportType {
    var activityType: ActivityType {
        switch self {
        case .run: .running
        case .bike: .cycling
        }
    }
}

enum GuideGenderPresentation: String, Codable, CaseIterable, Identifiable {
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

enum GuidanceIntensity: String, Codable, CaseIterable, Identifiable {
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
        case .low: "Less"
        case .normal: "Standard"
        case .high: "More"
        }
    }

    var analysisIntervalSeconds: Int {
        switch self {
        case .low: 120
        case .normal: 75
        case .high: 45
        }
    }

    var progressAnnouncementIntervalSeconds: Int {
        switch self {
        case .low: 300
        case .normal: 180
        case .high: 120
        }
    }
}

struct GuideVoice: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let description: String
    let locale: String
    let appleVoiceIdentifier: String?
    let genderPresentation: GuideGenderPresentation?
    let rate: Float
    let volume: Float

    nonisolated static let systemBest = GuideVoice(
        id: "apple-system-best",
        displayName: "Apple Best",
        description: "Highest-quality installed voice for your language",
        locale: "system",
        appleVoiceIdentifier: nil,
        genderPresentation: nil,
        rate: 0.5,
        volume: 0.95
    )

    static var availableOptions: [GuideVoice] {
        [.systemBest] + downloadedAppleVoices()
    }

    private static func downloadedAppleVoices() -> [GuideVoice] {
        let locale = AppLanguage.speechLocale
        let targetLanguage = locale.language.languageCode?.identifier
        let targetRegion = locale.region?.identifier
        let downloadedVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                return (voice.quality == .premium || voice.quality == .enhanced)
                    && !voice.voiceTraits.contains(.isNoveltyVoice)
                    && !voice.voiceTraits.contains(.isPersonalVoice)
            }

        func rankedVoices(for gender: AVSpeechSynthesisVoiceGender) -> [AVSpeechSynthesisVoice] {
            Array(
                downloadedVoices
                    .filter { $0.gender == gender }
                    .sorted { lhs, rhs in
                        let lhsLocale = Locale(identifier: lhs.language)
                        let rhsLocale = Locale(identifier: rhs.language)
                        let lhsRank = localeRank(
                            lhsLocale,
                            targetLanguage: targetLanguage,
                            targetRegion: targetRegion
                        )
                        let rhsRank = localeRank(
                            rhsLocale,
                            targetLanguage: targetLanguage,
                            targetRegion: targetRegion
                        )
                        if lhsRank != rhsRank {
                            return lhsRank > rhsRank
                        }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                    .prefix(5)
            )
        }

        let femaleVoices = rankedVoices(for: .female).map {
            downloadedAppleVoice(from: $0, gender: .female)
        }
        let maleVoices = rankedVoices(for: .male).map {
            downloadedAppleVoice(from: $0, gender: .male)
        }
        return femaleVoices + maleVoices
    }

    private static func localeRank(
        _ locale: Locale,
        targetLanguage: String?,
        targetRegion: String?
    ) -> Int {
        guard locale.language.languageCode?.identifier == targetLanguage else { return 0 }
        return locale.region?.identifier == targetRegion ? 2 : 1
    }

    private static func downloadedAppleVoice(
        from voice: AVSpeechSynthesisVoice,
        gender: GuideGenderPresentation
    ) -> GuideVoice {
        GuideVoice(
            id: "apple-premium-\(voice.identifier)",
            displayName: voice.name,
            description: "Apple \(voice.quality == .premium ? "Premium" : "Enhanced") · \(Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language)",
            locale: voice.language,
            appleVoiceIdentifier: voice.identifier,
            genderPresentation: gender,
            rate: 0.5,
            volume: 0.95
        )
    }
}

struct GuideTemplate: Codable, Hashable, Identifiable {
    let id: String
    let sport: SportType
    let displayName: String
    let tagline: String
    let personality: String
    let guidanceStyle: String
    let defaultVoiceId: String
    let voiceOptions: [GuideVoice]
    let systemPromptSeed: String

    var defaultVoice: GuideVoice {
        voiceOptions.first { $0.id == defaultVoiceId } ?? voiceOptions[0]
    }

}

struct GuidePersona: Codable, Hashable, Identifiable {
    let template: GuideTemplate
    let voice: GuideVoice
    let intensity: GuidanceIntensity
    let nudgeFrequency: NudgeFrequency

    var id: String {
        [
            template.id,
            voice.id,
            intensity.rawValue,
            nudgeFrequency.rawValue
        ].joined(separator: ":")
    }
}

extension GuideTemplate {
    nonisolated static let fixtures: [GuideTemplate] = [
        GuideTemplate(
            id: "live-running-guidance",
            sport: .run,
            displayName: "Live Guidance",
            tagline: "Spoken coaching that adapts to your run.",
            personality: "supportive, practical, pace-aware",
            guidanceStyle: "Concise running guidance whose tone follows the athlete's coaching-tone preference.",
            defaultVoiceId: GuideVoice.systemBest.id,
            voiceOptions: GuideVoice.availableOptions,
            systemPromptSeed: "Be practical and concise. Follow the selected coaching tone while prioritizing sustainable pacing, posture, breathing, and consistency."
        )
    ]
}
