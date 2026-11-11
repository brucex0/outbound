package com.plainstride.outbound

import com.plainstride.outbound.core.model.activity.resolveTarget

import com.plainstride.outbound.feature.recording.recordingLaunch

import androidx.navigation.navArgument
import androidx.navigation.NavType
import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.calculateEndPadding
import androidx.compose.foundation.layout.calculateStartPadding
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.material3.Switch
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Surface
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Today
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Groups2
import androidx.compose.material.icons.filled.CloudOff
import androidx.compose.material.icons.outlined.PeopleAlt
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.LifecycleEventObserver
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.plainstride.outbound.auth.AuthMessage
import com.plainstride.outbound.auth.AuthOperation
import com.plainstride.outbound.auth.AuthUiState
import com.plainstride.outbound.auth.AuthViewModel
import com.plainstride.outbound.connectivity.ConnectivityViewModel
import com.plainstride.outbound.connectivity.ConnectivityUiState
import com.plainstride.outbound.core.auth.SessionState
import com.plainstride.outbound.core.designsystem.LocalPlainstrideThemeColors
import com.plainstride.outbound.core.designsystem.PrimaryBottomToolbarClearance
import com.plainstride.outbound.feature.activity.ActivityDetailDestination
import com.plainstride.outbound.feature.activity.ActivityHistoryRoute
import com.plainstride.outbound.feature.activity.ActivityMessage
import com.plainstride.outbound.feature.activity.ActivityViewModel
import com.plainstride.outbound.feature.activity.RecentActivitiesRoute
import com.plainstride.outbound.reminders.ReminderSettingsRow
import com.plainstride.outbound.feature.onboarding.OnboardingEffect
import com.plainstride.outbound.feature.onboarding.OnboardingRoute
import com.plainstride.outbound.feature.onboarding.PlanBuilderSource
import com.plainstride.outbound.feature.onboarding.R as OnboardingR
import com.plainstride.outbound.feature.today.TodayMessage
import com.plainstride.outbound.feature.today.TodayRoute
import com.plainstride.outbound.feature.today.TodayViewModel
import com.plainstride.outbound.feature.today.R as TodayR
import com.plainstride.outbound.feature.settings.MeRoute
import com.plainstride.outbound.feature.settings.SettingsMessage
import com.plainstride.outbound.feature.settings.SettingsViewModel
import com.plainstride.outbound.feature.settings.MeInsight
import com.plainstride.outbound.feature.settings.MeMilestone
import com.plainstride.outbound.feature.settings.SettingsGroupTitle
import com.plainstride.outbound.feature.settings.R as SettingsR
import com.plainstride.outbound.feature.recording.ActivityPhotoAlbumExportResult
import com.plainstride.outbound.feature.recording.RecordedActivityReview
import com.plainstride.outbound.feature.recording.RecordingGoal
import com.plainstride.outbound.feature.recording.RecordingGoalType
import com.plainstride.outbound.feature.recording.RecordingLaunchConfiguration
import com.plainstride.outbound.feature.recording.StretchSessionRoute
import com.plainstride.outbound.feature.recording.StretchLaunchContext
import com.plainstride.outbound.feature.recording.StretchEntryPoint
import com.plainstride.outbound.feature.recording.RecordingRoute
import com.plainstride.outbound.feature.recording.ActivityStartWarmup
import com.plainstride.outbound.feature.recording.RecordingViewModel
import com.plainstride.outbound.feature.recording.ActivityKind
import com.plainstride.outbound.feature.recording.ActiveRecordingViewModel
import com.plainstride.outbound.feature.recording.FollowedRouteConfiguration
import com.plainstride.outbound.feature.recording.RecordingRoutePoint
import com.plainstride.outbound.feature.recording.LocationPermissionState
import com.plainstride.outbound.feature.recording.StructuredWorkoutStep
import com.plainstride.outbound.feature.livecoach.LiveCoachRecordingEffect
import com.plainstride.outbound.feature.livecoach.LiveCoachSettingsSection
import com.plainstride.outbound.feature.assistant.AssistantRoute
import com.plainstride.outbound.feature.assistant.MusicRoute
import com.plainstride.outbound.core.assistant.VoiceSport
import com.plainstride.outbound.feature.social.SocialRoute
import com.plainstride.outbound.feature.social.SocialViewModel
import com.plainstride.outbound.feature.social.SocialActivityDetailDestination
import com.plainstride.outbound.feature.social.SocialActivityEventDestination
import com.plainstride.outbound.feature.social.SocialProfileDestination
import com.plainstride.outbound.feature.social.ConnectionsDestination
import com.plainstride.outbound.feature.social.ConnectionScannerDestination
import com.plainstride.outbound.feature.social.SocialGroupDestination
import com.plainstride.outbound.feature.social.SocialInvitationDestination
import com.plainstride.outbound.feature.social.GroupInviteDestination
import com.plainstride.outbound.feature.social.SocialPerson
import com.plainstride.outbound.feature.social.R as SocialR
import com.plainstride.outbound.feature.today.WorkoutLaunchIntent
import com.plainstride.outbound.feature.today.TodayManualLaunch
import com.plainstride.outbound.feature.today.TodayActivityChoice
import com.plainstride.outbound.feature.today.TodayGoalChoice
import com.plainstride.outbound.feature.today.TodayShoeOption
import com.plainstride.outbound.feature.today.TodayRouteSelection
import com.plainstride.outbound.core.designsystem.MapCoordinate
import com.plainstride.outbound.core.model.Modality
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.feature.community.CommunityRouteDetailDestination
import com.plainstride.outbound.feature.community.CommunityRouteScreen
import com.plainstride.outbound.feature.community.RouteScope
import com.plainstride.outbound.feature.community.guidancePoints
import com.plainstride.outbound.feature.health.*
import com.plainstride.outbound.feature.progress.ProgressRoute
import com.plainstride.outbound.feature.progress.ProgressUnitSystem
import com.plainstride.outbound.feature.progress.AddShoeSheet
import com.plainstride.outbound.feature.progress.GearSettingsSection
import com.plainstride.outbound.feature.progress.NewShoe
import com.plainstride.outbound.feature.progress.R as ProgressR
import com.plainstride.outbound.feature.safety.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.rememberLauncherForActivityResult
import android.content.Intent
import android.provider.Settings
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import com.plainstride.outbound.reminders.ReminderViewModel

private enum class TopLevelDestination(
    val route: String,
    @param:StringRes val label: Int,
    @param:StringRes val headline: Int,
    @param:StringRes val body: Int,
) {
    Social("social", R.string.tab_social, R.string.social_headline, R.string.social_body),
    Today("today", R.string.tab_today, R.string.today_headline, R.string.today_body),
    Me("me", R.string.tab_me, R.string.me_headline, R.string.me_body),
}

@Composable
fun PlainstrideApp(
    settingsViewModel: SettingsViewModel,
    transferCode: String? = null,
    onTransferCodeConsumed: () -> Unit = {},
    navigationUri: android.net.Uri? = null,
    onNavigationUriConsumed: () -> Unit = {},
    connectionCode: String? = null,
    onConnectionCodeConsumed: () -> Unit = {},
    groupInviteToken: String? = null,
    onGroupInviteConsumed: () -> Unit = {},
) {
    val authViewModel: AuthViewModel = hiltViewModel()
    val authState by authViewModel.state.collectAsStateWithLifecycle()
    val snackbar = remember { SnackbarHostState() }
    val resources = LocalResources.current
    LaunchedEffect(authViewModel) {
        authViewModel.messages.collect { snackbar.showSnackbar(resources.getString(authMessageResource(it))) }
    }
    when (authState.session) {
        SessionState.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        SessionState.SignedOut -> SignInScreen(authState, authViewModel, snackbar, transferCode, onTransferCodeConsumed)
        is SessionState.SignedIn, is SessionState.Refreshing -> SignedInApp(
            authState,
            authViewModel,
            settingsViewModel,
            snackbar,
            navigationUri,
            onNavigationUriConsumed,
            connectionCode,
            onConnectionCodeConsumed,
            groupInviteToken,
            onGroupInviteConsumed,
        )
    }
}

