import Foundation

enum SportType: String, Codable, CaseIterable, Identifiable {
    case run
    case bike
    case walk
    case hike
    case swim

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .run: String(localized: "activity.type.run", defaultValue: "Run")
        case .bike: String(localized: "activity.type.bike", defaultValue: "Bike")
        case .walk: String(localized: "activity.type.walk", defaultValue: "Walk")
        case .hike: String(localized: "activity.type.hike", defaultValue: "Hike")
        case .swim: String(localized: "activity.type.swim", defaultValue: "Swim")
        }
    }

    var systemImage: String {
        switch self {
        case .run: "figure.run"
        case .bike: "bicycle"
        case .walk: "figure.walk"
        case .hike: "figure.hiking"
        case .swim: "figure.pool.swim"
        }
    }
}

extension SportType {
    var activityType: ActivityType {
        switch self {
        case .run: .running
        case .bike: .cycling
        case .walk: .walking
        case .hike: .hiking
        case .swim: .swimming
        }
    }

    init(activityType: ActivityType?) {
        switch activityType {
        case .cycling: self = .bike
        case .walking: self = .walk
        case .hiking: self = .hike
        case .swimming: self = .swim
        case .running, .none: self = .run
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
        case .calm: String(localized: "guide.tone.calm", defaultValue: "Calm")
        case .balanced: String(localized: "guide.tone.balanced", defaultValue: "Balanced")
        case .driven: String(localized: "guide.tone.driven", defaultValue: "Driven")
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
        case .low: String(localized: "guide.updates.less", defaultValue: "Less")
        case .normal: String(localized: "guide.updates.standard", defaultValue: "Standard")
        case .high: String(localized: "guide.updates.more", defaultValue: "More")
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

enum GuideVoicePresentation: String, Codable, CaseIterable, Identifiable {
    case female
    case male

    var id: String { rawValue }

    var sectionTitle: String {
        switch self {
        case .female: String(localized: "guide.voice.female.section.title", defaultValue: "Female voices")
        case .male: String(localized: "guide.voice.male.section.title", defaultValue: "Male voices")
        }
    }
}

struct GuideVoice: Codable, Hashable, Identifiable {
    let id: String
    let displayName: String
    let description: String
    let style: String
    let presentation: GuideVoicePresentation
    let previewAssetID: String

    var locale: String { AppLanguage.currentIdentifier }

    static var defaultOption: GuideVoice {
        availableOptions[0]
    }

    static var availableOptions: [GuideVoice] {
        [
            GuideVoice(
                id: "plainstride_warm_1",
                displayName: String(localized: "guide.voice.warm.name", defaultValue: "Female"),
                description: String(localized: "guide.voice.warm.detail", defaultValue: "Warm, clear, and encouraging while you move."),
                style: "warm",
                presentation: .female,
                previewAssetID: "voice.preview"
            ),
            GuideVoice(
                id: "plainstride_clear_1",
                displayName: String(localized: "guide.voice.bright.name", defaultValue: "Male"),
                description: String(localized: "guide.voice.bright.detail", defaultValue: "Direct, steady, and easy to hear while you move."),
                style: "bright",
                presentation: .male,
                previewAssetID: "voice.preview"
            )
        ]
    }
}

struct GuideTemplate: Codable, Hashable, Identifiable {
    let id: String
    let sport: SportType
    let displayName: String
    let tagline: String
    let defaultVoiceId: String
    let allowedVoiceIds: [String]
    let voiceOptions: [GuideVoice]
    let fixedScriptStyleId: String

    var defaultVoice: GuideVoice {
        voiceOptions.first { $0.id == defaultVoiceId } ?? voiceOptions[0]
    }
}

struct GuidePersona: Codable, Hashable, Identifiable {
    let template: GuideTemplate
    let voice: GuideVoice
    let intensity: GuidanceIntensity
    let nudgeFrequency: NudgeFrequency
    let coachingContract: CoachingContract

    var id: String {
        [template.id, voice.id, intensity.rawValue, nudgeFrequency.rawValue, coachingContract.rawValue]
            .joined(separator: ":")
    }
}

extension GuideTemplate {
    static var fixtures: [GuideTemplate] {
        let voices = GuideVoice.availableOptions
        return [
            GuideTemplate(
                id: "plainstride_supportive_v1",
                sport: .run,
                displayName: String(localized: "guide.persona.supportive.name", defaultValue: "Supportive"),
                tagline: String(localized: "guide.persona.supportive.detail", defaultValue: "Encouraging, practical coaching that keeps effort sustainable."),
                defaultVoiceId: "plainstride_warm_1",
                allowedVoiceIds: voices.map(\.id),
                voiceOptions: voices,
                fixedScriptStyleId: "standard"
            ),
            GuideTemplate(
                id: "plainstride_focused_v1",
                sport: .run,
                displayName: String(localized: "guide.persona.focused.name", defaultValue: "Focused"),
                tagline: String(localized: "guide.persona.focused.detail", defaultValue: "Clear, concise coaching with one useful action at a time."),
                defaultVoiceId: "plainstride_clear_1",
                allowedVoiceIds: voices.map(\.id),
                voiceOptions: voices,
                fixedScriptStyleId: "standard"
            ),
            GuideTemplate(
                id: "plainstride_calm_v1",
                sport: .run,
                displayName: String(localized: "guide.persona.calm.name", defaultValue: "Calm"),
                tagline: String(localized: "guide.persona.calm.detail", defaultValue: "Low-key guidance centered on breathing, rhythm, and composure."),
                defaultVoiceId: "plainstride_warm_1",
                allowedVoiceIds: voices.map(\.id),
                voiceOptions: voices,
                fixedScriptStyleId: "calm"
            )
        ]
    }

    static func from(catalog: LiveCoachCatalogDTO) -> [GuideTemplate] {
        let voices = catalog.voices.map {
            GuideVoice(
                id: $0.id,
                displayName: $0.displayName,
                description: $0.description,
                style: $0.style,
                presentation: $0.presentation,
                previewAssetID: $0.previewAssetId
            )
        }
        return catalog.coachPersonas.compactMap { persona in
            let compatible = voices.filter { persona.allowedVoiceProfileIds.contains($0.id) }
            guard !compatible.isEmpty else { return nil }
            return GuideTemplate(
                id: persona.id,
                sport: .run,
                displayName: persona.displayName,
                tagline: persona.description,
                defaultVoiceId: persona.defaultVoiceProfileId,
                allowedVoiceIds: persona.allowedVoiceProfileIds,
                voiceOptions: compatible,
                fixedScriptStyleId: persona.fixedScriptStyleId
            )
        }
    }
}
