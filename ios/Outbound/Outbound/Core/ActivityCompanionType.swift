import SwiftUI

/// Optional activity companion context (`With dog`).
///
/// This is deliberately not an `ActivityType`: the canonical sport stays
/// running, walking, hiking, or cycling while this value records that the
/// person brought a dog. It never measures or describes the dog itself.
nonisolated enum ActivityCompanionType: String, Hashable, CaseIterable, Codable {
    case dog

    /// Localized label used on the setup control and shared marker surfaces.
    var displayName: String {
        switch self {
        case .dog: String(localized: "activity.companion.dog.title", defaultValue: "With dog")
        }
    }

    /// Sports that may carry the companion context.
    nonisolated static let eligibleActivityTypes: Set<ActivityType> = [
        .running, .walking, .hiking, .cycling,
    ]

    nonisolated static func isEligible(for activityType: ActivityType) -> Bool {
        eligibleActivityTypes.contains(activityType)
    }

    /// Unknown future values decode as `nil` so older app versions never fail
    /// on newer records; unsupported values are never sent back upstream.
    nonisolated init?(safeDecoding rawValue: String?) {
        guard let rawValue, let value = ActivityCompanionType(rawValue: rawValue) else { return nil }
        self = value
    }

    /// Default title for freestyle activities only. Planned and curated
    /// workouts keep their own titles; the canonical sport is never changed.
    func defaultFreestyleTitle(for activityType: ActivityType) -> String {
        switch activityType {
        case .running: String(localized: "recording.companion.title.run", defaultValue: "Dog run")
        case .walking: String(localized: "recording.companion.title.walk", defaultValue: "Dog walk")
        case .hiking: String(localized: "recording.companion.title.hike", defaultValue: "Dog hike")
        case .cycling: String(localized: "recording.companion.title.ride", defaultValue: "Dog ride")
        default: displayName
        }
    }
}

extension ActivityType {
    /// True when the `With dog` context is not offered for this sport.
    var ineligibleForCompanion: Bool {
        ActivityCompanionType.isEligible(for: self) == false
    }
}

extension ActivityCompanionType {
    /// Compact text treatment for countdown/live surfaces. Deliberately small
    /// so it never displaces primary metrics.
    var liveBadge: some View {
        Text(displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(OutboundPalette.companion)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(OutboundPalette.companion.opacity(0.12), in: Capsule())
            .fixedSize()
            .accessibilityElement(children: .combine)
    }

    /// Compact text pill for saved history, detail, and share-safe social cards.
    var savedPill: some View {
        Text(displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(OutboundPalette.companion)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(OutboundPalette.companion.opacity(0.12), in: Capsule())
            .fixedSize()
    }
}