@Composable
private fun SignedInApp(
    authState: AuthUiState,
    authViewModel: AuthViewModel,
    settingsViewModel: SettingsViewModel,
    snackbar: SnackbarHostState,
    navigationUri: android.net.Uri?,
    onNavigationUriConsumed: () -> Unit,
    connectionCode: String?,
    onConnectionCodeConsumed: () -> Unit,
    groupInviteToken: String?,
    onGroupInviteConsumed: () -> Unit,
) {
    val settingsState by settingsViewModel.state.collectAsStateWithLifecycle()
    val measurementUnitSystem = if (settingsState.preferences.measurement == com.plainstride.outbound.feature.settings.MeasurementSystem.Imperial) {
        MeasurementUnitSystem.imperial
    } else {
        MeasurementUnitSystem.metric
    }
    var onboardingResolved by remember { mutableStateOf(false) }
    var forceOnboardingReplay by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val resources = LocalResources.current
    val scope = rememberCoroutineScope()
    val voicePreparation: com.plainstride.outbound.feature.livecoach.VoicePreparationViewModel = hiltViewModel()
    val voiceLocale = when (androidx.compose.ui.platform.LocalConfiguration.current.locales[0].language) {
        "zh" -> "zh-Hans"
        "es" -> "es"
        else -> "en"
    }
    DisposableEffect(when (val session = authState.session) {
        is SessionState.SignedIn -> session.accountId
        is SessionState.Refreshing -> session.accountId
        else -> null
    }, voiceLocale) {
        voicePreparation.activate(voiceLocale)
        onDispose { voicePreparation.preparation.stop() }
    }
    if (!onboardingResolved) {
        OnboardingRoute(
            onComplete = { onboardingResolved = true },
            forceReplay = forceOnboardingReplay,
            usesMetric = measurementUnitSystem == MeasurementUnitSystem.metric,
            onMessage = { effect ->
                val message = when (effect) {
                    OnboardingEffect.IdentityUnavailable -> R.string.onboarding_identity_unavailable
                    OnboardingEffect.HealthUnavailable -> R.string.onboarding_health_unavailable
                    OnboardingEffect.ProfileUnavailable -> R.string.onboarding_save_unavailable
                    OnboardingEffect.RunningScheduleConflict -> OnboardingR.string.planning_running_schedule_conflict
                    OnboardingEffect.ProgrammeTimelineConflict -> OnboardingR.string.planning_programme_timeline_conflict
                    OnboardingEffect.ProgrammeConstraintsConflict -> OnboardingR.string.planning_programme_constraints_conflict
                    OnboardingEffect.GoalTimelineUnrealistic -> OnboardingR.string.planning_goal_timeline_unrealistic
                    OnboardingEffect.PlanCreationUnavailable -> OnboardingR.string.plan_builder_create_error
                    OnboardingEffect.SkipUnavailable -> OnboardingR.string.plan_builder_skip_error
                    OnboardingEffect.Completed, OnboardingEffect.FailedOpen -> return@OnboardingRoute
                }
                scope.launch { snackbar.showSnackbar(resources.getString(message)) }
            },
        )
        return
    }
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    var selectedTab by rememberSaveable { mutableStateOf(TopLevelDestination.Today.route) }
    val tabStateHolder = rememberSaveableStateHolder()
    val currentRoute = if (backStackEntry?.destination?.route == APP_SHELL_ROUTE) selectedTab
        else backStackEntry?.destination?.route

    var recordingLaunch by remember { mutableStateOf(RecordingLaunchConfiguration()) }
    var selectingRouteForToday by rememberSaveable { mutableStateOf(false) }
    var reminderWorkoutId by remember { mutableStateOf<String?>(null) }
    var todayStartRequest by remember { mutableStateOf(0) }
    var todayRefreshRequest by remember { mutableStateOf(0) }
    var planBuilderSource by remember { mutableStateOf<PlanBuilderSource?>(null) }
    var assistantEntryDestination by remember { mutableStateOf("me") }
    var settingsRequest by remember { mutableStateOf(0) }
    var trackedAssistantExposure by remember { mutableStateOf(false) }
    var cheerPickerVisible by remember { mutableStateOf(false) }
    var addShoeSheetVisible by remember { mutableStateOf(false) }
    val recordingViewModel: RecordingViewModel = hiltViewModel()
    var todayStartJob by remember { mutableStateOf<kotlinx.coroutines.Job?>(null) }
    val activeRecordingViewModel:ActiveRecordingViewModel=hiltViewModel()
    val hasActiveSession by activeRecordingViewModel.active.collectAsStateWithLifecycle()
    var suppressRecordingRecovery by remember { mutableStateOf(false) }
    val accountId = when (val session = authState.session) {
        is SessionState.SignedIn -> session.accountId
        is SessionState.Refreshing -> session.accountId
        else -> null
    }
    remember(accountId) {
        com.plainstride.outbound.core.data.AccountConfigurationStore.activate(context, accountId)
        true
    }
    val cycleViewModel:CycleAwareViewModel=hiltViewModel()
    val cycleState by cycleViewModel.state.collectAsStateWithLifecycle()
    val healthViewModel:HealthIntegrationViewModel=hiltViewModel()
    val healthPermissions by healthViewModel.permissions.collectAsStateWithLifecycle()
    val integrationViewModel: P0IntegrationViewModel = hiltViewModel()
    fun selectTab(route: String) {
        if (selectedTab != route) integrationViewModel.trackPrimaryTabSelected(route)
        selectedTab = route
        // Tabs are state within the one shell, never navigation destinations.
        navController.popBackStack(APP_SHELL_ROUTE, inclusive = false)
    }
    val cheerPickerViewModel: SafetySettingsViewModel = hiltViewModel()
    val connectivityViewModel: ConnectivityViewModel = hiltViewModel()
    val connectivityState by connectivityViewModel.state.collectAsStateWithLifecycle()
    val rewardsViewModel: RewardsViewModel = hiltViewModel()
    val rewardsState by rewardsViewModel.state.collectAsStateWithLifecycle()
    val reminderViewModel: ReminderViewModel = hiltViewModel()
    val integration by integrationViewModel.state.collectAsStateWithLifecycle()
    val reminderEnabled by reminderViewModel.enabled.collectAsStateWithLifecycle()
    val notificationPermissionPreferences = remember(context) {
        context.getSharedPreferences("notification_permission", android.content.Context.MODE_PRIVATE)
    }
    var notificationPermissionRequested by remember {
        mutableStateOf(notificationPermissionPreferences.getBoolean("requested", false))
    }
    var showNotificationPermissionPrimer by rememberSaveable { mutableStateOf(false) }
    var pendingPushPermission by remember { mutableStateOf<Boolean?>(null) }
    var pendingReminderPermission by remember { mutableStateOf<Boolean?>(null) }
    var pushPermissionGranted by remember {
        mutableStateOf(
            notificationAccessAvailable(context),
        )
    }
    val pushPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val accessAvailable = granted && notificationAccessAvailable(context)
        pushPermissionGranted = accessAvailable
        notificationPermissionRequested = true
        notificationPermissionPreferences.edit().putBoolean("requested", true).apply()
        pendingPushPermission?.let { integrationViewModel.setPushEnabled(accessAvailable && it) }
        pendingPushPermission = null
        pendingReminderPermission?.let { reminderViewModel.setEnabled(accessAvailable && it) }
        pendingReminderPermission = null
        integrationViewModel.trackPushPermissionResult(accessAvailable)
        reminderViewModel.trackPermissionResult(accessAvailable)
    }
    fun requestNotificationPermission(forPush: Boolean, forReminder: Boolean) {
        val permission = android.Manifest.permission.POST_NOTIFICATIONS
        val runtimePermissionGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
        if (runtimePermissionGranted && !NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            notificationPermissionRequested = true
            notificationPermissionPreferences.edit().putBoolean("requested", true).apply()
            openAppNotificationSettings(context)
            return
        }
        val rationaleAvailable = context.findActivity()?.shouldShowRequestPermissionRationale(permission) == true
        if (notificationPermissionRequested && !rationaleAvailable) {
            openAppNotificationSettings(context)
            return
        }
        notificationPermissionRequested = true
        notificationPermissionPreferences.edit().putBoolean("requested", true).apply()
        pendingPushPermission = forPush.takeIf { it }
        pendingReminderPermission = forReminder.takeIf { it }
        pushPermissionLauncher.launch(permission)
    }
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, context, accountId) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                val accessAvailable = notificationAccessAvailable(context)
                if (accessAvailable != pushPermissionGranted) integrationViewModel.trackPushPermissionResult(accessAvailable)
                pushPermissionGranted = accessAvailable
                notificationPermissionRequested = notificationPermissionPreferences.getBoolean("requested", false)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    var todaySelectedRoute by remember(accountId) { mutableStateOf<com.plainstride.outbound.feature.community.CommunityRoute?>(null) }
    var todayRouteReversed by rememberSaveable(accountId) { mutableStateOf(false) }
    var selectedTodayShoeId by remember(accountId) { mutableStateOf<String?>(null) }
    LaunchedEffect(integration.defaultGearId) {
        if (selectedTodayShoeId == null) selectedTodayShoeId = integration.defaultGearId
    }
    val activeShoes = remember(integration.gearShoes) { integration.gearShoes.filterNot { it.isRetired } }
    val selectedTodayShoe = selectedTodayShoeId?.let { id -> activeShoes.firstOrNull { it.id.toString() == id } }
        ?: activeShoes.firstOrNull { it.id.toString() == integration.defaultGearId }
        ?: activeShoes.firstOrNull()
    val selectedTodayShoeIdForLaunch = selectedTodayShoe?.id?.toString()
    val sharedSocialViewModel: SocialViewModel = hiltViewModel(key = "shared_social_$accountId")
    val groupSocialState by sharedSocialViewModel.state.collectAsStateWithLifecycle()
    val groupLifecycleOwner = androidx.lifecycle.compose.LocalLifecycleOwner.current
    DisposableEffect(groupLifecycleOwner, sharedSocialViewModel) {
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_RESUME) sharedSocialViewModel.retryGroupParticipation()
        }
        groupLifecycleOwner.lifecycle.addObserver(observer)
        onDispose { groupLifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val groupLocale = resources.configuration.locales[0].toLanguageTag()
    LaunchedEffect(accountId, groupLocale) { accountId?.let { sharedSocialViewModel.start(it, groupLocale, trackOpen = false) } }
    val groupRecordingPreferences = remember(accountId) { context.getSharedPreferences("group_recording_${accountId}", android.content.Context.MODE_PRIVATE) }
    var selectedRecordingEventId by remember(accountId) { mutableStateOf(groupRecordingPreferences.getString("selected_event", null)) }
    val todayGroupEvent = groupSocialState.home.upcomingRuns.firstOrNull { event ->
        event.currentUserOutcome == null && !groupRecordingPreferences.getStringSet("completed_events", emptySet()).orEmpty().contains(event.id) &&
        (event.joined || event.canParticipate == true) && event.status in setOf("scheduled", "active") &&
            (event.status == "active" || runCatching { java.time.Instant.parse(event.startsAt).atZone(java.time.ZoneId.systemDefault()).toLocalDate() == java.time.LocalDate.now() }.onFailure { android.util.Log.w("PlainstrideGroups", "today_event_start_parse type=${it.javaClass.simpleName}") }.getOrDefault(false))
    }

    val trustedContacts by cheerPickerViewModel.trustedContacts.collectAsStateWithLifecycle()
    val sharesWithTrustedContactsByDefault by cheerPickerViewModel.sharesWithTrustedContactsByDefault.collectAsStateWithLifecycle()
    val selectedCheerIds by cheerPickerViewModel.selectedRecipientIds.collectAsStateWithLifecycle()
    val selectedCheerIdSet = selectedCheerIds.toSet()
    val activeCheerShare by cheerPickerViewModel.activeShare.collectAsStateWithLifecycle()
    val recordingSafetyViewModel: RecordingSafetyViewModel = hiltViewModel()
    val sharedLiveGroupRun by recordingSafetyViewModel.coordinator.group.collectAsStateWithLifecycle()
    val groupRunJoining by recordingSafetyViewModel.coordinator.groupJoining.collectAsStateWithLifecycle()
    val toggleActivityLiveMap: (String) -> Unit = { eventId ->
        if (recordingSafetyViewModel.coordinator.isSharingEvent(eventId)) {
            recordingSafetyViewModel.coordinator.group.value?.let { run ->
                scope.launch {
                    recordingSafetyViewModel.coordinator.leaveGroupRun(run.id, finished = false)
                        .onFailure { snackbar.showSnackbar(resources.getString(R.string.auth_generic_error)) }
                }
            }
        } else {
            scope.launch {
                recordingSafetyViewModel.coordinator.joinActivityGroupRun(eventId)
                    .onFailure { snackbar.showSnackbar(resources.getString(R.string.auth_generic_error)) }
            }
        }
    }
    LaunchedEffect(accountId, currentRoute, todayGroupEvent?.id, todayGroupEvent?.joined, selectedRecordingEventId, hasActiveSession, groupRunJoining, sharedLiveGroupRun?.id, sharedLiveGroupRun?.status) {
        val event = todayGroupEvent ?: return@LaunchedEffect
        if (accountId == null || hasActiveSession || currentRoute != TopLevelDestination.Today.route) return@LaunchedEffect
        val joinChoiceKey = "join_choice_${event.id}"
        if (event.joined && selectedRecordingEventId == null && !groupRecordingPreferences.contains(joinChoiceKey)) {
            selectedRecordingEventId = event.id
            groupRecordingPreferences.edit().putString("selected_event", event.id).putBoolean(joinChoiceKey, true).apply()
            integrationViewModel.trackGroupRecordingSelection(true, "today_rsvp_default")
        }
        val shareDefaultKey = "share_default_applied_${event.id}"
        if (selectedRecordingEventId == event.id && !groupRecordingPreferences.getBoolean(shareDefaultKey, false)
            && !recordingSafetyViewModel.coordinator.hasDifferentActiveGroup(event.id) && !groupRunJoining) {
            // Apply once, before the request: a refresh or later Stop sharing must never re-enable it.
            groupRecordingPreferences.edit().putBoolean(shareDefaultKey, true).apply()
            if (!recordingSafetyViewModel.coordinator.isSharingEvent(event.id)) toggleActivityLiveMap(event.id)
        }
    }
    val stopActivityLiveMap: () -> Unit = {
        recordingSafetyViewModel.coordinator.group.value?.let { run ->
            scope.launch {
                recordingSafetyViewModel.coordinator.leaveGroupRun(run.id, finished = false)
                    .onFailure { snackbar.showSnackbar(resources.getString(R.string.auth_generic_error)) }
            }
        }
    }
    LaunchedEffect(currentRoute, pushPermissionGranted) {
        if (currentRoute == TopLevelDestination.Social.route && !pushPermissionGranted) {
            integrationViewModel.trackPushPermissionPromptExposed("social")
        }
    }
    fun launchTodayRecording() {
        if (todayStartJob?.isActive == true) return
        val changedRun = recordingLaunch.entrySource == "today_changed_run"
        val configuration = recordingLaunch.copy(
            activityEventId = todayGroupEvent?.id?.takeIf { !changedRun && it == selectedRecordingEventId },
            activityEventTitle = todayGroupEvent?.name?.takeIf { !changedRun && todayGroupEvent.id == selectedRecordingEventId },
        )
        todayStartJob = scope.launch {
            try {
                recordingViewModel.configure(configuration, measurementUnitSystem)
                val permission = recordingLocationPermission(context)
                val hasPermission = permission == LocationPermissionState.PRECISE || permission == LocationPermissionState.APPROXIMATE
                val needsMotion = configuration.activityKind in setOf(ActivityKind.RUNNING, ActivityKind.WALKING) &&
                    android.os.Build.VERSION.SDK_INT >= 29 &&
                    !context.getSharedPreferences("motion_permission", android.content.Context.MODE_PRIVATE).getBoolean("requested", false) &&
                    context.checkSelfPermission(android.Manifest.permission.ACTIVITY_RECOGNITION) != PackageManager.PERMISSION_GRANTED &&
                    context.getSystemService(android.hardware.SensorManager::class.java)?.getDefaultSensor(android.hardware.Sensor.TYPE_STEP_DETECTOR) != null
                if (configuration.startImmediately && !needsMotion && hasPermission && (configuration.indoor || recordingViewModel.hasRecentStartLocation())) {
                    cheerPickerViewModel.applyTrustedContactDefault()
                    voicePreparation.preparation.activityWillStart(configuration.voiceGuideEnabled)
                    // Resolve recovery before a direct Walk/Hike start so entering
                    // the recording route cannot recover the new session as paused.
                    recordingViewModel.recover(requireNotNull(accountId), permission)
                    if (configuration.activityKind in setOf(ActivityKind.WALKING, ActivityKind.HIKING)) {
                        recordingViewModel.start(requireNotNull(accountId), permission)
                    } else recordingViewModel.beginCountdown()
                }
                recordingLaunch = configuration
                navController.navigate(RECORDING_ROUTE) { launchSingleTop = true }
            } finally { todayStartJob = null }
        }
    }
    androidx.activity.compose.BackHandler(enabled = todayStartJob?.isActive == true) {
        todayStartJob?.cancel()
        recordingViewModel.cancelCountdown()
    }
    LaunchedEffect(currentRoute) {
        if (currentRoute != TopLevelDestination.Today.route && currentRoute != RECORDING_ROUTE) {
            todayStartJob?.cancel()
        }
    }
    LaunchedEffect(accountId) { accountId?.let { integrationViewModel.start(it, resources.configuration.locales[0].toLanguageTag());cycleViewModel.start(it);healthViewModel.start(it) } }
    LaunchedEffect(accountId, pushPermissionGranted, notificationPermissionRequested, reminderEnabled) {
        if (
            accountId != null &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !notificationPermissionRequested
        ) {
            if (pushPermissionGranted) {
                notificationPermissionRequested = true
                notificationPermissionPreferences.edit().putBoolean("requested", true).apply()
            } else {
                if (!notificationPermissionPreferences.getBoolean("primer_shown", false)) {
                    notificationPermissionPreferences.edit().putBoolean("primer_shown", true).apply()
                    showNotificationPermissionPrimer = true
                    integrationViewModel.trackPushPermissionPromptExposed("authenticated_entry")
                }
            }
        }
    }
    LaunchedEffect(accountId) { cheerPickerViewModel.onAccountActivated(accountId) }
    LaunchedEffect(integration.connections) { cheerPickerViewModel.onConnectionsUpdated(integration.connections) }
    LaunchedEffect(accountId) { accountId?.let(connectivityViewModel::start) }
    LaunchedEffect(connectivityState.isOffline) {
        if (!connectivityState.isOffline && !voicePreparation.preparation.state.value.ready) voicePreparation.preparation.retry()
    }
    LaunchedEffect(connectivityState.isOffline, connectivityState.pendingSyncCount > 0) {
        if (!connectivityState.isOffline && connectivityState.pendingSyncCount > 0) {
            snackbar.showSnackbar(resources.getString(R.string.connectivity_pending))
        }
    }
    LaunchedEffect(accountId) {
        accountId?.let { activeRecordingViewModel.recover(it, recordingLocationPermission(context)) }
    }
    LaunchedEffect(hasActiveSession, currentRoute) {
        if (!hasActiveSession) suppressRecordingRecovery = false
        if (hasActiveSession && !suppressRecordingRecovery && currentRoute != RECORDING_ROUTE) {
            navController.navigate(RECORDING_ROUTE) { launchSingleTop = true }
        }
    }
    LaunchedEffect(accountId, lifecycleOwner) {
        if (accountId != null) lifecycleOwner.lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            // Also runs immediately when collection starts after ON_RESUME already happened.
            while (true) {
                integrationViewModel.refreshSocialState("foreground")
                delay(30_000)
            }
        }
    }
    LaunchedEffect(accountId) {
        if (accountId != null) com.plainstride.outbound.notifications.InboxUpdates.changes.collect {
            integrationViewModel.refreshSocialState("push")
        }
    }
    LaunchedEffect(navigationUri, accountId) {
        if (accountId == null) return@LaunchedEffect
        val destination = navigationUri?.pathSegments?.firstOrNull() ?: return@LaunchedEffect
        navigationUri.getQueryParameter("type")?.let { integrationViewModel.trackPushOpened(destination, it) }
        integrationViewModel.refreshInbox()
        val id = navigationUri.getQueryParameter("id").orEmpty()
        val route = when (destination) {
            "today" -> { reminderWorkoutId = navigationUri.getQueryParameter("workout"); TopLevelDestination.Today.route }
            "assistant" -> { assistantEntryDestination = TopLevelDestination.entries.firstOrNull { it.route == currentRoute }?.route ?: "me"; ASSISTANT_ROUTE }
            "connections" -> AppDetailRoutes.connections("notification")
            "activity" -> id.takeIf(String::isNotBlank)?.let { AppDetailRoutes.activity(it, "notification") }
            "post" -> id.takeIf(String::isNotBlank)?.let(AppDetailRoutes::post)
            "event" -> id.takeIf(String::isNotBlank)?.let { AppDetailRoutes.event(it, "notification") }
            "group" -> id.takeIf(String::isNotBlank)?.let { AppDetailRoutes.group(it, "notification") }
            "invitation" -> id.takeIf(String::isNotBlank)?.let(AppDetailRoutes::invitation)
            "live" -> id.takeIf(String::isNotBlank)?.let { AppDetailRoutes.safety("live", it, "notification") }
            "group_run" -> id.takeIf(String::isNotBlank)?.let { AppDetailRoutes.safety("group", it, "notification") }
            else -> NOTIFICATIONS_ROUTE
        }
        if (route == TopLevelDestination.Today.route) selectTab(route)
        else navController.navigate(route ?: NOTIFICATIONS_ROUTE) { launchSingleTop = true }
        onNavigationUriConsumed()
    }
    LaunchedEffect(connectionCode) {
        val code = connectionCode ?: return@LaunchedEffect
        rewardsViewModel.claimIncomingInvitation(code)
        navController.navigate(AppDetailRoutes.connectionProfile(code)) { launchSingleTop = true }
        onConnectionCodeConsumed()
    }
    LaunchedEffect(groupInviteToken) {
        val token = groupInviteToken ?: return@LaunchedEffect
        navController.navigate(AppDetailRoutes.groupInvite(token)) { launchSingleTop = true }
        onGroupInviteConsumed()
    }

    Scaffold(
        containerColor = Color.Transparent,
        contentWindowInsets = WindowInsets.safeDrawing,
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            val primaryDestination = TopLevelDestination.entries.firstOrNull { it.route == currentRoute }
            if (primaryDestination != null) {
                val lifecycleOwner = LocalLifecycleOwner.current
                val lifecycleState by lifecycleOwner.lifecycle.currentStateFlow.collectAsStateWithLifecycle(
                    minActiveState = Lifecycle.State.CREATED,
                )
                val windowFocused = LocalWindowInfo.current.isWindowFocused
                val companionEligible = lifecycleState.isAtLeast(Lifecycle.State.RESUMED) && windowFocused &&
                    !hasActiveSession && !showNotificationPermissionPrimer && !cheerPickerVisible &&
                    !addShoeSheetVisible && planBuilderSource == null
                LaunchedEffect(companionEligible) {
                    if (companionEligible && !trackedAssistantExposure) {
                        integrationViewModel.trackAssistantLauncherEligibleExposure(primaryDestination.route)
                        trackedAssistantExposure = true
                    }
                }
                Row(
                    Modifier
                        .fillMaxWidth()
                        .navigationBarsPadding()
                        .padding(horizontal = 16.dp, vertical = 6.dp)
                        .offset(y = 8.dp),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    key(accountId) {
                        FoxCompanionLauncher(
                            eligible = companionEligible,
                            notifications = integration.notifications.takeIf { integration.notificationAccountId == accountId }.orEmpty(),
                            claimDelivery = integrationViewModel::claimCompanionDelivery,
                            onPresence = integrationViewModel::trackCompanionPresence,
                            onAction = integrationViewModel::trackCompanionAction,
                            onOpenAssistant = {
                                assistantEntryDestination = primaryDestination.route
                                integrationViewModel.trackAssistantOpened(primaryDestination.route)
                                navController.navigate(ASSISTANT_ROUTE) { launchSingleTop = true }
                            },
                            onOpenInbox = { navController.navigate(NOTIFICATIONS_ROUTE) { launchSingleTop = true } },
                            onOpenNotification = { item ->
                                integrationViewModel.openNotification(item)
                                navController.navigate(notificationRoute(item)) { launchSingleTop = true }
                            },
                        )
                    }
                    Spacer(Modifier.width(10.dp))
                    val contextualStart = primaryDestination == TopLevelDestination.Today && !hasActiveSession
                    NavigationBar(
                        modifier = Modifier.widthIn(max = 252.dp).fillMaxWidth().height(64.dp).clip(RoundedCornerShape(32.dp)),
                        containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.78f),
                        tonalElevation = 0.dp,
                    ) {
                        val themeColors = LocalPlainstrideThemeColors.current
                        TopLevelDestination.entries.forEach { destination ->
                            val isContextualStart = destination == TopLevelDestination.Today && contextualStart
                            NavigationBarItem(
                                selected = destination == primaryDestination,
                                onClick = {
                                    if (isContextualStart) {
                                        todayStartRequest += 1
                                    } else {
                                        selectTab(destination.route)
                                    }
                                },
                                icon = {
                                    val iconTint = when {
                                        isContextualStart -> themeColors.action
                                        destination == primaryDestination -> MaterialTheme.colorScheme.primary
                                        else -> MaterialTheme.colorScheme.onSurfaceVariant
                                    }
                                    Icon(
                                        imageVector = when {
                                            isContextualStart -> Icons.Default.PlayCircle
                                            destination == TopLevelDestination.Social -> Icons.Outlined.PeopleAlt
                                            destination == TopLevelDestination.Today -> Icons.Default.AutoAwesome
                                            else -> Icons.Default.Person
                                        },
                                        contentDescription = stringResource(
                                            if (isContextualStart) TodayR.string.today_start else destination.label,
                                        ),
                                        tint = iconTint,
                                        modifier = Modifier.size(if (isContextualStart) 40.dp else 32.dp),
                                    )
                                },
                                label = null,
                                alwaysShowLabel = false,
                                colors = androidx.compose.material3.NavigationBarItemDefaults.colors(
                                    selectedIconColor = MaterialTheme.colorScheme.primary,
                                    unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                    selectedTextColor = MaterialTheme.colorScheme.primary,
                                    unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                                    indicatorColor = Color.Transparent,
                                ),
                            )
                        }
                    }
                }
            }
        },
    ) { contentPadding ->
        val layoutDirection = LocalLayoutDirection.current
        val contentInsets = PaddingValues(
            start = contentPadding.calculateStartPadding(layoutDirection),
            top = contentPadding.calculateTopPadding(),
            end = contentPadding.calculateEndPadding(layoutDirection),
            bottom = if (TopLevelDestination.entries.any { it.route == currentRoute }) {
                WindowInsets.safeDrawing.asPaddingValues().calculateBottomPadding()
            } else {
                contentPadding.calculateBottomPadding()
            },
        )
        Column(Modifier.fillMaxSize().padding(contentInsets).consumeWindowInsets(contentInsets)) {
        if (currentRoute != RECORDING_ROUTE && connectivityState.isOffline) {
            ConnectivityBanner(
                connectivityState,
                Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp),
            )
        }
        NavHost(
            navController = navController,
            startDestination = APP_SHELL_ROUTE,
            modifier = Modifier.fillMaxWidth().weight(1f),
        ) {
            composable(APP_SHELL_ROUTE) {
                val todayViewModel: TodayViewModel = hiltViewModel()
                LaunchedEffect(accountId, groupLocale) { accountId?.let { todayViewModel.configure(it, groupLocale) } }
                val todayState by todayViewModel.state.collectAsStateWithLifecycle()
                val mePlanSummary = todayState.planningSnapshot?.let { planning ->
                    val recommendation = (todayState.suggestion as? com.plainstride.outbound.feature.today.CachedResource.Available)
                        ?.takeUnless { it.isStale }?.value
                        ?.takeIf { it.validForDate == java.time.LocalDate.now().toString() && planning.plan == null }
                        ?.primary
                    com.plainstride.outbound.feature.settings.MePlanSummary(
                        phase = planning.plan?.currentPhase,
                        consistencyPercent = planning.athleteState?.consistencyScore?.times(100)?.toInt()?.coerceIn(0, 100),
                        runGoalTarget = planning.goal
                            ?.takeIf { it.activities == listOf(com.plainstride.outbound.core.model.Modality.run) }
                            ?.daysPerWeekTarget
                            ?.takeIf { it > 0 },
                        hasConfirmedNoPlan = todayState.hasConfirmedNoPlan,
                        dailyRecommendationTitle = recommendation?.title,
                    )
                }
                val destination = TopLevelDestination.entries.first { it.route == selectedTab }
                tabStateHolder.SaveableStateProvider(destination.route) {
                    if (destination == TopLevelDestination.Today) {
                        ActivityStartWarmup(recordingViewModel)
                        val startLocation by recordingViewModel.startLocationUpdates.collectAsStateWithLifecycle()
                        TodayRoute(
                            onOpenStretch = { navController.navigate(AppDetailRoutes.stretch("today")) { launchSingleTop = true } },
                            mapLocation = startLocation,
                            accountId = requireNotNull(accountId),
                            localeTag = resources.configuration.locales[0].toLanguageTag(),
                            viewModel = todayViewModel,
                            activeSession = hasActiveSession,
                            groupActivityContent = todayGroupEvent?.takeIf { !hasActiveSession }?.let { event ->
                                { com.plainstride.outbound.feature.social.TodayGroupActivityCard(event,
                                    recordingSafetyViewModel.coordinator.isSharingEvent(event.id), groupRunJoining || recordingSafetyViewModel.coordinator.hasDifferentActiveGroup(event.id),
                                    { navController.navigate(AppDetailRoutes.event(event.id, "today_group_activity")) },
                                    { toggleActivityLiveMap(event.id) },
                                    joined = selectedRecordingEventId == event.id,
                                    onJoinChanged = { joined ->
                                        selectedRecordingEventId = event.id.takeIf { joined }
                                        groupRecordingPreferences.edit().putString("selected_event", selectedRecordingEventId).putBoolean("join_choice_${event.id}", joined).apply()
                                        integrationViewModel.trackGroupRecordingSelection(joined)
                                        if (!joined && recordingSafetyViewModel.coordinator.isSharingEvent(event.id)) toggleActivityLiveMap(event.id)
                                    }) }
                            },
                            completedToday = integration.completedToday,
                            onStartWorkout = { intent, options ->
                                val launch = intent.toRecordingLaunch().copy(gearId = selectedTodayShoeIdForLaunch,privateTrainingSignal=cycleState.currentSignal.takeIf{cycleState.enabled&&it!=CycleTrainingSignal.NO_ADJUSTMENT}?.wireValue,startImmediately=true,indoor=options.indoor,voiceGuideEnabled=options.voiceGuideEnabled,aiCoachEnabled=options.aiCoachEnabled,companionType=options.companionType)
                                recordingLaunch = if (intent.source == "today_changed_run") launch.copy(startImmediately = false, autoStopAtGoal = false) else launch.withTodayRoute(todaySelectedRoute, todayRouteReversed)
                                launchTodayRecording()
                            },
                            onStartFreestyle = { options ->
                                recordingLaunch = RecordingLaunchConfiguration(
                                    gearId = selectedTodayShoeIdForLaunch,
                                    entrySource = "today_freestyle",
                                    startImmediately = true,
                                    indoor = options.indoor,
                                    voiceGuideEnabled = options.voiceGuideEnabled,
                                    aiCoachEnabled = options.aiCoachEnabled,
                                    companionType = options.companionType,
                                ).withTodayRoute(todaySelectedRoute, todayRouteReversed)
                                launchTodayRecording()
                            },
                            onReturnToSession = { navController.navigate(RECORDING_ROUTE) { launchSingleTop = true } },
                            onSetUpPlan = { planBuilderSource = PlanBuilderSource.PlannedButton },
                            onBuildPlan = { planBuilderSource = PlanBuilderSource.AllPlans },
                            unitSystem = measurementUnitSystem,
                            onStartManual = { setup ->
                                if (setup.curatedWorkout?.let { workout ->
                                    workout.coachingTarget?.pace?.reference == "athlete_reference" ||
                                        workout.steps.any { it.coachingTarget?.pace?.reference == "athlete_reference" }
                                } == true) integrationViewModel.trackCoachingReference(integration.coachingReferencePace != null)
                                recordingLaunch = setup.toRecordingLaunch(selectedTodayShoeIdForLaunch, integration.coachingReferencePace).withTodayRoute(todaySelectedRoute, todayRouteReversed)
                                launchTodayRecording()
                            },
                            shoes = activeShoes.map { com.plainstride.outbound.feature.today.TodayShoeOption(it.id.toString(), it.displayName) },
                            selectedShoeId = selectedTodayShoeIdForLaunch,
                            onSelectShoe = { shoe -> selectedTodayShoeId = shoe.id; integrationViewModel.trackShoeSelected("active_shoe") },
                            onAddShoe = { integrationViewModel.trackShoeSelected("add_new"); addShoeSheetVisible = true },
                            onOpenLiveTrack = { cheerPickerVisible = true },
                            cheerRecipientsSelected = selectedCheerIdSet.isNotEmpty(),
                            onOpenInbox = { navController.navigate(NOTIFICATIONS_ROUTE) },
                            onFindRoute = {
                                selectingRouteForToday = true
                                if (integration.routeScope != RouteScope.DISCOVERY) integrationViewModel.scope(RouteScope.DISCOVERY)
                                integrationViewModel.trackTodayRouteLibraryOpened()
                                todaySelectedRoute?.id?.let(integrationViewModel::loadCommunityRoute)
                                navController.navigate(COMMUNITY_ROUTES_ROUTE)
                            },
                            selectedRoute = todaySelectedRoute?.let { route ->
                                val points = route.guidancePoints().map { MapCoordinate(it.latitude, it.longitude) }
                                val distance = com.plainstride.outbound.core.model.activity.SessionFormatting.distance(route.distanceM, measurementUnitSystem)
                                val unit = if (measurementUnitSystem == MeasurementUnitSystem.metric) "km" else "mi"
                                val label = resources.getString(TodayR.string.today_route_distance_format, distance.value, unit)
                                TodayRouteSelection(route.id, route.name, label, points, todayRouteReversed)
                            },
                            onRemoveRoute = {
                                integrationViewModel.trackTodayRouteRemoved(todaySelectedRoute)
                                todaySelectedRoute = null
                                todayRouteReversed = false
                                integrationViewModel.clearCommunityRoute()
                            },
                            onRouteDirectionChanged = { reverse ->
                                if (todayRouteReversed != reverse) integrationViewModel.trackTodayRouteDirection(reverse)
                                todayRouteReversed = reverse
                            },
                            useFahrenheit = settingsState.preferences.temperature == com.plainstride.outbound.feature.settings.TemperatureUnit.Fahrenheit,
                            inboxCount = NotificationPresentationPolicy.attentionCount(integration.notifications),
                            startRequest = todayStartRequest,
                            refreshRequest = todayRefreshRequest,
                            onMessage = { message ->
                                snackbar.showSnackbar(resources.getString(todayMessageResource(message)))
                            },
                            guidanceContent = { CycleTodayGuidance(cycleState,onKeep={},{ todayViewModel.state.value.primarySuggestion?.let{suggestion->cycleViewModel.requestGentler(suggestion.plannedWorkoutId?:suggestion.id)} }) },
                            initialWorkoutId = reminderWorkoutId,
                        )
                    } else if (destination == TopLevelDestination.Me) {
                        MeRoute(
                            viewModel = settingsViewModel,
                            settingsRequest = settingsRequest,
                            appVersion = BuildConfig.VERSION_NAME,
                            debugToolsEnabled = BuildConfig.DEBUG,
                            onLinkGoogle = { authViewModel.linkGoogle(context) },
                            onSignOut = authViewModel::signOut,
                            onDeleteAccount = authViewModel::requestDeletion,
                            onReplayOnboarding = {
                                forceOnboardingReplay = true
                                onboardingResolved = false
                            },
                            inboxCount = NotificationPresentationPolicy.attentionCount(integration.notifications),
                            onNotifications = { navController.navigate(NOTIFICATIONS_ROUTE) { launchSingleTop = true } },
                            connections = integration.connections,
                            insights = integration.insights.map { MeInsight(it.id, it.label, it.value, it.confidence.replaceFirstChar(Char::uppercase)) },
                            milestones = buildList {
                                addAll(integration.recognitions.map { MeMilestone("${it.badgeId}:${it.awardedAt}", it.badgeId.replace('_', ' ').replaceFirstChar(Char::uppercase)) })
                                val stats = integration.progress.stats
                                if (stats.eligibleActivityCount >= 1) add(MeMilestone("local:first_activity", resources.getString(SettingsR.string.milestone_first_activity)))
                                if (stats.eligibleActivityCount >= 10) add(MeMilestone("local:ten_activities", resources.getString(SettingsR.string.milestone_ten_activities)))
                                if (stats.weeklyBuckets.sumOf { it.distanceMeters } >= 100_000) add(MeMilestone("local:hundred_km", resources.getString(SettingsR.string.milestone_hundred_km)))
                            }.distinctBy(MeMilestone::id),
                            accountWeeklyMinutes = (integration.progress.accountWeek?.durationSeconds ?: 0) / 60,
                            accountWeeklyDistanceMeters = integration.progress.accountWeek?.distanceMeters ?: 0.0,
                            weeklyRunGoal = integration.weeklyRunGoal,
                            planSummary = mePlanSummary,
                            statisticsAvailable = integration.progress.isAvailable
                                && integration.statisticsWeekStart?.let { !java.time.Instant.now().isBefore(it) } == true
                                && integration.statisticsWeekEnd?.let { java.time.Instant.now().isBefore(it) } == true,
                            onRefreshStatistics = integrationViewModel::refreshStatistics,
                            onRefreshToday = todayViewModel::refresh,
                            statisticsCached = integration.progress.isCached,
                            onMyQrCode = { navController.navigate(MY_QR_ROUTE) { launchSingleTop = true } },
                            onConnections = {
                                navController.navigate(AppDetailRoutes.connections("me_preview")) { launchSingleTop = true }
                            },
                            onConnectionProfile = { person ->
                                sharedSocialViewModel.prepareProfile(person) {
                                    navController.navigate(AppDetailRoutes.profile(person.id, "me_preview")) { launchSingleTop = true }
                                }
                            },
                            onMyRoutes = {
                                integrationViewModel.scope(com.plainstride.outbound.feature.community.RouteScope.MINE)
                                navController.navigate(COMMUNITY_ROUTES_ROUTE) { launchSingleTop = true }
                            },
                            onOpenProgressInsights = {
                                navController.navigate(PROGRESS_ROUTE) { launchSingleTop = true }
                            },
                            onMeDestination = settingsViewModel::trackMeDestination,
                            benefitsContent = {
                                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    if (rewardsState.status?.featureControls?.paywallEnabled == true) {
                                        MeBenefitDestinationCard(
                                            title = R.string.rewards_plus,
                                            body = R.string.rewards_plus_settings_body,
                                            icon = Icons.Filled.AutoAwesome,
                                        ) {
                                            settingsViewModel.trackMeDestination("plus")
                                            navController.navigate(PLUS_ROUTE)
                                        }
                                    }
                                    MeBenefitDestinationCard(
                                        title = R.string.rewards_settings_title,
                                        body = R.string.rewards_settings_body,
                                        icon = Icons.Filled.EmojiEvents,
                                    ) {
                                        settingsViewModel.trackMeDestination("rewards_center")
                                        navController.navigate(REWARDS_ROUTE)
                                    }
                                    MeBenefitDestinationCard(
                                        title = R.string.rewards_my_invitation_code,
                                        body = R.string.rewards_invitation_code_body,
                                        icon = Icons.Filled.Person,
                                    ) {
                                        settingsViewModel.trackMeDestination("invitation_code")
                                        navController.navigate(INVITATION_CODE_ROUTE)
                                    }
                                }
                            },
                            activityContent = {
                                accountId?.let { id ->
                                    RecentActivitiesRoute(
                                        accountId = id,
                                        unitSystem = measurementUnitSystem,
                                        weightKilograms = integration.weightKilograms,
                                        onOpenActivity = { selectedId ->
                                            navController.navigate(AppDetailRoutes.activity(selectedId, "me_recent")) { launchSingleTop = true }
                                        },
                                        onOpenAll = {
                                            navController.navigate(ACTIVITY_HISTORY_ROUTE) { launchSingleTop = true }
                                        },
                                        onImportHealth = { navController.navigate(HEALTH_ROUTE) { launchSingleTop = true } },
                                        onMessage = { message -> snackbar.showSnackbar(resources.getString(activityMessageResource(message))) },
                                    )
                                }
                            },
                            settingsContent = {
                                LaunchedEffect(pushPermissionGranted) {
                                    if (!pushPermissionGranted) {
                                        integrationViewModel.trackPushPermissionPromptExposed("settings")
                                    }
                                }
                                SettingsGroupTitle(stringResource(SettingsR.string.settings_planned_workouts))
                                ReminderSettingsRow(
                                    viewModel = reminderViewModel,
                                    debugToolsEnabled = BuildConfig.DEBUG,
                                    notificationsAllowed = pushPermissionGranted,
                                    onRequestNotificationPermission = {
                                        requestNotificationPermission(forPush = false, forReminder = true)
                                    },
                                )
                                SettingsGroupTitle(stringResource(SettingsR.string.settings_safety))
                                ListItem(
                                    headlineContent = { Text(stringResource(com.plainstride.outbound.feature.safety.R.string.trusted_contacts_title)) },
                                    supportingContent = { Text(stringResource(com.plainstride.outbound.feature.safety.R.string.trusted_contacts_settings_body)) },
                                    modifier = Modifier.clickable {
                                        settingsViewModel.trackMeDestination("trusted_contacts")
                                        navController.navigate(TRUSTED_CONTACTS_ROUTE)
                                    },
                                )
                                ListItem(headlineContent = { Text(stringResource(R.string.safety_destination)) }, supportingContent = { Text(stringResource(SettingsR.string.settings_safety_body)) }, modifier = Modifier.clickable { navController.navigate(SAFETY_ROUTE) })
                                SettingsGroupTitle(stringResource(SettingsR.string.settings_live_guidance))
                                LiveCoachSettingsSection(onPlus = { navController.navigate(PLUS_ROUTE) })
                                SettingsGroupTitle(stringResource(SettingsR.string.settings_health_and_body))
                                accountId?.let { CycleAwareSection(it,cycleViewModel) }
                                SettingsGroupTitle(stringResource(ProgressR.string.progress_gear))
                                GearSettingsSection(
                                    summaries = integration.gearMileage,
                                    statisticsAvailable = integration.progress.isAvailable,
                                    defaultShoeId = integration.defaultGearId,
                                    units = if (measurementUnitSystem == MeasurementUnitSystem.metric) ProgressUnitSystem.METRIC else ProgressUnitSystem.IMPERIAL,
                                    onAdd = { addShoeSheetVisible = true },
                                    onMakeDefault = integrationViewModel::setDefaultGearShoe,
                                    onRetire = integrationViewModel::retireGearShoe,
                                )
                                SettingsGroupTitle(stringResource(SettingsR.string.settings_integrations))
                                ListItem(headlineContent = { Text(stringResource(R.string.music_settings_title)) }, supportingContent = { Text(stringResource(R.string.music_settings_body)) }, modifier = Modifier.clickable { navController.navigate(MUSIC_ROUTE) })
                                ListItem(headlineContent = { Text(stringResource(R.string.progress_destination)) }, modifier = Modifier.clickable { navController.navigate(PROGRESS_ROUTE) })
                                ListItem(headlineContent = { Text(stringResource(R.string.routes_destination)) }, modifier = Modifier.clickable { navController.navigate(COMMUNITY_ROUTES_ROUTE) })
                                ListItem(headlineContent = { Text(stringResource(R.string.health_destination)) }, modifier = Modifier.clickable { navController.navigate(HEALTH_ROUTE) })
                                ListItem(headlineContent = { Text(stringResource(R.string.notifications_destination)) }, modifier = Modifier.clickable { navController.navigate(NOTIFICATIONS_ROUTE) })
                                ListItem(
                                    headlineContent = { Text(stringResource(R.string.push_notifications_setting)) },
                                    supportingContent = {
                                        Column {
                                            Text(stringResource(R.string.push_notifications_body))
                                            if (!pushPermissionGranted) {
                                                TextButton(onClick = {
                                                    integrationViewModel.trackPushPermissionPromptAction("settings", "enable")
                                                    requestNotificationPermission(forPush = true, forReminder = reminderEnabled)
                                                }) {
                                                    Text(stringResource(SocialR.string.social_notifications_permission_enable))
                                                }
                                            }
                                        }
                                    },
                                    trailingContent = {
                                        Switch(
                                            checked = integration.pushEnabled && pushPermissionGranted,
                                            onCheckedChange = { enabled ->
                                                if (!enabled) {
                                                    integrationViewModel.setPushEnabled(false)
                                                } else if (!pushPermissionGranted) {
                                                    requestNotificationPermission(forPush = true, forReminder = reminderEnabled)
                                                } else {
                                                    integrationViewModel.setPushEnabled(true)
                                                }
                                            },
                                        )
                                    },
                                )
                            },
                            onMessage = { message -> snackbar.showSnackbar(resources.getString(settingsMessageResource(message))) },
                        )
                    } else if (destination == TopLevelDestination.Social && accountId != null) {
                        SocialRoute(
                            accountId = accountId, localeTag = groupLocale,
                            inboxCount = NotificationPresentationPolicy.attentionCount(integration.notifications),
                            unitSystem = measurementUnitSystem,
                            onConditions = { selectTab(TopLevelDestination.Today.route) },
                            onCommunity = { navController.navigate(COMMUNITY_ROUTES_ROUTE) },
                            onNotifications = { navController.navigate(NOTIFICATIONS_ROUTE) { launchSingleTop = true } },
                            onOpenConnections = { source, adding -> navController.navigate(AppDetailRoutes.connections(source, adding)) },
                            onOpenGroup = { id, source, invitation -> navController.navigate(AppDetailRoutes.group(id, source, invitation)) },
                            onOpenInvitation = { navController.navigate(AppDetailRoutes.invitation(it)) },
                            onRoutesTabSelected = { if (integration.routeScope != RouteScope.DISCOVERY) integrationViewModel.scope(RouteScope.DISCOVERY) },
                            onOpenSharedActivity = { navController.navigate(AppDetailRoutes.post(it)) },
                            onOpenSharedEvent = { id, source -> navController.navigate(AppDetailRoutes.event(id, source)) },
                            onOpenSharedProfile = { navController.navigate(AppDetailRoutes.profile(it.id)) },
                            onOpenLiveCheer = { navController.navigate(AppDetailRoutes.safety("live", it, "social_active_now")) },
                            communityRoutesContent = { routeImportRequest ->
                                CommunityRouteScreen(
                                    accountId = accountId, onOpenRoute = { navController.navigate(AppDetailRoutes.route(it.id)) },
                                    library = integration.routes, scope = integration.routeScope, onScope = integrationViewModel::scope,
                                    onRefresh = integrationViewModel::refreshRoutes, onSearch = integrationViewModel::search,
                                    onImport = integrationViewModel::trackRouteImport,
                                    bottomContentPadding = PrimaryBottomToolbarClearance,
                                    routeDetail = integration.selectedCommunityRoute, routeDetailLoading = integration.communityRouteLoading,
                                    onLoadDetail = integrationViewModel::loadCommunityRoute,
                                    unitSystem = measurementUnitSystem, onImportedDelete = integrationViewModel::trackImportedRouteDeleted,
                                    importRequest = routeImportRequest, searchQuery = integration.routeQuery,
                                )
                            },
                            notificationAccessAvailable = pushPermissionGranted,
                            onEnableNotifications = { integrationViewModel.trackPushPermissionPromptAction("social", "enable"); requestNotificationPermission(forPush = true, forReminder = reminderEnabled) },
                            viewModel = sharedSocialViewModel,
                        )
                    } else {
                        FoundationScreen(destination, authState, authViewModel)
                    }
                }
            }
            composable(AppDetailRoutes.Connections) { entry ->
                ConnectionsDestination(
                    accountId = requireNotNull(accountId), localeTag = groupLocale,
                    entrySource = entry.arguments?.getString("source") ?: "deep_link",
                    startsAdding = entry.arguments?.getString("adding") == "true",
                    onOpenProfile = { navController.navigate(AppDetailRoutes.profile(it.id, "connections")) },
                    onOpenInvitation = { navController.navigate(AppDetailRoutes.invitation(it)) },
                    onOpenGroupInvitation = { id, invitation -> navController.navigate(AppDetailRoutes.group(id, "invitation", invitation)) },
                    onScanQr = { navController.navigate(CONNECTION_SCANNER_ROUTE) },
                    onMyQr = { navController.navigate(MY_QR_ROUTE) }, onBack = { navController.popBackStack() },
                )
            }
            composable(CONNECTION_SCANNER_ROUTE) {
                ConnectionScannerDestination(onCode = { code ->
                    navController.popBackStack()
                    navController.navigate(AppDetailRoutes.connectionProfile(code))
                }, onBack = { navController.popBackStack() })
            }
            composable(AppDetailRoutes.Post) { entry ->
                val socialViewModel = sharedSocialViewModel
                val activityViewModel: ActivityViewModel = hiltViewModel()
                SocialActivityDetailDestination(
                    accountId = requireNotNull(accountId), localeTag = groupLocale,
                    postId = entry.arguments?.getString("postId").orEmpty(),
                    onOpenGroupActivity = { navController.navigate(AppDetailRoutes.event(it, "activity_detail")) },
                    unitSystem = measurementUnitSystem, viewModel = socialViewModel, activityViewModel = activityViewModel,
                    onPublishRoute = { id, name -> integrationViewModel.publishSavedActivityRoute(id, name, "social_activity_detail") },
                    onOpenSharedProfile = { navController.navigate(AppDetailRoutes.profile(it.id, "activity_detail")) },
                    onBack = { navController.popBackStack() },
                )
            }
            composable(AppDetailRoutes.Event) { entry ->
                val socialViewModel: SocialViewModel = hiltViewModel()
                val eventId = entry.arguments?.getString("eventId").orEmpty()
                SocialActivityEventDestination(
                    accountId = requireNotNull(accountId), localeTag = groupLocale,
                    eventId = eventId, entrySource = entry.arguments?.getString("source") ?: "social_upcoming",
                    unitSystem = measurementUnitSystem, groupRun = sharedLiveGroupRun?.toSharedLiveRun(),
                    groupRunJoining = groupRunJoining, onToggleActivityLiveMap = { toggleActivityLiveMap(eventId) },
                    onStartActivity = { event ->
                        if (hasActiveSession) {
                            recordingViewModel.attachGroupActivity(event.id, event.name)
                            recordingLaunch = recordingViewModel.state.value.launch
                        } else recordingLaunch = event.recordingLaunch()
                        navController.navigate(RECORDING_ROUTE) { launchSingleTop = true }
                    },
                    viewModel = socialViewModel, onBack = { navController.popBackStack() },
                )
            }
            listOf(AppDetailRoutes.Profile, AppDetailRoutes.ConnectionProfile).forEach { route ->
                composable(route) { entry ->
                    val socialViewModel: SocialViewModel = hiltViewModel()
                    SocialProfileDestination(
                        accountId = requireNotNull(accountId), localeTag = groupLocale,
                        personId = entry.arguments?.getString("personId"), connectionCode = entry.arguments?.getString("code"),
                        entrySource = entry.arguments?.getString("source") ?: "connection_qr_code", viewModel = socialViewModel,
                        onOpenSharedActivity = { navController.navigate(AppDetailRoutes.post(it.id)) },
                        onBack = { navController.popBackStack() },
                    )
                }
            }
            composable(AppDetailRoutes.Group) { entry ->
                SocialGroupDestination(
                    accountId = requireNotNull(accountId), localeTag = groupLocale,
                    groupId = entry.arguments?.getString("groupId").orEmpty(),
                    invitationId = entry.arguments?.getString("invitation")?.takeIf(String::isNotBlank),
                    entrySource = entry.arguments?.getString("source") ?: "deep_link", unitSystem = measurementUnitSystem,
                    onOpenEvent = { id, source -> navController.navigate(AppDetailRoutes.event(id, source)) },
                    onBack = { navController.popBackStack() },
                )
            }
            composable(AppDetailRoutes.Invitation) { entry ->
                val socialViewModel: SocialViewModel = hiltViewModel()
                SocialInvitationDestination(
                    accountId = requireNotNull(accountId), localeTag = groupLocale,
                    invitationId = entry.arguments?.getString("id").orEmpty(), viewModel = socialViewModel,
                    onOpenGroup = { id, invitation -> navController.navigate(AppDetailRoutes.group(id, "invitation", invitation)) {
                        popUpTo(entry.destination.id) { inclusive = true }
                    } }, onBack = { navController.popBackStack() },
                )
            }
            composable(AppDetailRoutes.GroupInvite) { entry ->
                val socialViewModel: SocialViewModel = hiltViewModel()
                GroupInviteDestination(entry.arguments?.getString("token").orEmpty(), socialViewModel,
                    onResolved = { id -> navController.navigate(AppDetailRoutes.group(id, "group_invite")) {
                        popUpTo(entry.destination.id) { inclusive = true }
                    } }, onBack = { navController.popBackStack() })
            }
            composable(ASSISTANT_ROUTE) {
                // Reuse Today's shell-owned model, including its usable cached suggestion.
                val shellEntry = remember(navController) { navController.getBackStackEntry(APP_SHELL_ROUTE) }
                val todayViewModel: TodayViewModel = hiltViewModel(shellEntry)
                val todayState by todayViewModel.state.collectAsStateWithLifecycle()
                AssistantRoute(
                    requireNotNull(accountId),
                    screen = assistantEntryDestination,
                    hasFocusedWorkout = todayState.primarySuggestion != null,
                    onClose = { navController.popBackStack() },
                    onNavigate = navigate@{ route ->
                        // Dismiss and route in one host-owned handoff. Ignore repeated
                        // taps from the outgoing assistant composition.
                        if (navController.currentDestination?.route != ASSISTANT_ROUTE) return@navigate
                        navController.popBackStack()
                        val target = when (route) {
                            "today", "social", "me", MUSIC_ROUTE, ACTIVITY_HISTORY_ROUTE, HEALTH_ROUTE -> route
                            else -> TopLevelDestination.Me.route
                        }
                        integrationViewModel.trackAssistantDestinationOpened(target)
                        if (route == "settings") settingsRequest += 1
                        if (TopLevelDestination.entries.any { it.route == target }) {
                            selectTab(target)
                        } else {
                            navController.navigate(target) { launchSingleTop = true }
                        }
                    },
                    onPrepareActivity = { sport, distanceMeters, durationSeconds ->
                        val isBike = sport == VoiceSport.Bike
                        val goal = when {
                            distanceMeters != null -> RecordingGoal(RecordingGoalType.DISTANCE, targetDistanceMeters = distanceMeters)
                            durationSeconds != null -> RecordingGoal(RecordingGoalType.TIME, targetDurationSeconds = durationSeconds.toLong())
                            else -> RecordingGoal()
                        }
                        recordingLaunch = RecordingLaunchConfiguration(
                            activityKind = if (isBike) ActivityKind.CYCLING else ActivityKind.RUNNING,
                            goal = goal,
                            entrySource = "assistant",
                            gearId = integration.defaultGearId,
                        )
                        navController.navigate(RECORDING_ROUTE) { launchSingleTop = true }
                    },
                    onActionApplied = { todayRefreshRequest += 1 },
                )
            }
            composable(MY_QR_ROUTE) {
                InvitationCodeRoute(
                    onBack = { navController.popBackStack() },
                    entrySource = "me_profile_card",
                )
            }
            composable(
                AppDetailRoutes.Stretch,
                arguments = listOf(navArgument("source") { type = NavType.StringType; defaultValue = "standalone" }),
            ) { entry ->
                val stretchCoach: com.plainstride.outbound.feature.livecoach.LiveCoachViewModel = hiltViewModel()
                val stretchVoice by stretchCoach.selectedVoiceProfileId.collectAsStateWithLifecycle(initialValue = null)
                val source = if (entry.arguments?.getString("source") == "today") StretchEntryPoint.TODAY else StretchEntryPoint.STANDALONE
                StretchSessionRoute(
                    launch = StretchLaunchContext(entryPoint = source),
                    voiceProfileId = stretchVoice,
                    sessionKey = entry.id,
                    onDone = { navController.popBackStack() },
                    onEvent = { recordingViewModel.trackStretchEvent(it) },
                    fetchAudio = recordingViewModel::fetchStretchAudio,
                )
            }
            composable(RECORDING_ROUTE) {
                val feedbackCoach: com.plainstride.outbound.feature.livecoach.LiveCoachViewModel = hiltViewModel()
                val coachFeedback by feedbackCoach.feedback.collectAsStateWithLifecycle()
                val coachAdvice by feedbackCoach.advice.collectAsStateWithLifecycle()
                val stretchVoice by feedbackCoach.selectedVoiceProfileId.collectAsStateWithLifecycle(initialValue = null)
                RecordingRoute(
                    stretchVoiceProfileId = stretchVoice,
                    guidanceReport = coachFeedback.report,
                    coachingAdvice = coachAdvice,
                    selectedGuidanceFeedback = coachFeedback.selection,
                    onGuidanceFeedbackSelect = feedbackCoach::selectFeedback,
                    onGuidanceFeedbackSubmit = feedbackCoach::submitFeedback,
                    routeGuidanceContent = { snapshot, route, units, onDirectionsResult ->
                        LaunchedEffect(snapshot.sessionId, route.id) { recordingViewModel.trackRouteGuidanceDisplayed() }
                        com.plainstride.outbound.feature.community.LiveRouteGuidanceCard(snapshot, route, units, onDirectionsResult)
                    },
                    viewModel = recordingViewModel,
                    accountId = requireNotNull(accountId) { "Authenticated session is missing its account identifier." },
                    launch = recordingLaunch,
                    onPrepareActivityStart = {
                        cheerPickerViewModel.applyTrustedContactDefault()
                        voicePreparation.preparation.activityWillStart(recordingViewModel.state.value.launch.voiceGuideEnabled)
                    },
                    isOffline = connectivityState.isOffline,
                    unitSystem = measurementUnitSystem,
                    weightKilograms = integration.weightKilograms,
                    onSavedSideEffects = { review -> suppressRecordingRecovery = true; healthViewModel.export(review) },
                    onOpenAssistant = {
                        assistantEntryDestination = "recording"
                        integrationViewModel.trackAssistantOpened("today", "live_session")
                        navController.navigate(ASSISTANT_ROUTE) { launchSingleTop = true }
                    },
                    onCheerMeOn = { cheerPickerVisible = true },
                    cheerSelectedName = integration.connections.firstOrNull { it.id in selectedCheerIdSet }?.displayName,
                    cheerSelectedCount = selectedCheerIdSet.size,
                    liveSharingEnabled = activeCheerShare?.status == "active",
                    onSaved = { review: RecordedActivityReview, photoAlbumExport: ActivityPhotoAlbumExportResult? ->
                        val photoMessage = when (photoAlbumExport) {
                            ActivityPhotoAlbumExportResult.SAVED -> R.string.photo_album_saved
                            ActivityPhotoAlbumExportResult.PERMISSION_DENIED -> R.string.photo_album_permission_denied
                            ActivityPhotoAlbumExportResult.FAILED -> R.string.photo_album_save_failed
                            ActivityPhotoAlbumExportResult.ALREADY_SAVED, null -> null
                        }
                        photoMessage?.let { message ->
                            scope.launch { snackbar.showSnackbar(resources.getString(message)) }
                        }
                        selectTab(TopLevelDestination.Me.route)
                    },
                    onExit = {
                        suppressRecordingRecovery = true
                        selectTab(TopLevelDestination.Today.route)
                    },
                    groupRun=sharedLiveGroupRun?.toSharedLiveRun(),
                    groupRunJoining=groupRunJoining,
                    onToggleActivityLiveMap={recordingViewModel.state.value.launch.activityEventId?.let(toggleActivityLiveMap)},
                    onStopActivityLiveMap=stopActivityLiveMap,
                    sessionEffect = { snapshot, liveLaunch ->
                        LiveCoachRecordingEffect(liveLaunch, measurementUnitSystem, feedbackCoach)
                        RecordingSafetyEffect(snapshot, liveLaunch.activityEventId, voiceEnabled = liveLaunch.voiceGuideEnabled)
                    },
                    saveActivityPhotosToAlbum = settingsState.preferences.saveActivityPhotosToAlbum,
                    onPhotoAlbumPermissionDenied = {
                        settingsViewModel.setSaveActivityPhotosToAlbum(false, showMessage = false)
                    },
                )
            }
            composable(ACTIVITY_HISTORY_ROUTE) {
                ActivityHistoryRoute(
                    accountId = requireNotNull(accountId), unitSystem = measurementUnitSystem,
                    onOpenActivity = { navController.navigate(AppDetailRoutes.activity(it, "history")) },
                    onBack = { navController.popBackStack() },
                    onMessage = { message -> scope.launch { snackbar.showSnackbar(resources.getString(activityMessageResource(message))) }; Unit },
                )
            }
            composable(AppDetailRoutes.Activity) { entry ->
                ActivityDetailDestination(
                    accountId = requireNotNull(accountId), activityId = entry.arguments?.getString("id").orEmpty(),
                    entrySource = entry.arguments?.getString("source") ?: "deep_link", unitSystem = measurementUnitSystem,
                    weightKilograms = integration.weightKilograms, onBack = { navController.popBackStack() },
                    onMessage = { message -> scope.launch { snackbar.showSnackbar(resources.getString(activityMessageResource(message))) }; Unit },
                    onPublishRoute = { id, name -> integrationViewModel.publishSavedActivityRoute(id, name) },
                    onOpenGroupActivity = { navController.navigate(AppDetailRoutes.event(it, "activity_detail")) },
                )
            }
            composable(MUSIC_ROUTE) { MusicRoute(onClose = { navController.popBackStack() }) }
            composable(PROGRESS_ROUTE) {
                val progress = integration.progress.copy(
                    unitSystem = if (measurementUnitSystem == MeasurementUnitSystem.metric) ProgressUnitSystem.METRIC else ProgressUnitSystem.IMPERIAL,
                )
                ProgressRoute(progress, onAnalyticsEvent = integrationViewModel::trackProgressEvent, onRefresh = integrationViewModel::refreshStatistics)
            }
            composable(COMMUNITY_ROUTES_ROUTE) {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    Column(Modifier.fillMaxSize()) {
                        if (!selectingRouteForToday) Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                            androidx.compose.material3.IconButton(onClick = { navController.popBackStack() }) {
                                Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(com.plainstride.outbound.feature.community.R.string.routes_close))
                            }
                            Text(stringResource(com.plainstride.outbound.feature.community.R.string.routes_title), style = MaterialTheme.typography.titleLarge)
                        }
                        Box(Modifier.weight(1f)) {
                            key(selectingRouteForToday) {
                                CommunityRouteScreen(requireNotNull(accountId),{navController.navigate(AppDetailRoutes.route(it.id))},integration.routes, integration.routeScope, integrationViewModel::scope, integrationViewModel::refreshRoutes, integrationViewModel::search,integrationViewModel::trackRouteImport,routeDetail=integration.selectedCommunityRoute,routeDetailLoading=integration.communityRouteLoading,onLoadDetail=integrationViewModel::loadCommunityRoute,unitSystem=measurementUnitSystem,searchQuery=integration.routeQuery,selectionMode=selectingRouteForToday,initialSelection=todaySelectedRoute,initialSelectionReverse=todayRouteReversed,onSelectRoute={route,reverse->val removedRoute=todaySelectedRoute.takeIf{route==null};todaySelectedRoute=route;todayRouteReversed=reverse;selectingRouteForToday=false;integrationViewModel.clearCommunityRoute();navController.popBackStack();if(removedRoute!=null)integrationViewModel.trackTodayRouteRemoved(removedRoute) else route?.let{integrationViewModel.trackTodayRouteSelected(it)}},onDismissSelection={selectingRouteForToday=false;integrationViewModel.clearCommunityRoute();navController.popBackStack()})
                            }
                        }
                    }
                }
            }
            composable(AppDetailRoutes.Route) { entry ->
                CommunityRouteDetailDestination(
                    accountId = requireNotNull(accountId), routeId = entry.arguments?.getString("routeId").orEmpty(),
                    unitSystem = measurementUnitSystem,
                    onFollow = { route, reverse ->
                        todaySelectedRoute = route
                        todayRouteReversed = reverse
                        selectingRouteForToday = false
                        integrationViewModel.clearCommunityRoute()
                        integrationViewModel.trackTodayRouteSelected(route)
                        if (reverse) integrationViewModel.trackTodayRouteDirection(true)
                        selectTab(TopLevelDestination.Today.route)
                    },
                    onBack = { navController.popBackStack() }, onChanged = { integrationViewModel.refreshRoutes() },
                    onImportedDelete = integrationViewModel::trackImportedRouteDeleted,
                )
            }
            composable(SAFETY_ROUTE) { SafetyRoute(connections = integration.connections, accountId = accountId, unitSystem = measurementUnitSystem) }
            composable(AppDetailRoutes.Safety) { entry ->
                SafetyRoute(targetId = entry.arguments?.getString("id"), targetKind = entry.arguments?.getString("kind") ?: "live",
                    connections = integration.connections, accountId = accountId, unitSystem = measurementUnitSystem,
                    liveCheerEntrySource = entry.arguments?.getString("source") ?: "notification", onBack = { navController.popBackStack() })
            }
            composable(TRUSTED_CONTACTS_ROUTE) {
                TrustedContactsSettingsScreen(
                    connections = integration.connections,
                    trustedContacts = trustedContacts,
                    sharesWithTrustedContactsByDefault = sharesWithTrustedContactsByDefault,
                    onTrustedChange = cheerPickerViewModel::setTrusted,
                    onDefaultSharingChange = cheerPickerViewModel::setSharesWithTrustedContactsByDefault,
                    onBack = { navController.popBackStack() },
                    onOpenConnections = {
                        navController.navigate(AppDetailRoutes.connections("trusted_contacts")) { launchSingleTop = true }
                    },
                )
            }
            composable(HEALTH_ROUTE) { HealthDestination(healthPermissions, healthViewModel::refresh) { navController.popBackStack() } }
            composable(NOTIFICATIONS_ROUTE) {
                LaunchedEffect(Unit) { integrationViewModel.openInbox() }
                NotificationInbox(integration.notifications, onBack = { navController.popBackStack() }) { item ->
                    integrationViewModel.openNotification(item)
                    val route = notificationRoute(item)
                    navController.navigate(route) { launchSingleTop = true }
                }
            }
            composable(AppDetailRoutes.Notification) { entry ->
                NotificationDestination(requireNotNull(accountId), requireNotNull(entry.arguments?.getString("id")), onBack = { navController.popBackStack() })
            }
            composable(REWARDS_ROUTE) { RewardsRoute(onBack = { navController.popBackStack() }, onRedeem = { navController.navigate(REWARD_REDEMPTION_ROUTE) }) }
            composable(REWARD_REDEMPTION_ROUTE) { RewardRedemptionRoute(onBack = { navController.popBackStack() }) }
            composable(INVITATION_CODE_ROUTE) {
                InvitationCodeRoute(
                    onBack = { navController.popBackStack() },
                    entrySource = "me_invitation_code",
                )
            }
            composable(PLUS_ROUTE) { PlusRoute(onBack = { navController.popBackStack() }) }
        }
        }
        if (cheerPickerVisible) {
            CheerInvitationPickerDialog(
                connections = integration.connections,
                trustedContacts = trustedContacts,
                currentSelection = selectedCheerIdSet,
                onDismiss = { cheerPickerVisible = false },
                onSetUpTrustedContacts = {
                    cheerPickerVisible = false
                    navController.navigate(TRUSTED_CONTACTS_ROUTE)
                },
                onDone = { ids ->
                    scope.launch {
                        if (cheerPickerViewModel.configureCheerRecipients(ids)) cheerPickerVisible = false
                        else {
                            cheerPickerVisible = false
                            snackbar.showSnackbar(resources.getString(com.plainstride.outbound.feature.safety.R.string.live_cheer_invitation_failed))
                        }
                    }
                },
            )
        }
        planBuilderSource?.let { source ->
        Dialog(
            onDismissRequest = {},
            properties = DialogProperties(
                usePlatformDefaultWidth = false,
                dismissOnBackPress = false,
                dismissOnClickOutside = false,
            ),
        ) {
            Surface(Modifier.fillMaxSize()) {
                OnboardingRoute(
                    source = source,
                    usesMetric = measurementUnitSystem == MeasurementUnitSystem.metric,
                    onComplete = {
                        planBuilderSource = null
                        todayRefreshRequest += 1
                    },
                    onMessage = { effect ->
                        val message = when (effect) {
                            OnboardingEffect.IdentityUnavailable -> R.string.onboarding_identity_unavailable
                            OnboardingEffect.HealthUnavailable -> R.string.onboarding_health_unavailable
                            OnboardingEffect.ProfileUnavailable -> R.string.onboarding_save_unavailable
                            OnboardingEffect.RunningScheduleConflict -> OnboardingR.string.planning_running_schedule_conflict
                            OnboardingEffect.ProgrammeTimelineConflict -> OnboardingR.string.planning_programme_timeline_conflict
                            OnboardingEffect.ProgrammeConstraintsConflict -> OnboardingR.string.planning_programme_constraints_conflict
                            OnboardingEffect.GoalTimelineUnrealistic -> OnboardingR.string.planning_goal_timeline_unrealistic
                    OnboardingEffect.PlanCreationUnavailable -> OnboardingR.string.plan_builder_create_error
                            OnboardingEffect.SkipUnavailable -> OnboardingR.string.plan_builder_skip_error
                            OnboardingEffect.Completed, OnboardingEffect.FailedOpen -> return@OnboardingRoute
                        }
                        android.widget.Toast.makeText(
                            context,
                            resources.getString(message),
                            android.widget.Toast.LENGTH_SHORT,
                        ).show()
                    },
                )
            }
        }
        }
    }
    if (addShoeSheetVisible) {
        AddShoeSheet(
            units = if (measurementUnitSystem == MeasurementUnitSystem.metric) ProgressUnitSystem.METRIC else ProgressUnitSystem.IMPERIAL,
            onDismiss = { addShoeSheetVisible = false },
            onAdd = { shoe: NewShoe -> integrationViewModel.addGearShoe(shoe); addShoeSheetVisible = false },
        )
    }
    if (showNotificationPermissionPrimer) AlertDialog(
        onDismissRequest = {
            integrationViewModel.trackPushPermissionPromptAction("authenticated_entry", "not_now")
            showNotificationPermissionPrimer = false
        },
        title = { Text(stringResource(SocialR.string.social_notifications_permission_primer_title)) },
        text = { Text(stringResource(SocialR.string.social_notifications_permission_body)) },
        confirmButton = {
            TextButton(onClick = {
                integrationViewModel.trackPushPermissionPromptAction("authenticated_entry", "enable")
                showNotificationPermissionPrimer = false
                requestNotificationPermission(forPush = true, forReminder = reminderEnabled)
            }) { Text(stringResource(SocialR.string.social_notifications_permission_enable)) }
        },
        dismissButton = {
            TextButton(onClick = {
                integrationViewModel.trackPushPermissionPromptAction("authenticated_entry", "not_now")
                showNotificationPermissionPrimer = false
            }) { Text(stringResource(SocialR.string.social_notifications_permission_not_now)) }
        },
    )
    if (authState.confirmDeletion) AlertDialog(
        onDismissRequest = authViewModel::cancelDeletion,
        title = { Text(stringResource(R.string.delete_account_title)) },
        text = { Text(stringResource(R.string.delete_account_body)) },
        confirmButton = { TextButton(onClick = { authViewModel.deleteAccount(context) }) { Text(stringResource(R.string.delete_account_confirm)) } },
        dismissButton = { TextButton(onClick = authViewModel::cancelDeletion) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun ConnectivityBanner(state: ConnectivityUiState, modifier: Modifier = Modifier) {
    if (!state.isOffline) return
    val message = stringResource(R.string.connectivity_offline)
    val accessibilityLabel = stringResource(R.string.connectivity_offline_accessibility)
    Surface(
        modifier = modifier.semantics(mergeDescendants = true) { contentDescription = accessibilityLabel },
        shape = RoundedCornerShape(50),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
        shadowElevation = 6.dp,
        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.tertiary.copy(alpha = 0.28f)),
    ) {
        Row(
            Modifier.padding(horizontal = 14.dp).height(36.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(7.dp),
        ) {
            Icon(Icons.Default.CloudOff, null, tint = MaterialTheme.colorScheme.tertiary, modifier = Modifier.size(16.dp))
            Text(message, style = MaterialTheme.typography.labelMedium, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
        }
    }
}

@Composable
private fun MeBenefitDestinationCard(
    @StringRes title: Int,
    @StringRes body: Int,
    icon: ImageVector,
    onClick: () -> Unit,
) {
    OutlinedCard(Modifier.fillMaxWidth().clickable(onClick = onClick)) {
        ListItem(
            headlineContent = { Text(stringResource(title)) },
            supportingContent = { Text(stringResource(body)) },
            leadingContent = { Icon(icon, null, tint = MaterialTheme.colorScheme.primary) },
        )
    }
}

private const val RECORDING_ROUTE = "recording"
private const val APP_SHELL_ROUTE = "app_shell"
private const val ASSISTANT_ROUTE = "assistant"
private const val MY_QR_ROUTE = "my_qr"
private const val MUSIC_ROUTE = "music"
private const val ACTIVITY_HISTORY_ROUTE = "activity_history"
private const val CONNECTION_SCANNER_ROUTE = "connection_scanner"
private const val PROGRESS_ROUTE = "progress"
private const val COMMUNITY_ROUTES_ROUTE = "community_routes"
private const val SAFETY_ROUTE = "safety"
private const val TRUSTED_CONTACTS_ROUTE = "trusted_contacts"
private const val HEALTH_ROUTE = "health"
private const val NOTIFICATIONS_ROUTE = "notifications"
private const val REWARDS_ROUTE = "rewards"
private const val REWARD_REDEMPTION_ROUTE = "reward-redemption"
private const val INVITATION_CODE_ROUTE = "invitation-code"
private const val PLUS_ROUTE = "plus"

private fun recordingLocationPermission(context: android.content.Context): LocationPermissionState = when {
    context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED -> LocationPermissionState.PRECISE
    context.checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED -> LocationPermissionState.APPROXIMATE
    else -> LocationPermissionState.DENIED
}

private fun notificationAccessAvailable(context: android.content.Context): Boolean =
    (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
        context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        NotificationManagerCompat.from(context).areNotificationsEnabled()

private fun openAppNotificationSettings(context: android.content.Context) {
    val notificationSettings = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(notificationSettings) }
        .getOrElse {
            context.startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
}

@Composable private fun HealthDestination(snapshot: HealthPermissionSnapshot?, refresh:()->Unit, dismiss:()->Unit) {
    val context=LocalContext.current
    val launcher=rememberLauncherForActivityResult(androidx.health.connect.client.PermissionController.createRequestPermissionResultContract()){refresh()}
    if(snapshot==null) Box(Modifier.fillMaxSize(),contentAlignment=Alignment.Center){CircularProgressIndicator()} else HealthConnectEducation(snapshot,{launcher.launch(it)},{
        val intent=Intent(androidx.health.connect.client.HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)
        runCatching{context.startActivity(intent)}.getOrElse{context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,android.net.Uri.parse("package:${context.packageName}")))}
    },dismiss)
}

@StringRes
private fun activityMessageResource(message: ActivityMessage): Int = when (message) {
    ActivityMessage.SAVED -> com.plainstride.outbound.feature.activity.R.string.activity_saved
    ActivityMessage.UPDATED -> com.plainstride.outbound.feature.activity.R.string.activity_updated
    ActivityMessage.DELETED -> com.plainstride.outbound.feature.activity.R.string.activity_deleted
    ActivityMessage.FAILED -> com.plainstride.outbound.feature.activity.R.string.activity_failed
    ActivityMessage.EXPORT_UNAVAILABLE -> com.plainstride.outbound.feature.activity.R.string.activity_export_unavailable
}

private fun RecordingLaunchConfiguration.withTodayRoute(
    route: com.plainstride.outbound.feature.community.CommunityRoute?,
    reverse: Boolean,
): RecordingLaunchConfiguration {
    if (route == null) return this
    val routeLaunch = com.plainstride.outbound.feature.community.CommunityRecordingCoordinator.launch(route, reverse)
    val preservesWorkoutStructure = activityKind == routeLaunch.activityKind
    return copy(
        activityKind = routeLaunch.activityKind,
        title = route.name,
        workoutSteps = workoutSteps.takeIf { preservesWorkoutStructure }.orEmpty(),
        plannedWorkoutId = plannedWorkoutId.takeIf { preservesWorkoutStructure },
        performedWorkoutReference = performedWorkoutReference.takeIf { preservesWorkoutStructure },
        standaloneWorkoutId = standaloneWorkoutId.takeIf { preservesWorkoutStructure },
        standaloneWorkoutCatalogVersion = standaloneWorkoutCatalogVersion.takeIf { preservesWorkoutStructure },
        workoutDetail = workoutDetail.takeIf { preservesWorkoutStructure },
        workoutGuideline = workoutGuideline.takeIf { preservesWorkoutStructure },
        privateTrainingSignal = privateTrainingSignal.takeIf { preservesWorkoutStructure },
        workoutPhase = workoutPhase.takeIf { preservesWorkoutStructure },
        workoutTargetPaceSecondsPerKilometer = workoutTargetPaceSecondsPerKilometer.takeIf { preservesWorkoutStructure },
        workoutFasterToleranceSeconds = workoutFasterToleranceSeconds.takeIf { preservesWorkoutStructure },
        workoutSlowerToleranceSeconds = workoutSlowerToleranceSeconds.takeIf { preservesWorkoutStructure },
        workoutRecognizesTargetLock = workoutRecognizesTargetLock && preservesWorkoutStructure,
        raceIntent = raceIntent.takeIf { preservesWorkoutStructure },
        followedRoute = routeLaunch.followedRoute,
        startImmediately = true,
    )
}

private fun TodayManualLaunch.toRecordingLaunch(defaultGearId: String?, athleteReferencePace: Double?): RecordingLaunchConfiguration {
    val workout = curatedWorkout.takeUnless { goal == TodayGoalChoice.RACE }
    val recordingGoal = when (goal) {
        TodayGoalChoice.RACE -> RecordingGoal(RecordingGoalType.DISTANCE, targetDistanceMeters = requireNotNull(racePlan).distanceMeters)
        TodayGoalChoice.DISTANCE -> RecordingGoal(RecordingGoalType.DISTANCE, targetDistanceMeters = distanceMeters)
        TodayGoalChoice.TIME -> RecordingGoal(RecordingGoalType.TIME, targetDurationSeconds = durationSeconds)
        TodayGoalChoice.CALORIES -> RecordingGoal(RecordingGoalType.CALORIES, targetCalories = calories)
        TodayGoalChoice.CURATED -> RecordingGoal(RecordingGoalType.WORKOUT, targetDurationSeconds = workout?.targetDurationSeconds?.toLong() ?: durationSeconds)
        TodayGoalChoice.FREE -> RecordingGoal()
    }
    return RecordingLaunchConfiguration(
        activityKind = when (activity) {
            TodayActivityChoice.WALK -> ActivityKind.WALKING
            TodayActivityChoice.HIKE -> ActivityKind.HIKING
            TodayActivityChoice.BIKE -> ActivityKind.CYCLING
            else -> ActivityKind.RUNNING
        },
        title = raceTitle ?: workout?.title,
        raceIntent = racePlan.takeIf { goal == TodayGoalChoice.RACE }?.let {
            com.plainstride.outbound.feature.recording.RecordingRaceIntent(it.distanceMeters, "target_time", it.goalTimeSeconds, it.targetPaceSecondsPerKilometer, it.pacingStrategy, it.recommendationSource)
        },
        goal = recordingGoal,
        workoutGuideline = raceGuideline.takeIf { goal == TodayGoalChoice.RACE },
        workoutSteps = workout?.steps?.map {
            StructuredWorkoutStep(
                title = it.label,
                detail = it.detail,
                durationSeconds = it.durationSeconds,
                phase = it.coachingTarget?.phase,
                targetPaceSecondsPerKilometer = it.coachingTarget?.pace?.resolveTarget(athleteReferencePace),
                fasterToleranceSeconds = it.coachingTarget?.pace?.fasterToleranceSeconds,
                slowerToleranceSeconds = it.coachingTarget?.pace?.slowerToleranceSeconds,
                recognizesTargetLock = it.coachingTarget?.recognizesTargetLock == true,
            )
        }.orEmpty(),
        entrySource = "today_manual",
        standaloneWorkoutId = workout?.id,
        standaloneWorkoutCatalogVersion = curatedWorkoutCatalogVersion,
        autoStopAtGoal = autoStopAtGoal && goal in setOf(TodayGoalChoice.DISTANCE, TodayGoalChoice.TIME, TodayGoalChoice.CALORIES),
        workoutPhase = if (goal == TodayGoalChoice.RACE) "work" else workout?.coachingTarget?.phase,
        workoutTargetPaceSecondsPerKilometer = racePlan.takeIf { goal == TodayGoalChoice.RACE }?.targetPaceSecondsPerKilometer ?: workout?.coachingTarget?.pace?.resolveTarget(athleteReferencePace),
        workoutFasterToleranceSeconds = if (goal == TodayGoalChoice.RACE && racePlan?.targetPaceSecondsPerKilometer != null) 15.0 else workout?.coachingTarget?.pace?.fasterToleranceSeconds,
        workoutSlowerToleranceSeconds = if (goal == TodayGoalChoice.RACE && racePlan?.targetPaceSecondsPerKilometer != null) 20.0 else workout?.coachingTarget?.pace?.slowerToleranceSeconds,
        workoutRecognizesTargetLock = if (goal == TodayGoalChoice.RACE) racePlan?.targetPaceSecondsPerKilometer != null else workout?.coachingTarget?.recognizesTargetLock == true,
        gearId = defaultGearId,
        indoor = indoor,
        voiceGuideEnabled = voiceGuideEnabled,
        aiCoachEnabled = aiCoachEnabled,
        startImmediately = true,
        companionType = companionType,
    )
}

@Composable
private fun FoundationScreen(destination: TopLevelDestination, authState: AuthUiState, authViewModel: AuthViewModel) {
    val context = LocalContext.current
    Box(
        modifier = Modifier.fillMaxSize().padding(horizontal = 32.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                text = stringResource(destination.headline),
                style = MaterialTheme.typography.headlineMedium,
                textAlign = TextAlign.Center,
            )
            Text(
                text = stringResource(destination.body),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyLarge,
                textAlign = TextAlign.Center,
            )
            if (destination == TopLevelDestination.Me) {
                Button(onClick = { authViewModel.linkGoogle(context) }, enabled = authState.operation == null) {
                    Text(stringResource(R.string.link_google))
                }
                TextButton(onClick = authViewModel::signOut, enabled = authState.operation == null) {
                    Text(stringResource(R.string.sign_out))
                }
                TextButton(onClick = authViewModel::requestDeletion, enabled = authState.operation == null) {
                    Text(stringResource(R.string.delete_account))
                }
            }
        }
    }
}

@Composable
private fun SignInScreen(
    state: AuthUiState,
    viewModel: AuthViewModel,
    snackbar: SnackbarHostState,
    initialTransferCode: String?,
    onTransferCodeConsumed: () -> Unit,
) {
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    var showsTransfer by remember { mutableStateOf(initialTransferCode != null) }
    var transferCode by remember { mutableStateOf(initialTransferCode.orEmpty()) }
    LaunchedEffect(initialTransferCode) {
        if (initialTransferCode != null) {
            showsTransfer = true
            transferCode = initialTransferCode
        }
    }
    Scaffold(snackbarHost = { SnackbarHost(snackbar) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).padding(horizontal = 20.dp, vertical = 18.dp)) {
            Text(stringResource(R.string.auth_wordmark), style = MaterialTheme.typography.labelLarge)
            Spacer(Modifier.weight(0.35f))
            WelcomeOrbit(Modifier.fillMaxWidth().padding(bottom = 24.dp))
            Text(stringResource(R.string.auth_companion_eyebrow), Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.labelMedium, textAlign = TextAlign.Center)
            Text(stringResource(R.string.auth_companion_headline), Modifier.fillMaxWidth().padding(top = 10.dp), style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center)
            Spacer(Modifier.weight(0.65f))
            OutlinedButton(
                onClick = { viewModel.signIn(context) },
                enabled = state.operation == null,
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(14.dp),
            ) { Text(stringResource(if (state.operation == AuthOperation.SignIn) R.string.signing_in else R.string.continue_with_google)) }
            TextButton(onClick = { showsTransfer = !showsTransfer }, enabled = state.operation == null) {
                Text(stringResource(R.string.transfer_existing_account))
            }
            if (showsTransfer) {
                Text(
                    stringResource(R.string.transfer_explanation),
                    modifier = Modifier.padding(top = 12.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center,
                )
                OutlinedTextField(
                    value = transferCode,
                    onValueChange = { transferCode = it.take(32) },
                    label = { Text(stringResource(R.string.transfer_code_label)) },
                    singleLine = true,
                    enabled = state.operation == null,
                    modifier = Modifier.padding(top = 8.dp),
                )
                Button(
                    onClick = {
                        viewModel.redeemTransfer(context, transferCode)
                        onTransferCodeConsumed()
                    },
                    enabled = state.operation == null && transferCode.isNotBlank(),
                    modifier = Modifier.padding(top = 8.dp),
                ) {
                    Text(stringResource(if (state.operation == AuthOperation.Redeem) R.string.transfer_connecting else R.string.transfer_connect))
                }
            }
            val termsLabel = stringResource(R.string.auth_terms_link)
            val privacyLabel = stringResource(R.string.auth_privacy_link)
            val legalNotice = stringResource(R.string.auth_terms_notice, termsLabel, privacyLabel)
            val linkStyles = TextLinkStyles(SpanStyle(
                color = MaterialTheme.colorScheme.primary,
                textDecoration = TextDecoration.Underline,
            ))
            Text(
                text = buildAnnotatedString {
                    append(legalNotice)
                    listOf(
                        Triple(termsLabel, "terms", "https://plainstride.ai/terms"),
                        Triple(privacyLabel, "privacy", "https://plainstride.ai/privacy"),
                    ).forEach { (label, document, url) ->
                        val start = legalNotice.indexOf(label)
                        if (start >= 0) {
                            addLink(LinkAnnotation.Url(url, linkStyles) {
                                viewModel.trackLegal(document)
                                uriHandler.openUri(url)
                            }, start, start + label.length)
                        }
                    }
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun WelcomeOrbit(modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.height(220.dp)) {
        val centerX = maxWidth / 2
        val orbitColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.16f)

        Canvas(Modifier.fillMaxSize()) {
            val orbitWidth = minOf(size.width - 34.dp.toPx(), 272.dp.toPx())
            val orbitHeight = 132.dp.toPx()
            rotate(-8f, pivot = Offset(size.width / 2, 104.dp.toPx())) {
                drawOval(
                    color = orbitColor,
                    topLeft = Offset((size.width - orbitWidth) / 2, 104.dp.toPx() - orbitHeight / 2),
                    size = Size(orbitWidth, orbitHeight),
                    style = Stroke(width = 2.dp.toPx()),
                )
            }
        }

        OrbitPerson(R.string.auth_orbit_family, Icons.Default.Favorite, Modifier.offset(x = centerX - 140.dp, y = 19.dp))
        OrbitPerson(R.string.auth_orbit_friends, Icons.Default.Group, Modifier.offset(x = centerX + 76.dp, y = 34.dp))
        OrbitPerson(R.string.auth_orbit_groups, Icons.Default.Groups2, Modifier.offset(x = centerX - 131.dp, y = 110.dp))

        Box(Modifier.offset(x = centerX - 38.dp, y = 67.dp).size(76.dp)) {
            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.secondaryContainer,
                modifier = Modifier.fillMaxSize().border(4.dp, MaterialTheme.colorScheme.background, CircleShape),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(Icons.Default.Person, stringResource(R.string.auth_orbit_you), Modifier.size(34.dp))
                }
            }
            Surface(
                shape = CircleShape,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.align(Alignment.TopEnd).offset(x = 4.dp, y = (-4).dp)
                    .size(27.dp).border(3.dp, MaterialTheme.colorScheme.background, CircleShape),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(Icons.Default.AutoAwesome, null, Modifier.size(13.dp), tint = MaterialTheme.colorScheme.onPrimary)
                }
            }
        }

        Surface(
            shape = RoundedCornerShape(20.dp),
            color = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f),
            modifier = Modifier.align(Alignment.TopCenter).offset(y = 184.dp),
        ) {
            Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.AutoAwesome, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.auth_better_together), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            }
        }
    }
}

