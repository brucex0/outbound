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

    var isStandardQuality: Bool { id.hasPrefix("apple-standard-") }

    static var availableOptions: [GuideVoice] {
        downloadedAppleVoices()
            + siriAppleVoices()
            + (standardAppleVoice().map { [$0] } ?? [])
    }

    static var defaultOption: GuideVoice {
        let options = availableOptions
        let locale = AppLanguage.speechLocale
        let targetLanguage = locale.language.languageCode?.identifier
        let targetRegion = locale.region?.identifier
        return options
            .filter {
                !$0.isStandardQuality
                    && Locale(identifier: $0.locale).language.languageCode?.identifier == targetLanguage
            }
            .sorted {
                let lhsLocale = Locale(identifier: $0.locale)
                let rhsLocale = Locale(identifier: $1.locale)
                let lhsRank = localeRank(lhsLocale, targetLanguage: targetLanguage, targetRegion: targetRegion)
                let rhsRank = localeRank(rhsLocale, targetLanguage: targetLanguage, targetRegion: targetRegion)
                return lhsRank == rhsRank
                    ? $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    : lhsRank > rhsRank
            }
            .first ?? options.first(where: \.isStandardQuality) ?? options[0]
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
                        if lhs.quality != rhs.quality {
                            return lhs.quality == .premium
                        }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
        }

        let femaleVoices = rankedVoices(for: .female).map {
            downloadedAppleVoice(from: $0, gender: .female)
        }
        let maleVoices = rankedVoices(for: .male).map {
            downloadedAppleVoice(from: $0, gender: .male)
        }
        let unspecifiedVoices = rankedVoices(for: .unspecified).map {
            downloadedAppleVoice(from: $0, gender: nil)
        }
        return femaleVoices + maleVoices + unspecifiedVoices
    }

    private static func standardAppleVoice() -> GuideVoice? {
        let locale = AppLanguage.speechLocale
        let targetLanguage = locale.language.languageCode?.identifier
        let targetRegion = locale.region?.identifier
        let voice = AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                let voiceLocale = Locale(identifier: voice.language)
                return voice.quality == .default
                    && !isSiriVoice(voice)
                    && voiceLocale.language.languageCode?.identifier == targetLanguage
                    && !voice.voiceTraits.contains(.isNoveltyVoice)
                    && !voice.voiceTraits.contains(.isPersonalVoice)
            }
            .sorted { lhs, rhs in
                let lhsRank = localeRank(Locale(identifier: lhs.language), targetLanguage: targetLanguage, targetRegion: targetRegion)
                let rhsRank = localeRank(Locale(identifier: rhs.language), targetLanguage: targetLanguage, targetRegion: targetRegion)
                return lhsRank == rhsRank
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : lhsRank > rhsRank
            }
            .first
        return voice.map { downloadedAppleVoice(from: $0, gender: genderPresentation(for: $0.gender)) }
    }

    private static func siriAppleVoices() -> [GuideVoice] {
        let locale = AppLanguage.speechLocale
        let targetLanguage = locale.language.languageCode?.identifier
        let targetRegion = locale.region?.identifier
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                voice.quality == .default
                    && isSiriVoice(voice)
                    && !voice.voiceTraits.contains(.isNoveltyVoice)
                    && !voice.voiceTraits.contains(.isPersonalVoice)
            }
            .sorted { lhs, rhs in
                let lhsRank = localeRank(Locale(identifier: lhs.language), targetLanguage: targetLanguage, targetRegion: targetRegion)
                let rhsRank = localeRank(Locale(identifier: rhs.language), targetLanguage: targetLanguage, targetRegion: targetRegion)
                return lhsRank == rhsRank
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : lhsRank > rhsRank
            }
            .map { downloadedAppleVoice(from: $0, gender: genderPresentation(for: $0.gender)) }
    }

    private static func isSiriVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        voice.identifier.localizedCaseInsensitiveContains("siri")
            || voice.name.localizedCaseInsensitiveContains("siri")
    }

    private static func genderPresentation(for gender: AVSpeechSynthesisVoiceGender) -> GuideGenderPresentation? {
        switch gender {
        case .female: .female
        case .male: .male
        default: nil
        }
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
        gender: GuideGenderPresentation?
    ) -> GuideVoice {
        GuideVoice(
            id: isSiriVoice(voice)
                ? "apple-siri-\(voice.identifier)"
                : voice.quality == .default
                    ? "apple-standard-\(voice.identifier)"
                    : "apple-high-quality-\(voice.identifier)",
            displayName: voice.name,
            description: voiceDescription(voice),
            locale: voice.language,
            appleVoiceIdentifier: voice.identifier,
            genderPresentation: gender,
            rate: 0.5,
            volume: 0.95
        )
    }

    private static func voiceDescription(_ voice: AVSpeechSynthesisVoice) -> String {
        let quality = switch voice.quality {
        case .premium: String(localized: "guide.voice.quality.premium", defaultValue: "Apple Premium")
        case .enhanced: String(localized: "guide.voice.quality.enhanced", defaultValue: "Apple Enhanced")
        default: isSiriVoice(voice)
            ? String(localized: "guide.voice.quality.siri", defaultValue: "Apple Siri")
            : String(localized: "guide.voice.quality.standard", defaultValue: "Apple Standard")
        }
        let language = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
        return "\(quality) · \(language)"
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
    nonisolated static var fixtures: [GuideTemplate] {
        let voices = GuideVoice.availableOptions
        let defaultVoice = GuideVoice.defaultOption
        return [GuideTemplate(
            id: "live-running-guidance",
            sport: .run,
            displayName: "Live Guidance",
            tagline: "Spoken coaching that adapts to your run.",
            personality: "supportive, practical, pace-aware",
            guidanceStyle: "Concise running guidance whose tone follows the athlete's coaching-tone preference.",
            defaultVoiceId: defaultVoice.id,
            voiceOptions: voices,
            systemPromptSeed: "Be practical and concise. Follow the selected coaching tone while prioritizing sustainable pacing, posture, breathing, and consistency."
        )]
    }
}
