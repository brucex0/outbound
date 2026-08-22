import Foundation

enum AnalyticsValue: Sendable, Equatable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)

    nonisolated var foundationValue: Any {
        switch self {
        case .string(let value): value
        case .integer(let value): value
        case .double(let value): value
        case .boolean(let value): value
        }
    }
}

enum ProductEventName: String, Sendable, CaseIterable {
    case activitySetupViewed = "activity_setup_viewed"
    case activityConfigurationChanged = "activity_configuration_changed"
    case activityStarted = "activity_started"
    case activityPaused = "activity_paused"
    case activityResumed = "activity_resumed"
    case activityFinished = "activity_finished"
    case activitySaved = "activity_saved"
    case activityDiscarded = "activity_discarded"
    case goalProgressReached = "goal_progress_reached"
    case featureExposed = "feature_exposed"
    case musicAuthorizationRequested = "music_authorization_requested"
    case musicAuthorizationCompleted = "music_authorization_completed"
    case musicQuickPickSelected = "music_quick_pick_selected"
    case musicPlaybackStarted = "music_playback_started"
    case musicControlUsed = "music_control_used"
    case musicOperationFailed = "music_operation_failed"
    case routeLibraryOpened = "route_library_opened"
    case routeSelected = "route_selected"
    case shoeSelected = "shoe_selected"
    case photoCaptureAttempted = "photo_capture_attempted"
    case photoCaptured = "photo_captured"
    case photoRemoved = "photo_removed"
    case groupRunCreateAttempted = "group_run_create_attempted"
    case groupRunCreated = "group_run_created"
    case groupRunJoinAttempted = "group_run_join_attempted"
    case groupRunJoined = "group_run_joined"
    case groupRunInviteShared = "group_run_invite_shared"
}

enum ProductPropertyKey: String, Sendable, CaseIterable {
    case schemaVersion = "schema_version"
    case appVersion = "app_version"
    case appBuild = "app_build"
    case osMajorVersion = "os_major_version"
    case language = "language"
    case authenticationState = "authentication_state"
    case entrySource = "entry_source"
    case feature
    case changeType = "change_type"
    case selectionType = "selection_type"
    case sourceType = "source_type"
    case goalType = "goal_type"
    case targetBucket = "target_bucket"
    case progressPercent = "progress_percent"
    case musicEnabled = "music_enabled"
    case routeSelected = "route_selected"
    case shoeSelected = "shoe_selected"
    case preRunPhotoAdded = "pre_run_photo_added"
    case groupRunEnabled = "group_run_enabled"
    case liveShareEnabled = "live_share_enabled"
    case indoor
    case durationBucket = "duration_bucket"
    case distanceBucket = "distance_bucket"
    case photoCountBucket = "photo_count_bucket"
    case participantCountBucket = "participant_count_bucket"
    case goalCompletionBucket = "goal_completion_bucket"
    case control
    case result
    case errorCategory = "error_category"
}

struct ProductAnalyticsEvent: Sendable, Equatable {
    static let currentSchemaVersion = 1

    let name: ProductEventName
    let schemaVersion: Int
    let properties: [ProductPropertyKey: AnalyticsValue]

    init(
        _ name: ProductEventName,
        schemaVersion: Int = currentSchemaVersion,
        properties: [ProductPropertyKey: AnalyticsValue] = [:]
    ) {
        self.name = name
        self.schemaVersion = schemaVersion
        self.properties = properties
    }
}

enum ProductAnalyticsSchema {
    nonisolated private static let sharedKeys: Set<ProductPropertyKey> = [
        .schemaVersion, .appVersion, .appBuild, .osMajorVersion, .language, .authenticationState
    ]

    nonisolated private static let eventKeys: [ProductEventName: Set<ProductPropertyKey>] = [
        .activitySetupViewed: [.entrySource],
        .activityConfigurationChanged: [.changeType, .selectionType, .goalType, .targetBucket],
        .activityStarted: [.entrySource, .goalType, .targetBucket, .musicEnabled, .routeSelected, .shoeSelected, .preRunPhotoAdded, .groupRunEnabled, .liveShareEnabled, .indoor, .participantCountBucket],
        .activityPaused: [],
        .activityResumed: [],
        .activityFinished: [.durationBucket, .distanceBucket, .goalCompletionBucket],
        .activitySaved: [.goalType, .durationBucket, .distanceBucket, .photoCountBucket, .goalCompletionBucket, .musicEnabled, .routeSelected, .shoeSelected, .groupRunEnabled, .indoor],
        .activityDiscarded: [.durationBucket, .distanceBucket, .photoCountBucket, .goalCompletionBucket],
        .goalProgressReached: [.goalType, .progressPercent],
        .featureExposed: [.feature],
        .musicAuthorizationRequested: [],
        .musicAuthorizationCompleted: [.result],
        .musicQuickPickSelected: [.selectionType],
        .musicPlaybackStarted: [.result],
        .musicControlUsed: [.control],
        .musicOperationFailed: [.errorCategory],
        .routeLibraryOpened: [],
        .routeSelected: [.sourceType, .distanceBucket],
        .shoeSelected: [.selectionType],
        .photoCaptureAttempted: [.sourceType],
        .photoCaptured: [.sourceType],
        .photoRemoved: [.sourceType],
        .groupRunCreateAttempted: [],
        .groupRunCreated: [.participantCountBucket],
        .groupRunJoinAttempted: [],
        .groupRunJoined: [.participantCountBucket],
        .groupRunInviteShared: [.participantCountBucket]
    ]

    nonisolated static func validatedProperties(for event: ProductAnalyticsEvent) -> [ProductPropertyKey: AnalyticsValue]? {
        guard event.schemaVersion > 0, let specificKeys = eventKeys[event.name] else { return nil }
        let allowedKeys = sharedKeys.union(specificKeys)
        guard Set(event.properties.keys).isSubset(of: allowedKeys) else { return nil }
        guard event.properties.values.allSatisfy(isSafeValue) else { return nil }
        return event.properties
    }

    private nonisolated static func isSafeValue(_ value: AnalyticsValue) -> Bool {
        switch value {
        case .string(let value):
            return !value.isEmpty && value.count <= 64 && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-." )).contains($0)
            }
        case .integer, .double, .boolean:
            return true
        }
    }
}

enum ProductAnalyticsBucket {
    static func distance(meters: Double) -> String {
        return switch max(0, meters) {
        case ..<1_000: "under_1k"
        case ..<3_000: "1k_3k"
        case ..<5_000: "3k_5k"
        case ..<10_000: "5k_10k"
        case ..<21_097.5: "10k_half"
        default: "half_plus"
        }
    }

    static func duration(seconds: Int) -> String {
        return switch max(0, seconds) {
        case ..<600: "under_10m"
        case ..<1_800: "10m_30m"
        case ..<3_600: "30m_60m"
        case ..<7_200: "60m_120m"
        default: "120m_plus"
        }
    }

    static func count(_ count: Int) -> String {
        return switch max(0, count) {
        case 0: "0"
        case 1: "1"
        case 2...3: "2_3"
        case 4...7: "4_7"
        default: "8_plus"
        }
    }

    static func completion(_ ratio: Double?) -> String {
        guard let ratio, ratio.isFinite else { return "not_applicable" }
        return switch max(0, ratio) {
        case ..<0.25: "under_25"
        case ..<0.50: "25_49"
        case ..<0.75: "50_74"
        case ..<1.0: "75_99"
        default: "completed"
        }
    }
}