@Composable
private fun OrbitPerson(label: Int, icon: androidx.compose.ui.graphics.vector.ImageVector, modifier: Modifier) {
    Surface(
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = modifier.size(64.dp).border(4.dp, MaterialTheme.colorScheme.background, CircleShape),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Icon(icon, null, Modifier.size(19.dp), tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.72f))
            Text(stringResource(label), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.72f))
        }
    }
}

@StringRes
private fun authMessageResource(message: AuthMessage) = when (message) {
    AuthMessage.Cancelled -> R.string.auth_cancelled
    AuthMessage.Configuration -> R.string.auth_configuration_error
    AuthMessage.InvalidCredential -> R.string.auth_invalid_credential
    AuthMessage.InvalidTransfer -> R.string.transfer_invalid
    AuthMessage.Conflict -> R.string.auth_identity_conflict
    AuthMessage.Offline -> R.string.auth_offline
    AuthMessage.Unavailable -> R.string.auth_unavailable
    AuthMessage.Generic -> R.string.auth_generic_error
    AuthMessage.Linked -> R.string.auth_linked
    AuthMessage.Transferred -> R.string.transfer_complete
    AuthMessage.SignedOut -> R.string.auth_signed_out
    AuthMessage.Deleted -> R.string.auth_deleted
}

