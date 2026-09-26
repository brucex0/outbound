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
    case appStartupResolved = "app_startup_resolved"
    case activitySetupViewed = "activity_setup_viewed"
    case activityConfigurationChanged = "activity_configuration_changed"
    case activityStarted = "activity_started"
    case activityPaused = "activity_paused"
    case activityResumed = "activity_resumed"
    case activityFinished = "activity_finished"
    case activitySaved = "activity_saved"
    case activitySaveIneligibleShown = "activity_save_ineligible_shown"
    case postWorkoutStretchOffered = "post_workout_stretch_offered"
    case postWorkoutStretchStarted = "post_workout_stretch_started"
    case postWorkoutStretchCompleted = "post_workout_stretch_completed"
    case postWorkoutStretchDismissed = "post_workout_stretch_dismissed"
    case activityDiscardPrompted = "activity_discard_prompted"
    case activityDiscarded = "activity_discarded"
    case activityDeleted = "activity_deleted"
    case activityDetailOpened = "activity_detail_opened"
    case activityRecognitionViewed = "activity_recognition_viewed"
    case activitySplitsViewed = "activity_splits_viewed"
    case activitySharePreviewed = "activity_share_previewed"
    case activityShareAction = "activity_share_action"
    case activitySyncCompleted = "activity_sync_completed"
    case activitySyncFailed = "activity_sync_failed"
    case recognitionSyncCompleted = "recognition_sync_completed"
    case recognitionSyncFailed = "recognition_sync_failed"
    case recognitionAwarded = "recognition_awarded"
    case activityRecordingQuality = "activity_recording_quality"
    case activityElevationCorrectionCompleted = "activity_elevation_correction_completed"
    case activityFeedLoaded = "activity_feed_loaded"
    case activityRecoveryPresentation = "activity_recovery_presentation"
    case activityPhotoRecovery = "activity_photo_recovery"
    case activitySimulationStarted = "activity_simulation_started"
    case activitySimulationControlUsed = "activity_simulation_control_used"
    case liveActivityReconciled = "live_activity_reconciled"
    case liveWorkoutPanelDisplayChanged = "live_workout_panel_display_changed"
    case watchFeatureExposed = "watch_feature_exposed"
    case watchConnectionAttempted = "watch_connection_attempted"
    case watchConnectionResult = "watch_connection_result"
    case watchWorkoutOrigin = "watch_workout_origin"
    case watchFirstLiveHeartRateReceived = "watch_first_live_heart_rate_received"
    case watchDisconnected = "watch_disconnected"
    case watchReconnected = "watch_reconnected"
    case watchControlUsed = "watch_control_used"
    case watchWorkoutSaveResult = "watch_workout_save_result"
    case watchPhoneOnlyFallback = "watch_phone_only_fallback"
    case paginatedListPageLoaded = "paginated_list_page_loaded"
    case meDestinationOpened = "me_destination_opened"
    case progressSurfaceOpened = "progress_surface_opened"
    case progressControlChanged = "progress_control_changed"
    case progressInsightsExposed = "progress_insights_exposed"
    case connectionsOpened = "connections_opened"
    case connectionsSearchCompleted = "connections_search_completed"
    case socialProfileOpened = "social_profile_opened"
    case socialInboxOpened = "social_inbox_opened"
    case socialTabExposed = "social_tab_exposed"
    case socialTabSelected = "social_tab_selected"
    case socialTabBadgeExposed = "social_tab_badge_exposed"
    case socialTabBadgeSelected = "social_tab_badge_selected"
    case socialTabBadgeCleared = "social_tab_badge_cleared"
    case socialActiveNowExposed = "social_active_now_exposed"
    case socialActiveNowSelected = "social_active_now_selected"
    case socialUpcomingExposed = "social_upcoming_exposed"
    case socialUpcomingSelected = "social_upcoming_selected"
    case socialDiscoveryActionSelected = "social_discovery_action_selected"
    case socialFeedFirstCardVisible = "social_feed_first_card_visible"
    case notificationCenterOpened = "notification_center_opened"
    case notificationSectionExposed = "notification_section_exposed"
    case notificationActionSelected = "notification_action_selected"
    case profileQRCodeOpened = "profile_qr_code_opened"
    case connectionQRCodeRequestResult = "connection_qr_code_request_result"
    case socialOperationFailed = "social_operation_failed"
    case groupSectionExposed = "group_section_exposed"
    case groupOpened = "group_opened"
    case groupMembershipChanged = "group_membership_changed"
    case groupCreationStarted = "group_creation_started"
    case groupCreationCompleted = "group_creation_completed"
    case groupCreationFailed = "group_creation_failed"
    case groupInvitationSent = "group_invitation_sent"
    case groupInvitationAccepted = "group_invitation_accepted"
    case groupInvitationDeclined = "group_invitation_declined"
    case groupInvitationCancelled = "group_invitation_cancelled"
    case groupActivated = "group_activated"
    case groupFocusChanged = "group_focus_changed"
    case groupThemeChanged = "group_theme_changed"
    case groupTargetChanged = "group_target_changed"
    case groupProgressOpened = "group_progress_opened"
    case groupCheerSent = "group_cheer_sent"
    case groupCheerRemoved = "group_cheer_removed"
    case groupPlanActivityStarted = "group_plan_activity_started"
    case groupPlanActivityCompleted = "group_plan_activity_completed"
    case groupActivityContributionReconciled = "group_activity_contribution_reconciled"
    case groupWeeklyFocusCompleted = "group_weekly_focus_completed"
    case groupNotificationsChanged = "group_notifications_changed"
    case groupNameChanged = "group_name_changed"
    case groupCalendarChanged = "group_calendar_changed"
    case groupOwnershipTransferred = "group_ownership_transferred"
    case groupMemberLeft = "group_member_left"
    case groupMemberRemoved = "group_member_removed"
    case groupArchived = "group_archived"
    case groupReactivated = "group_reactivated"
    case groupOperationFailed = "group_operation_failed"
    case activityEventDetailOpened = "activity_event_detail_opened"
    case activityEventLocationSelected = "activity_event_location_selected"
    case goalProgressReached = "goal_progress_reached"
    case goalEditorOpened = "goal_editor_opened"
    case featureExposed = "feature_exposed"
    case assistantLauncherEligibleExposure = "assistant_launcher_eligible_exposure"
    case assistantLauncherAnimationShown = "assistant_launcher_animation_shown"
    case assistantLauncherOpened = "assistant_launcher_opened"
    case assistantMeaningfulEngagement = "assistant_meaningful_engagement"
    case todayCardDisplayChanged = "today_card_display_changed"
    case todayAdjustmentDecided = "today_adjustment_decided"
    case planningSurfaceOpened = "planning_surface_opened"
    case trainingPlanEnded = "training_plan_ended"
    case musicAuthorizationRequested = "music_authorization_requested"
    case musicAuthorizationCompleted = "music_authorization_completed"
    case motionAuthorizationRequested = "motion_authorization_requested"
    case motionAuthorizationCompleted = "motion_authorization_completed"
    case musicQuickPickSelected = "music_quick_pick_selected"
    case musicPlaybackStarted = "music_playback_started"
    case musicPlaybackRecoveryCompleted = "music_playback_recovery_completed"
    case musicControlUsed = "music_control_used"
    case musicOperationFailed = "music_operation_failed"
    case routeLibraryOpened = "route_library_opened"
    case routeLibraryRefreshed = "route_library_refreshed"
    case routeSelected = "route_selected"
    case routeRemoved = "route_removed"
    case routePublishStarted = "route_publish_started"
    case routePublishCompleted = "route_publish_completed"
    case routePublishFailed = "route_publish_failed"
    case routeBookmarkChanged = "route_bookmark_changed"
    case routePublicationRemoved = "route_publication_removed"
    case routeImportDeleted = "route_import_deleted"
    case routeNavigationStarted = "route_navigation_started"
    case routeDisplayed = "route_displayed"
    case routeDeviationDetected = "route_deviation_detected"
    case routeRejoined = "route_rejoined"
    case routeWrongWayDetected = "route_wrong_way_detected"
    case routeGuidanceProgressReached = "route_guidance_progress_reached"
    case routeGuidanceArrived = "route_guidance_arrived"
    case routeGuidanceRecovered = "route_guidance_recovered"
    case routeGuidanceCompleted = "route_guidance_completed"
    case shoeSelected = "shoe_selected"
    case photoCaptureAttempted = "photo_capture_attempted"
    case photoCaptured = "photo_captured"
    case photoPreviewed = "photo_previewed"
    case photoZoomed = "photo_zoomed"
    case photoRemoved = "photo_removed"
    case photoReordered = "photo_reordered"
    case photoAlbumExportCompleted = "photo_album_export_completed"
    case groupRunCreateAttempted = "group_run_create_attempted"
    case groupRunCreated = "group_run_created"
    case groupRunJoinAttempted = "group_run_join_attempted"
    case groupRunJoined = "group_run_joined"
    case groupRunInviteShared = "group_run_invite_shared"
    case liveCheerInvitationConfigured = "live_cheer_invitation_configured"
    case liveCheerFollowerOpened = "live_cheer_follower_opened"
    case liveVoiceCheerSent = "live_voice_cheer_sent"
    case liveVoiceCheerPlayed = "live_voice_cheer_played"
    case liveVoiceCheerAcknowledged = "live_voice_cheer_acknowledged"
    case rewardsCenterOpened = "rewards_center_opened"
    case rewardCodeRedeemed = "reward_code_redeemed"
    case referralCodeShared = "referral_code_shared"
    case referralCodeCopied = "referral_code_copied"
    case subscriptionPaywallOpened = "subscription_paywall_opened"
    case subscriptionCustomerCenterOpened = "subscription_customer_center_opened"
    case subscriptionReconciled = "subscription_reconciled"
    case liveGuidanceMomentDetected = "live_guidance_moment_detected"
    case liveGuidanceCueSpoken = "live_guidance_cue_spoken"
    case liveGuidanceCueEvaluated = "live_guidance_cue_evaluated"
    case liveGuidanceChallengeSelected = "live_guidance_challenge_selected"
    case liveGuidanceFeedbackSubmitted = "live_guidance_feedback_submitted"
    case liveGuidanceProviderResult = "live_guidance_provider_result"
    case liveGuidanceAudioFirstByte = "live_guidance_audio_first_byte"
    case liveGuidanceAudioPlaybackRoute = "live_guidance_audio_playback_route"
    case liveGuidanceFixedAudioUnavailable = "live_guidance_fixed_audio_unavailable"
    case liveGuidanceVoiceSelected = "live_guidance_voice_selected"
    case pushNotificationOpened = "push_notification_opened"
    case workoutReminderSettingChanged = "workout_reminder_setting_changed"
    case workoutReminderPermissionResult = "workout_reminder_permission_result"
    case workoutReminderScheduleChanged = "workout_reminder_schedule_changed"
    case workoutReminderOpened = "workout_reminder_opened"
    case workoutStartedFromReminder = "workout_started_from_reminder"
    case onboardingIdentityPromptViewed = "onboarding_identity_prompt_viewed"
    case onboardingIdentityCompleted = "onboarding_identity_completed"
    case onboardingTrainingProfileViewed = "onboarding_training_profile_viewed"
    case onboardingTrainingProfileCompleted = "onboarding_training_profile_completed"
    case onboardingResolved = "onboarding_resolved"
    case planBuilderOpened = "plan_builder_opened"
    case planBuilderExited = "plan_builder_exited"
    case planCreationCompleted = "plan_creation_completed"
    case planIntakeContextLoaded = "plan_intake_context_loaded"
    case planIntakeGoalInterpreted = "plan_intake_goal_interpreted"
    case planIntakeAnswerEdited = "plan_intake_answer_edited"
    case planIntakeBaselineConfirmed = "plan_intake_baseline_confirmed"
    case authenticationSessionRecovered = "authentication_session_recovered"
    case accountTransferIntentCreated = "account_transfer_intent_created"
    case accountTransferShared = "account_transfer_shared"
    case legalDocumentOpened = "legal_document_opened"
    case termsAcceptancePresented = "terms_acceptance_presented"
    case termsAcceptanceCompleted = "terms_acceptance_completed"
    case healthConnectionRequested = "health_connection_requested"
    case healthConnectionCompleted = "health_connection_completed"
    case healthImportPromptViewed = "health_import_prompt_viewed"
    case healthImportCompleted = "health_import_completed"
    case stravaImportPromptViewed = "strava_import_prompt_viewed"
    case stravaImportCompleted = "strava_import_completed"
    case feedbackReporterOpened = "feedback_reporter_opened"
    case feedbackReportSubmitted = "feedback_report_submitted"
    case preferenceChanged = "preference_changed"
}