@StringRes
private fun todayMessageResource(message: TodayMessage) = when (message) {
    TodayMessage.CouldNotRefresh -> com.plainstride.outbound.feature.today.R.string.today_refresh_failed
    TodayMessage.ReadinessSavedOffline -> com.plainstride.outbound.feature.today.R.string.today_readiness_saved_offline
    TodayMessage.CouldNotAdjust -> com.plainstride.outbound.feature.today.R.string.today_adjust_failed
    TodayMessage.AdjustmentApplied -> com.plainstride.outbound.feature.today.R.string.today_adjust_applied
    TodayMessage.OriginalKept -> com.plainstride.outbound.feature.today.R.string.today_original_kept
    TodayMessage.PlanEnded -> com.plainstride.outbound.feature.today.R.string.plan_details_ended
    TodayMessage.CouldNotEndPlan -> com.plainstride.outbound.feature.today.R.string.plan_details_end_failed
}

@StringRes
private fun settingsMessageResource(message: SettingsMessage) = when (message) {
    SettingsMessage.Refreshed -> com.plainstride.outbound.feature.settings.R.string.settings_refreshed
    SettingsMessage.Saved -> com.plainstride.outbound.feature.settings.R.string.settings_saved
    SettingsMessage.SaveFailed -> com.plainstride.outbound.feature.settings.R.string.settings_save_failed
    SettingsMessage.RefreshFailed -> com.plainstride.outbound.feature.settings.R.string.settings_refresh_failed
}

private tailrec fun android.content.Context.findActivity(): android.app.Activity? = when (this) {
    is android.app.Activity -> this
    is android.content.ContextWrapper -> baseContext.findActivity()
    else -> null
}

private fun notificationRoute(item: NotificationCenterItem): String = when (val destination = item.presentation.destination) {
    NotificationDestination.Connections -> AppDetailRoutes.connections("notification")
    is NotificationDestination.Activity -> AppDetailRoutes.activity(destination.id, "notification")
    is NotificationDestination.Post -> AppDetailRoutes.post(destination.id)
    is NotificationDestination.Event -> AppDetailRoutes.event(destination.id, "notification")
    is NotificationDestination.Invitation -> AppDetailRoutes.invitation(destination.id)
    is NotificationDestination.Group -> AppDetailRoutes.group(destination.id, "notification")
    is NotificationDestination.GroupRun -> AppDetailRoutes.safety("group", destination.id, "notification")
    is NotificationDestination.Live -> AppDetailRoutes.safety("live", destination.id, "notification")
    NotificationDestination.Inbox -> AppDetailRoutes.notification(item.primary.id)
}