enum ProductPropertyKey: String, Sendable, CaseIterable {
    case schemaVersion = "schema_version"
    case appVersion = "app_version"
    case appBuild = "app_build"
    case osMajorVersion = "os_major_version"
    case language = "language"
    case authenticationState = "authentication_state"
    case destination
    case entrySource = "entry_source"
    case feature
    case section
    case category
    case changeType = "change_type"
    case selectionType = "selection_type"
    case sourceType = "source_type"
    case stepName = "step_name"
    case timestampSource = "timestamp_source"
    case direction
    case activityType = "activity_type"
    case routineID = "routine_id"
    case goalType = "goal_type"
    case targetBucket = "target_bucket"
    case progressPercent = "progress_percent"
    case musicEnabled = "music_enabled"
    case routeSelected = "route_selected"
    case shoeSelected = "shoe_selected"
    case preRunPhotoAdded = "pre_run_photo_added"
    case locationAttached = "location_attached"
    case groupRunEnabled = "group_run_enabled"
    case liveShareEnabled = "live_share_enabled"
    case indoor
    case voiceGuideEnabled = "voice_guide_enabled"
    case dogCompanionEnabled = "dog_companion_enabled"
    case durationBucket = "duration_bucket"
    case distanceBucket = "distance_bucket"
    case photoCountBucket = "photo_count_bucket"
    case participantCountBucket = "participant_count_bucket"
    case countBucket = "count_bucket"
    case pageDepthBucket = "page_depth_bucket"
    case queryLengthBucket = "query_length_bucket"
    case inputScript = "input_script"
    case matchMode = "match_mode"
    case goalCompletionBucket = "goal_completion_bucket"
    case control
    case result
    case errorCategory = "error_category"
    case momentType = "moment_type"
    case coachingContract = "coaching_contract"
    case cueCountBucket = "cue_count_bucket"
    case audioMode = "audio_mode"
    case accessReason = "access_reason"
    case latencyBucket = "latency_bucket"
    case missingDisplayName = "missing_display_name"
    case missingEmail = "missing_email"
    case locationQuality = "location_quality"
    case precisionMode = "precision_mode"
    case filterRatioBucket = "filter_ratio_bucket"
    case distanceCorrectionBucket = "distance_correction_bucket"
    case segmentCountBucket = "segment_count_bucket"
    case motionBridgeUsed = "motion_bridge_used"
    case routeMatchResult = "route_match_result"
    case documentType = "document_type"
    case termsVersion = "terms_version"
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
        .appStartupResolved: [.destination, .latencyBucket, .sourceType],
        .activitySetupViewed: [.entrySource],
        .activityConfigurationChanged: [.changeType, .selectionType, .activityType, .goalType, .targetBucket, .sourceType],
        .activityStarted: [.entrySource, .activityType, .goalType, .targetBucket, .musicEnabled, .routeSelected, .shoeSelected, .preRunPhotoAdded, .groupRunEnabled, .liveShareEnabled, .indoor, .voiceGuideEnabled, .dogCompanionEnabled, .participantCountBucket],
        .activityPaused: [.sourceType],
        .activityResumed: [.sourceType, .durationBucket],
        .activityFinished: [.durationBucket, .distanceBucket, .goalCompletionBucket],
        .activitySaved: [.activityType, .goalType, .durationBucket, .distanceBucket, .photoCountBucket, .goalCompletionBucket, .musicEnabled, .routeSelected, .shoeSelected, .groupRunEnabled, .indoor, .dogCompanionEnabled],
        .activitySaveIneligibleShown: [.activityType, .durationBucket, .distanceBucket],
        .activityDiscardPrompted: [.durationBucket, .distanceBucket, .photoCountBucket, .goalCompletionBucket],
        .activityDiscarded: [.durationBucket, .distanceBucket, .photoCountBucket, .goalCompletionBucket],
        .activityDeleted: [.sourceType, .countBucket],
        .activityDetailOpened: [.sourceType],
        .activityRecognitionViewed: [.sourceType, .countBucket],
        .activitySplitsViewed: [.sourceType, .countBucket],
        .activitySharePreviewed: [.sourceType],
        .activityShareAction: [.sourceType, .result],
        .activitySyncCompleted: [.sourceType, .routeSelected],
        .activitySyncFailed: [.sourceType, .routeSelected, .errorCategory],
        .recognitionSyncCompleted: [.countBucket, .sourceType],
        .recognitionSyncFailed: [.sourceType, .errorCategory],
        .recognitionAwarded: [.countBucket, .sourceType],
        .activityRecordingQuality: [
            .sourceType, .countBucket, .result, .locationQuality, .precisionMode,
            .filterRatioBucket, .distanceCorrectionBucket, .segmentCountBucket,
            .motionBridgeUsed, .routeMatchResult
        ],
        .activityElevationCorrectionCompleted: [.result, .sourceType, .latencyBucket, .errorCategory],
        .activityFeedLoaded: [.countBucket, .sourceType, .timestampSource],
        .activityRecoveryPresentation: [.result, .sourceType, .countBucket],
        .activityPhotoRecovery: [.countBucket, .preRunPhotoAdded],
        .activitySimulationStarted: [.sourceType, .distanceBucket, .selectionType],
        .activitySimulationControlUsed: [.control, .selectionType],
        .liveActivityReconciled: [.result],
        .liveWorkoutPanelDisplayChanged: [.selectionType, .sourceType],
        .watchFeatureExposed: [.sourceType],
        .watchConnectionAttempted: [.sourceType],
        .watchConnectionResult: [.sourceType, .result, .errorCategory, .latencyBucket],
        .watchWorkoutOrigin: [.sourceType],
        .watchFirstLiveHeartRateReceived: [.sourceType, .latencyBucket],
        .watchDisconnected: [.sourceType, .result, .errorCategory],
        .watchReconnected: [.sourceType, .result],
        .watchControlUsed: [.sourceType, .control],
        .watchWorkoutSaveResult: [.sourceType, .result, .errorCategory],
        .watchPhoneOnlyFallback: [.sourceType, .result, .errorCategory],
        .paginatedListPageLoaded: [.sourceType, .countBucket, .pageDepthBucket],
        .meDestinationOpened: [.destination, .entrySource],
        .progressSurfaceOpened: [.entrySource, .countBucket],
        .progressControlChanged: [.control, .selectionType],
        .progressInsightsExposed: [.countBucket, .sourceType],
        .connectionsOpened: [.entrySource],
        .connectionsSearchCompleted: [.sourceType, .inputScript, .queryLengthBucket, .countBucket, .matchMode, .result],
        .socialProfileOpened: [.entrySource],
        .socialInboxOpened: [.entrySource],
        .socialTabExposed: [.selectionType, .entrySource],
        .socialTabSelected: [.selectionType, .entrySource],
        .socialTabBadgeExposed: [.selectionType, .sourceType],
        .socialTabBadgeSelected: [.selectionType, .sourceType],
        .socialTabBadgeCleared: [.selectionType, .sourceType],
        .socialActiveNowExposed: [.countBucket],
        .socialActiveNowSelected: [.selectionType, .entrySource],
        .socialUpcomingExposed: [.countBucket, .sourceType],
        .socialUpcomingSelected: [.selectionType, .entrySource],
        .socialDiscoveryActionSelected: [.selectionType, .entrySource],
        .socialFeedFirstCardVisible: [.sourceType],
        .notificationCenterOpened: [.countBucket],
        .notificationSectionExposed: [.section, .countBucket],
        .notificationActionSelected: [.section, .category, .selectionType, .countBucket],
        .profileQRCodeOpened: [.entrySource],
        .connectionQRCodeRequestResult: [.result],
        .socialOperationFailed: [.sourceType, .errorCategory],
        .liveCheerInvitationConfigured: [.participantCountBucket],
        .liveCheerFollowerOpened: [.entrySource, .selectionType],
        .liveVoiceCheerSent: [.result, .durationBucket],
        .liveVoiceCheerPlayed: [.countBucket],
        .liveVoiceCheerAcknowledged: [.result],
        .rewardsCenterOpened: [],
        .rewardCodeRedeemed: [.sourceType, .result],
        .referralCodeShared: [.sourceType, .selectionType],
        .referralCodeCopied: [.sourceType, .selectionType],
        .subscriptionPaywallOpened: [.entrySource],
        .subscriptionCustomerCenterOpened: [.entrySource],
        .subscriptionReconciled: [.sourceType, .result],
        .groupSectionExposed: [.entrySource, .participantCountBucket],
        .groupSectionExposed: [.entrySource, .participantCountBucket],
        .groupOpened: [.entrySource, .selectionType, .participantCountBucket],
        .groupMembershipChanged: [.entrySource, .selectionType, .result, .participantCountBucket],
        .groupCreationStarted: [.entrySource],
        .groupCreationCompleted: [.entrySource, .participantCountBucket],
        .groupCreationFailed: [.entrySource, .errorCategory],
        .groupInvitationSent: [.entrySource, .participantCountBucket, .result],
        .groupInvitationAccepted: [.entrySource, .participantCountBucket],
        .groupInvitationDeclined: [.entrySource],
        .groupInvitationCancelled: [.entrySource],
        .groupActivated: [.participantCountBucket],
        .groupFocusChanged: [.selectionType, .sourceType],
        .groupThemeChanged: [.selectionType, .sourceType],
        .groupTargetChanged: [.selectionType, .targetBucket, .sourceType],
        .groupProgressOpened: [.entrySource, .selectionType, .participantCountBucket],
        .groupCheerSent: [.selectionType],
        .groupCheerRemoved: [.selectionType],
        .groupPlanActivityStarted: [.entrySource, .participantCountBucket],
        .groupPlanActivityCompleted: [.participantCountBucket, .result],
        .groupActivityContributionReconciled: [.selectionType, .participantCountBucket, .result],
        .groupWeeklyFocusCompleted: [.selectionType, .participantCountBucket],
        .groupNotificationsChanged: [.selectionType],
        .groupNameChanged: [],
        .groupCalendarChanged: [.sourceType],
        .groupOwnershipTransferred: [.participantCountBucket],
        .groupMemberLeft: [.participantCountBucket],
        .groupMemberRemoved: [.participantCountBucket],
        .groupArchived: [.participantCountBucket],
        .groupReactivated: [.participantCountBucket],
        .groupOperationFailed: [.sourceType, .errorCategory],
        .activityEventDetailOpened: [.entrySource],
        .activityEventLocationSelected: [.sourceType],
        .goalProgressReached: [.activityType, .goalType, .progressPercent],
        .goalEditorOpened: [.activityType, .goalType],
        .featureExposed: [.feature],
        .assistantLauncherEligibleExposure: [.destination, .entrySource],
        .assistantLauncherAnimationShown: [.destination, .entrySource],
        .assistantLauncherOpened: [.destination, .entrySource],
        .assistantMeaningfulEngagement: [.destination, .entrySource],
        .todayCardDisplayChanged: [.sourceType, .selectionType],
        .planningSurfaceOpened: [.sourceType, .entrySource, .countBucket],
        .trainingPlanEnded: [.entrySource],
        .musicAuthorizationRequested: [],
        .musicAuthorizationCompleted: [.result],
        .motionAuthorizationRequested: [],
        .motionAuthorizationCompleted: [.result],
        .musicQuickPickSelected: [.selectionType],
        .musicPlaybackStarted: [.result],
        .musicPlaybackRecoveryCompleted: [.result, .sourceType],
        .musicControlUsed: [.control],
        .musicOperationFailed: [.errorCategory],
        .routeLibraryOpened: [],
        .routeLibraryRefreshed: [.sourceType, .result],
        .routeSelected: [.sourceType, .distanceBucket],
        .routeRemoved: [.sourceType],
        .routePublishStarted: [.entrySource],
        .routePublishCompleted: [.entrySource],
        .routePublishFailed: [.entrySource, .errorCategory],
        .routeBookmarkChanged: [.result],
        .routePublicationRemoved: [.result],
        .routeImportDeleted: [.result],
        .routeNavigationStarted: [.sourceType, .distanceBucket, .direction],
        .routeDisplayed: [.sourceType],
        .routeDeviationDetected: [.distanceBucket],
        .routeRejoined: [],
        .routeWrongWayDetected: [.sourceType, .direction],
        .routeGuidanceProgressReached: [.sourceType, .direction, .progressPercent],
        .routeGuidanceArrived: [.sourceType, .direction],
        .routeGuidanceRecovered: [.sourceType, .direction, .progressPercent],
        .routeGuidanceCompleted: [.sourceType, .direction, .progressPercent, .result],
        .shoeSelected: [.selectionType],
        .photoCaptureAttempted: [.sourceType],
        .photoCaptured: [.sourceType, .locationAttached],
        .photoPreviewed: [.sourceType],
        .photoZoomed: [.sourceType, .control],
        .photoRemoved: [.sourceType],
        .photoReordered: [.sourceType],
        .photoAlbumExportCompleted: [.result, .sourceType, .countBucket],
        .groupRunCreateAttempted: [],
        .groupRunCreated: [.participantCountBucket],
        .groupRunJoinAttempted: [],
        .groupRunJoined: [.participantCountBucket],
        .groupRunInviteShared: [.participantCountBucket],
        .liveGuidanceMomentDetected: [.momentType, .coachingContract],
        .liveGuidanceCueSpoken: [.momentType, .coachingContract],
        .liveGuidanceCueEvaluated: [.momentType, .result],
        .liveGuidanceChallengeSelected: [.selectionType],
        .liveGuidanceFeedbackSubmitted: [.selectionType, .cueCountBucket],
        .liveGuidanceProviderResult: [.sourceType, .result, .audioMode, .accessReason, .latencyBucket],
        .liveGuidanceAudioFirstByte: [.sourceType, .latencyBucket],
        .liveGuidanceAudioPlaybackRoute: [.sourceType],
        .liveGuidanceVoiceSelected: [.selectionType, .sourceType],
        .pushNotificationOpened: [.sourceType, .selectionType],
        .workoutReminderSettingChanged: [.selectionType],
        .workoutReminderPermissionResult: [.result],
        .workoutReminderScheduleChanged: [.result, .sourceType],
        .workoutReminderOpened: [.destination],
        .workoutStartedFromReminder: [.sourceType],
        .onboardingIdentityPromptViewed: [.missingDisplayName, .missingEmail],
        .onboardingIdentityCompleted: [.missingDisplayName, .missingEmail],
        .onboardingTrainingProfileViewed: [],
        .onboardingTrainingProfileCompleted: [.result, .sourceType],
        .onboardingResolved: [.result],
        .planBuilderOpened: [.entrySource],
        .planBuilderExited: [.stepName],
        .planCreationCompleted: [.result, .latencyBucket, .goalType, .countBucket, .errorCategory],
        .planIntakeContextLoaded: [.sourceType],
        .planIntakeGoalInterpreted: [.result, .sourceType, .errorCategory],
        .planIntakeAnswerEdited: [.selectionType, .sourceType],
        .planIntakeBaselineConfirmed: [.result, .sourceType],
        .authenticationSessionRecovered: [.result],
        .accountTransferIntentCreated: [.result, .errorCategory],
        .accountTransferShared: [.sourceType],
        .legalDocumentOpened: [.documentType, .entrySource],
        .termsAcceptancePresented: [.termsVersion],
        .termsAcceptanceCompleted: [.termsVersion, .result],
        .healthConnectionRequested: [],
        .healthConnectionCompleted: [.result],
        .healthImportPromptViewed: [.sourceType],
        .healthImportCompleted: [.result, .sourceType, .selectionType, .control, .countBucket],
        .stravaImportPromptViewed: [.sourceType],
        .stravaImportCompleted: [.result, .sourceType, .selectionType, .control, .countBucket],
        .feedbackReporterOpened: [.entrySource, .result],
        .feedbackReportSubmitted: [.result, .selectionType],
        .preferenceChanged: [.changeType, .selectionType]
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
    static func latency(milliseconds: Double) -> String {
        switch max(0, milliseconds) {
        case ..<250: "under_250ms"
        case ..<1_000: "250ms_1s"
        case ..<3_000: "1s_3s"
        case ..<8_000: "3s_8s"
        default: "8s_plus"
        }
    }

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

    static func locationPointCount(_ count: Int) -> String {
        return switch max(0, count) {
        case 0: "0"
        case 1: "1"
        case 2..<10: "2_9"
        case 10..<50: "10_49"
        case 50..<200: "50_199"
        default: "200_plus"
        }
    }

    static func locationFilterRatio(accepted: Int, rejected: Int, stationary: Int) -> String {
        let total = accepted + rejected + stationary
        guard total > 0 else { return "none" }
        let ratio = Double(rejected + stationary) / Double(total)
        return switch ratio {
        case ..<0.05: "under_5"
        case ..<0.20: "5_19"
        case ..<0.50: "20_49"
        default: "50_plus"
        }
    }

    static func distanceCorrection(percent: Double) -> String {
        return switch max(0, percent) {
        case 0: "none"
        case ..<1: "under_1"
        case ..<3: "1_2"
        case ..<10: "3_9"
        default: "10_plus"
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

    static func pageDepth(_ page: Int) -> String {
        return switch max(1, page) {
        case 1: "1"
        case 2: "2"
        case 3...4: "3_4"
        default: "5_plus"
        }
    }
}
