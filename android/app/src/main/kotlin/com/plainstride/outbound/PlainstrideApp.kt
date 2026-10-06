package com.plainstride.outbound

import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.Image
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
import androidx.compose.ui.draw.blur
import androidx.compose.material3.MaterialTheme
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.ui.graphics.graphicsLayer
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
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalContext
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
import androidx.lifecycle.LifecycleEventObserver
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.dialog
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navDeepLink
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.plainstride.outbound.auth.AuthMessage
import com.plainstride.outbound.auth.AuthOperation
import com.plainstride.outbound.auth.AuthUiState
import com.plainstride.outbound.auth.AuthViewModel
import com.plainstride.outbound.connectivity.ConnectivityViewModel
import com.plainstride.outbound.connectivity.ConnectivityUiState
import com.plainstride.outbound.core.auth.SessionState
import com.plainstride.outbound.core.designsystem.PlainstrideFloatingAction
import com.plainstride.outbound.core.designsystem.PlainstrideFloatingActionStyle
import com.plainstride.outbound.core.designsystem.LocalPlainstrideThemeColors
import com.plainstride.outbound.core.designsystem.PrimaryBottomToolbarClearance
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
import com.plainstride.outbound.feature.recording.ActivityKind
import com.plainstride.outbound.feature.recording.ActivityPhotoAlbumExportResult
import com.plainstride.outbound.feature.recording.RecordedActivityReview
import com.plainstride.outbound.feature.recording.RecordingGoal
import com.plainstride.outbound.feature.recording.RecordingGoalType
import com.plainstride.outbound.feature.recording.RecordingLaunchConfiguration
import com.plainstride.outbound.feature.recording.RecordingRoute
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
import com.plainstride.outbound.feature.social.SocialPerson
import com.plainstride.outbound.feature.today.WorkoutLaunchIntent
import com.plainstride.outbound.feature.today.TodayManualLaunch
import com.plainstride.outbound.feature.today.TodayActivityChoice
import com.plainstride.outbound.feature.today.TodayGoalChoice
import com.plainstride.outbound.feature.today.TodayShoeOption
import com.plainstride.outbound.feature.today.TodayRouteSelection
import com.plainstride.outbound.core.designsystem.MapCoordinate
import com.plainstride.outbound.core.model.Modality
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
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
import kotlinx.coroutines.launch
import kotlinx.coroutines.delay
import kotlinx.coroutines.coroutineScope
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

private data class SocialNavigationTarget(
    val type: String,
    val id: String = "",
    val entrySource: String = "deep_link",
)

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
    val currentDestination = backStackEntry?.destination
    var recordingLaunch by remember { mutableStateOf(RecordingLaunchConfiguration()) }
    var selectingRouteForToday by rememberSaveable { mutableStateOf(false) }
    var socialTarget by remember { mutableStateOf<SocialNavigationTarget?>(null) }
    var sharedSocialProfile by remember { mutableStateOf<SocialPerson?>(null) }
    var activityTarget by remember { mutableStateOf<String?>(null) }
    var safetyTarget by remember { mutableStateOf<Pair<String,String>?>(null) }
    var notificationDetailID by remember { mutableStateOf<String?>(null) }
    var reminderWorkoutId by remember { mutableStateOf<String?>(null) }
    var todayStartRequest by remember { mutableStateOf(0) }
    var todayRefreshRequest by remember { mutableStateOf(0) }
    var planBuilderSource by remember { mutableStateOf<PlanBuilderSource?>(null) }
    var assistantEntryDestination by remember { mutableStateOf("me") }
    var settingsRequest by remember { mutableStateOf(0) }
    var trackedAssistantExposure by remember { mutableStateOf(false) }
    var trackedAssistantAnimation by remember { mutableStateOf(false) }
    var cheerPickerVisible by remember { mutableStateOf(false) }
    var addShoeSheetVisible by remember { mutableStateOf(false) }
    val activeRecordingViewModel:ActiveRecordingViewModel=hiltViewModel()
    val hasActiveSession by activeRecordingViewModel.active.collectAsStateWithLifecycle()
    var suppressRecordingRecovery by remember { mutableStateOf(false) }
    val accountId = when (val session = authState.session) {
        is SessionState.SignedIn -> session.accountId
        is SessionState.Refreshing -> session.accountId
        else -> null
    }
    val cycleViewModel:CycleAwareViewModel=hiltViewModel()
    val cycleState by cycleViewModel.state.collectAsStateWithLifecycle()
    val healthViewModel:HealthIntegrationViewModel=hiltViewModel()
    val healthPermissions by healthViewModel.permissions.collectAsStateWithLifecycle()
    val integrationViewModel: P0IntegrationViewModel = hiltViewModel()
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
    var pendingPushPermission by remember { mutableStateOf<Boolean?>(null) }
    var pendingReminderPermission by remember { mutableStateOf<Boolean?>(null) }
    var pushPermissionGranted by remember {
        mutableStateOf(
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED,
        )
    }
    val pushPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        pushPermissionGranted = granted
        notificationPermissionRequested = true
        notificationPermissionPreferences.edit().putBoolean("requested", true).apply()
        pendingPushPermission?.let { integrationViewModel.setPushEnabled(granted && it) }
        pendingPushPermission = null
        pendingReminderPermission?.let { reminderViewModel.setEnabled(granted && it) }
        pendingReminderPermission = null
        integrationViewModel.trackPushPermissionResult(granted)
        reminderViewModel.trackPermissionResult(granted)
    }
    fun requestNotificationPermission(forPush: Boolean, forReminder: Boolean) {
        val permission = android.Manifest.permission.POST_NOTIFICATIONS
        val rationaleAvailable = context.findActivity()?.shouldShowRequestPermissionRationale(permission) == true
        if (notificationPermissionRequested && !rationaleAvailable) {
            context.startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return
        }
        notificationPermissionRequested = true
        notificationPermissionPreferences.edit().putBoolean("requested", true).apply()
        pendingPushPermission = forPush.takeIf { it }
        pendingReminderPermission = forReminder.takeIf { it }
        pushPermissionLauncher.launch(permission)
    }
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, context) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                pushPermissionGranted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                    context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
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
    val trustedContacts by cheerPickerViewModel.trustedContacts.collectAsStateWithLifecycle()
    val sharesWithTrustedContactsByDefault by cheerPickerViewModel.sharesWithTrustedContactsByDefault.collectAsStateWithLifecycle()
    val selectedCheerIds by cheerPickerViewModel.selectedRecipientIds.collectAsStateWithLifecycle()
    val selectedCheerIdSet = selectedCheerIds.toSet()
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
    val stopActivityLiveMap: () -> Unit = {
        recordingSafetyViewModel.coordinator.group.value?.let { run ->
            scope.launch {
                recordingSafetyViewModel.coordinator.leaveGroupRun(run.id, finished = false)
                    .onFailure { snackbar.showSnackbar(resources.getString(R.string.auth_generic_error)) }
            }
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
                requestNotificationPermission(forPush = false, forReminder = reminderEnabled)
            }
        }
    }
    LaunchedEffect(accountId) { cheerPickerViewModel.onAccountActivated(accountId) }
    LaunchedEffect(integration.connections) { cheerPickerViewModel.onConnectionsUpdated(integration.connections) }
    LaunchedEffect(accountId) { accountId?.let(connectivityViewModel::start) }
    LaunchedEffect(connectivityState.isOffline, connectivityState.pendingSyncCount > 0) {
        if (!connectivityState.isOffline && connectivityState.pendingSyncCount > 0) {
            snackbar.showSnackbar(resources.getString(R.string.connectivity_pending))
        }
    }
    LaunchedEffect(accountId) {
        accountId?.let { activeRecordingViewModel.recover(it, recordingLocationPermission(context)) }
    }
    LaunchedEffect(hasActiveSession, currentDestination?.route) {
        if (!hasActiveSession) suppressRecordingRecovery = false
        if (hasActiveSession && !suppressRecordingRecovery && currentDestination?.route != RECORDING_ROUTE) {
            navController.navigate(RECORDING_ROUTE) { launchSingleTop = true }
        }
    }
    LaunchedEffect(navigationUri) {
        val destination = navigationUri?.pathSegments?.firstOrNull() ?: return@LaunchedEffect
        when (destination) {
            "today" -> { reminderWorkoutId=navigationUri.getQueryParameter("workout");navController.navigate(TopLevelDestination.Today.route) }
            "assistant" -> { assistantEntryDestination = TopLevelDestination.entries.firstOrNull { it.route == currentDestination?.route }?.route ?: "me"; navController.navigate(ASSISTANT_ROUTE) }
            "inbox" -> navController.navigate(NOTIFICATIONS_ROUTE)
            "activity" -> { activityTarget=navigationUri.getQueryParameter("id");navController.navigate(ACTIVITY_HISTORY_ROUTE) }
            "connections", "event", "group", "post", "invitation" -> { socialTarget=SocialNavigationTarget(destination, navigationUri.getQueryParameter("id").orEmpty());navController.navigate(TopLevelDestination.Social.route) }
            "group" -> { safetyTarget="group" to navigationUri.getQueryParameter("id").orEmpty();navController.navigate(SAFETY_ROUTE) }
            "live" -> { safetyTarget="live" to navigationUri.getQueryParameter("id").orEmpty();navController.navigate(SAFETY_ROUTE) }
            else -> navController.navigate(NOTIFICATIONS_ROUTE)
        }
        onNavigationUriConsumed()
    }
    LaunchedEffect(connectionCode) {
        val code = connectionCode ?: return@LaunchedEffect
        rewardsViewModel.claimIncomingInvitation(code)
        socialTarget = SocialNavigationTarget("connection_link", code)
        navController.navigate(TopLevelDestination.Social.route) { launchSingleTop = true }
    }
    LaunchedEffect(groupInviteToken) {
        val token = groupInviteToken ?: return@LaunchedEffect
        socialTarget = SocialNavigationTarget("group_invite", token)
        navController.navigate(TopLevelDestination.Social.route) { launchSingleTop = true }
        onGroupInviteConsumed()
    }

    Scaffold(
        containerColor = Color.Transparent,
        contentWindowInsets = WindowInsets.safeDrawing,
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            val primaryDestination = TopLevelDestination.entries.firstOrNull { it.route == currentDestination?.route }
            if (primaryDestination != null) {
                val lifecycleOwner = LocalLifecycleOwner.current
                val lifecycleState by lifecycleOwner.lifecycle.currentStateFlow.collectAsStateWithLifecycle(
                    minActiveState = Lifecycle.State.CREATED,
                )
                val launcherScale = remember { Animatable(1f) }
                val launcherRotation = remember { Animatable(0f) }
                val launcherShimmer = remember { Animatable(0f) }
                val launcherRingScale = remember { Animatable(0.72f) }
                val launcherRingOpacity = remember { Animatable(0f) }
                LaunchedEffect(primaryDestination) {
                    if (!trackedAssistantExposure) {
                        integrationViewModel.trackAssistantLauncherEligibleExposure(primaryDestination.route)
                        trackedAssistantExposure = true
                    }
                    if (!trackedAssistantAnimation) {
                        delay(500)
                        integrationViewModel.trackAssistantLauncherAnimationShown(primaryDestination.route)
                        trackedAssistantAnimation = true
                    }
                }
                LaunchedEffect(primaryDestination, lifecycleState) {
                    if (!lifecycleState.isAtLeast(Lifecycle.State.RESUMED)) {
                        launcherScale.snapTo(1f)
                        launcherRotation.snapTo(0f)
                        launcherShimmer.snapTo(0f)
                        launcherRingScale.snapTo(0.72f)
                        launcherRingOpacity.snapTo(0f)
                        return@LaunchedEffect
                    }

                    delay(500)
                    while (true) {
                        coroutineScope {
                            launch { launcherScale.animateTo(1.17f, tween(320, easing = LinearOutSlowInEasing)) }
                            launch { launcherRotation.animateTo(-10f, tween(320, easing = LinearOutSlowInEasing)) }
                            launch { launcherShimmer.animateTo(0.9f, tween(320, easing = LinearOutSlowInEasing)) }
                            launch { launcherRingScale.animateTo(0.94f, tween(320, easing = LinearOutSlowInEasing)) }
                            launch { launcherRingOpacity.animateTo(0.82f, tween(320, easing = LinearOutSlowInEasing)) }
                        }

                        val returnSpring = spring<Float>(dampingRatio = 0.48f, stiffness = Spring.StiffnessMedium)
                        coroutineScope {
                            launch { launcherScale.animateTo(1f, returnSpring) }
                            launch { launcherRotation.animateTo(0f, returnSpring) }
                            launch { launcherShimmer.animateTo(0f, returnSpring) }
                            launch { launcherRingScale.animateTo(1.55f, returnSpring) }
                            launch { launcherRingOpacity.animateTo(0f, returnSpring) }
                        }

                        launcherRingScale.snapTo(0.72f)
                        delay(2_800)
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
                    Box(Modifier.size(56.dp), contentAlignment = Alignment.Center) {
                        Canvas(
                            Modifier
                                .fillMaxSize()
                                .graphicsLayer {
                                    scaleX = launcherRingScale.value
                                    scaleY = launcherRingScale.value
                                    alpha = launcherRingOpacity.value
                                },
                        ) {
                            drawCircle(
                                color = Color.White,
                                radius = size.minDimension / 2f,
                                style = Stroke(width = 2.dp.toPx()),
                            )
                        }
                        PlainstrideFloatingAction(
                            modifier = Modifier.graphicsLayer {
                                scaleX = launcherScale.value
                                scaleY = launcherScale.value
                            },
                            style = PlainstrideFloatingActionStyle.Accent,
                            actionSize = 56.dp,
                            onClick = {
                                assistantEntryDestination = primaryDestination.route
                                integrationViewModel.trackAssistantOpened(primaryDestination.route)
                                navController.navigate(ASSISTANT_ROUTE) { launchSingleTop = true }
                            },
                        ) {
                            Box(Modifier.size(56.dp), contentAlignment = Alignment.Center) {
                                Image(
                                    painter = painterResource(R.drawable.plainstride_fox_assistant_head),
                                    contentDescription = stringResource(R.string.tab_assistant),
                                    modifier = Modifier.size(50.dp).graphicsLayer { rotationZ = launcherRotation.value },
                                )
                                Icon(
                                    Icons.Default.AutoAwesome,
                                    null,
                                    Modifier
                                        .align(Alignment.TopEnd)
                                        .offset(x = (-4).dp, y = 4.dp)
                                        .size(13.dp)
                                        .blur(0.8.dp)
                                        .graphicsLayer {
                                            scaleX = 1.12f
                                            scaleY = 1.12f
                                            alpha = launcherShimmer.value
                                        },
                                )
                            }
                        }
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
                                        navController.navigate(destination.route) {
                                            popUpTo(TopLevelDestination.Today.route) { saveState = true }
                                            launchSingleTop = true
                                            restoreState = true
                                        }
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
            bottom = if (TopLevelDestination.entries.any { it.route == currentDestination?.route }) {
                WindowInsets.safeDrawing.asPaddingValues().calculateBottomPadding()
            } else {
                contentPadding.calculateBottomPadding()
            },
        )
        Column(Modifier.fillMaxSize().padding(contentInsets).consumeWindowInsets(contentInsets)) {
        if (currentDestination?.route != RECORDING_ROUTE && connectivityState.isOffline) {
            ConnectivityBanner(
                connectivityState,
                Modifier.align(Alignment.CenterHorizontally).padding(top = 8.dp),
            )
        }
        NavHost(
            navController = navController,
            startDestination = TopLevelDestination.Today.route,
            modifier = Modifier.fillMaxWidth().weight(1f),
        ) {
            TopLevelDestination.entries.forEach { destination ->
                composable(destination.route) {
                    if (destination == TopLevelDestination.Today) {
                        val todayViewModel: TodayViewModel = hiltViewModel()
                        TodayRoute(
                            accountId = requireNotNull(accountId),
                            localeTag = resources.configuration.locales[0].toLanguageTag(),
                            viewModel = todayViewModel,
                            activeSession = hasActiveSession,
                            completedToday = integration.completedToday,
                            onStartWorkout = { intent, options ->
                                recordingLaunch = intent.toRecordingLaunch().copy(gearId = selectedTodayShoeIdForLaunch,privateTrainingSignal=cycleState.currentSignal.takeIf{cycleState.enabled&&it!=CycleTrainingSignal.NO_ADJUSTMENT}?.wireValue,startImmediately=true,indoor=options.indoor,voiceGuideEnabled=options.voiceGuideEnabled,companionType=options.companionType).withTodayRoute(todaySelectedRoute, todayRouteReversed)
                                navController.navigate(RECORDING_ROUTE) { launchSingleTop = true }
                            },
                            onStartFreestyle = { options ->
                                recordingLaunch = RecordingLaunchConfiguration(
                                    gearId = selectedTodayShoeIdForLaunch,
                                    entrySource = "today_freestyle",
                                    startImmediately = true,
                                    indoor = options.indoor,
                                    voiceGuideEnabled = options.voiceGuideEnabled,
                                    companionType = options.companionType,
                                ).withTodayRoute(todaySelectedRoute, todayRouteReversed)
                                navController.navigate(RECORDING_ROUTE) { launchSingleTop = true }
                            },
                            onReturnToSession = { navController.navigate(RECORDING_ROUTE) { launchSingleTop = true } },
                            onSetUpPlan = { planBuilderSource = PlanBuilderSource.PlannedButton },
                            onBuildPlan = { planBuilderSource = PlanBuilderSource.AllPlans },
                            onStartManual = { setup ->
                                recordingLaunch = setup.toRecordingLaunch(selectedTodayShoeIdForLaunch).withTodayRoute(todaySelectedRoute, todayRouteReversed)
                                navController.navigate(RECORDING_ROUTE) { launchSingleTop = true }
                            },
                            shoes = activeShoes.map { com.plainstride.outbound.feature.today.TodayShoeOption(it.id.toString(), it.displayName) },
                            selectedShoeId = selectedTodayShoeIdForLaunch,
                            onSelectShoe = { shoe -> selectedTodayShoeId = shoe.id; integrationViewModel.trackShoeSelected("active_shoe") },
                            onAddShoe = { integrationViewModel.trackShoeSelected("add_new"); addShoeSheetVisible = true },
                            onOpenLiveTrack = { cheerPickerVisible = true },
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
                            inboxCount = NotificationPresentationPolicy.actionableAttentionCount(integration.notifications),
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
                            inboxCount = NotificationPresentationPolicy.actionableAttentionCount(integration.notifications),
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
                            localWeeklyMinutes = integration.progress.stats.currentWeek.durationSeconds / 60,
                            localWeeklyDistanceMeters = integration.progress.stats.currentWeek.distanceMeters,
                            localWeeklyActivityCount = integration.progress.stats.currentWeek.activityCount,
                            onMyQrCode = { navController.navigate(MY_QR_ROUTE) { launchSingleTop = true } },
                            onConnections = {
                                socialTarget = SocialNavigationTarget("connections", entrySource = "me_preview")
                                navController.navigate(TopLevelDestination.Social.route) { launchSingleTop = true }
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
                                            activityTarget = selectedId
                                            navController.navigate(ACTIVITY_HISTORY_ROUTE) { launchSingleTop = true }
                                        },
                                        onOpenAll = {
                                            activityTarget = null
                                            navController.navigate(ACTIVITY_HISTORY_ROUTE) { launchSingleTop = true }
                                        },
                                        onImportHealth = { navController.navigate(HEALTH_ROUTE) { launchSingleTop = true } },
                                        onMessage = { message -> snackbar.showSnackbar(resources.getString(activityMessageResource(message))) },
                                    )
                                }
                            },
                            settingsContent = {
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
                                    supportingContent = { Text(stringResource(R.string.push_notifications_body)) },
                                    trailingContent = {
                                        Switch(
                                            checked = integration.pushEnabled && pushPermissionGranted,
                                            onCheckedChange = { enabled ->
                                                if (!enabled) {
                                                    integrationViewModel.setPushEnabled(false)
                                                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !pushPermissionGranted) {
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
                        SocialRoute(accountId, resources.configuration.locales[0].toLanguageTag(),socialTarget?.type,socialTarget?.id,targetEntrySource=socialTarget?.entrySource ?: "deep_link",inboxCount=NotificationPresentationPolicy.actionableAttentionCount(integration.notifications),unitSystem=measurementUnitSystem,onConditions={navController.navigate(TopLevelDestination.Today.route)},onCommunity={navController.navigate(COMMUNITY_ROUTES_ROUTE)},onNotifications={navController.navigate(NOTIFICATIONS_ROUTE) { launchSingleTop = true }},onActivity={id->activityTarget=id;navController.navigate(ACTIVITY_HISTORY_ROUTE)},onMyInvite={navController.navigate(MY_QR_ROUTE){launchSingleTop=true}},onTargetConsumed={socialTarget=null},onConnectionLinkConsumed={socialTarget=null;onConnectionCodeConsumed()},onGroupInviteConsumed={socialTarget=null},onRoutesTabSelected={if(integration.routeScope!=RouteScope.DISCOVERY)integrationViewModel.scope(RouteScope.DISCOVERY)},onOpenSharedActivity={id->navController.navigate("$SOCIAL_ACTIVITY_DETAIL_ROUTE/$id")},onOpenSharedEvent={id,source->navController.navigate("$SOCIAL_ACTIVITY_EVENT_ROUTE/$id?source=$source")},onOpenSharedProfile={person->sharedSocialProfile=person;navController.navigate("$SOCIAL_PROFILE_ROUTE/${person.id}")},groupRun=sharedLiveGroupRun?.toSharedLiveRun(),groupRunJoining=groupRunJoining,onToggleActivityLiveMap=toggleActivityLiveMap,onStartGroupActivity={event->recordingLaunch=RecordingLaunchConfiguration(activityKind=when(event.activityType?.lowercase()){"walking"->ActivityKind.WALKING;"hiking"->ActivityKind.HIKING;"cycling"->ActivityKind.CYCLING;"swimming"->ActivityKind.SWIMMING;else->ActivityKind.RUNNING},title=event.name,entrySource="group_event",activityEventId=event.id,startImmediately=false);navController.navigate(RECORDING_ROUTE){launchSingleTop=true}},communityRoutesContent={ routeImportRequest -> CommunityRouteScreen(integration.routes,integration.routeScope,integrationViewModel::scope,integrationViewModel::refreshRoutes,integrationViewModel::search,{launch->recordingLaunch=launch;navController.navigate(RECORDING_ROUTE)},integrationViewModel::bookmark,integrationViewModel::trackRouteImport,bottomContentPadding=PrimaryBottomToolbarClearance,routeDetail=integration.selectedCommunityRoute,routeDetailLoading=integration.communityRouteLoading,onLoadDetail=integrationViewModel::loadCommunityRoute,onRemovePublished=integrationViewModel::removePublishedRoute,onClearDetail=integrationViewModel::clearCommunityRoute,unitSystem=measurementUnitSystem,onImportedDelete=integrationViewModel::trackImportedRouteDeleted,importRequest=routeImportRequest,searchQuery=integration.routeQuery)})
                    } else {
                        FoundationScreen(destination, authState, authViewModel)
                    }
                }
            }
            composable("$SOCIAL_ACTIVITY_DETAIL_ROUTE/{postId}") { entry ->
                val postId = entry.arguments?.getString("postId").orEmpty()
                val socialEntry = remember(navController) { navController.getBackStackEntry(TopLevelDestination.Social.route) }
                val socialViewModel: SocialViewModel = hiltViewModel(socialEntry)
                val activityViewModel: ActivityViewModel = hiltViewModel(socialEntry)
                SocialActivityDetailDestination(
                    postId = postId,
                    unitSystem = measurementUnitSystem,
                    viewModel = socialViewModel,
                    activityViewModel = activityViewModel,
                    onOpenSharedProfile = { person -> sharedSocialProfile = person; socialViewModel.trackProfileOpened(); navController.navigate("$SOCIAL_PROFILE_ROUTE/${person.id}") },
                    onBack = { socialViewModel.closeActivityDetail(); navController.popBackStack() },
                )
            }
            composable("$SOCIAL_ACTIVITY_EVENT_ROUTE/{eventId}?source={source}") { entry ->
                val eventId = entry.arguments?.getString("eventId").orEmpty()
                val source = entry.arguments?.getString("source") ?: "social_upcoming"
                val socialEntry = remember(navController) { navController.getBackStackEntry(TopLevelDestination.Social.route) }
                val socialViewModel: SocialViewModel = hiltViewModel(socialEntry)
                SocialActivityEventDestination(
                    eventId = eventId,
                    entrySource = source,
                    viewModel = socialViewModel,
                    onBack = { navController.popBackStack() },
                )
            }
            composable("$SOCIAL_PROFILE_ROUTE/{personId}") { entry ->
                val personId = entry.arguments?.getString("personId").orEmpty()
                DisposableEffect(personId) { onDispose { if (sharedSocialProfile?.id == personId) sharedSocialProfile = null } }
                val socialEntry = remember(navController) { navController.getBackStackEntry(TopLevelDestination.Social.route) }
                val socialViewModel: SocialViewModel = hiltViewModel(socialEntry)
                SocialProfileDestination(
                    person = sharedSocialProfile?.takeIf { it.id == personId },
                    viewModel = socialViewModel,
                    onOpenSharedActivity = { post ->
                        socialViewModel.openActivityDetail(post)
                        navController.navigate("$SOCIAL_ACTIVITY_DETAIL_ROUTE/${post.id}")
                    },
                    onBack = { sharedSocialProfile = null; navController.popBackStack() },
                )
            }
            composable(ASSISTANT_ROUTE) {
                AssistantRoute(
                    requireNotNull(accountId),
                    screen = assistantEntryDestination,
                    onClose = { navController.popBackStack() },
                    onNavigate = { route ->
                        when (route) {
                            "today", "social", "me" -> navController.navigate(route) {
                                popUpTo(TopLevelDestination.Today.route) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                            "settings" -> {
                                settingsRequest += 1
                                navController.navigate(TopLevelDestination.Me.route) {
                                    popUpTo(TopLevelDestination.Today.route) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            }
                            MUSIC_ROUTE, ACTIVITY_HISTORY_ROUTE, HEALTH_ROUTE -> navController.navigate(route) { launchSingleTop = true }
                            else -> navController.navigate("me") { launchSingleTop = true }
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
            composable(RECORDING_ROUTE) {
                RecordingRoute(
                    accountId = requireNotNull(accountId) { "Authenticated session is missing its account identifier." },
                    launch = recordingLaunch,
                    onPrepareActivityStart = cheerPickerViewModel::applyTrustedContactDefault,
                    isOffline = connectivityState.isOffline,
                    unitSystem = measurementUnitSystem,
                    weightKilograms = integration.weightKilograms,
                    onSavedSideEffects = { review -> suppressRecordingRecovery = true; healthViewModel.export(review); integrationViewModel.completePlannedWorkout(recordingLaunch, review) },
                    onOpenAssistant = {
                        assistantEntryDestination = "recording"
                        integrationViewModel.trackAssistantOpened("today", "live_session")
                        navController.navigate(ASSISTANT_ROUTE) { launchSingleTop = true }
                    },
                    onCheerMeOn = { cheerPickerVisible = true },
                    cheerSelectedName = integration.connections.firstOrNull { it.id in selectedCheerIdSet }?.displayName,
                    cheerSelectedCount = selectedCheerIdSet.size,
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
                        navController.navigate(TopLevelDestination.Me.route) {
                            popUpTo(TopLevelDestination.Today.route) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                    onExit = {
                        suppressRecordingRecovery = true
                        navController.navigate(TopLevelDestination.Today.route) {
                            popUpTo(RECORDING_ROUTE) { inclusive = true }
                        }
                    },
                    groupRun=sharedLiveGroupRun?.toSharedLiveRun(),
                    groupRunJoining=groupRunJoining,
                    onToggleActivityLiveMap={recordingLaunch.activityEventId?.let(toggleActivityLiveMap)},
                    onStopActivityLiveMap=stopActivityLiveMap,
                    sessionEffect = { snapshot ->
                        LiveCoachRecordingEffect(recordingLaunch, measurementUnitSystem)
                        RecordingSafetyEffect(snapshot, recordingLaunch.activityEventId)
                    },
                    saveActivityPhotosToAlbum = settingsState.preferences.saveActivityPhotosToAlbum,
                    onPhotoAlbumPermissionDenied = {
                        settingsViewModel.setSaveActivityPhotosToAlbum(false, showMessage = false)
                    },
                )
            }
            composable(ACTIVITY_HISTORY_ROUTE) {
                ActivityHistoryRoute(
                    accountId = requireNotNull(accountId) { "Authenticated session is missing its account identifier." },
                    unitSystem = measurementUnitSystem,
                    weightKilograms = integration.weightKilograms,
                    initialActivityId = activityTarget,
                    onBack = { navController.popBackStack() },
                    onMessage = { message -> snackbar.showSnackbar(resources.getString(activityMessageResource(message))) },
                    onPublishRoute = integrationViewModel::publishSavedActivityRoute,
                )
            }
            composable(MUSIC_ROUTE) { MusicRoute(onClose = { navController.popBackStack() }) }
            composable(PROGRESS_ROUTE) {
                val progress = integration.progress.copy(
                    unitSystem = if (measurementUnitSystem == MeasurementUnitSystem.metric) ProgressUnitSystem.METRIC else ProgressUnitSystem.IMPERIAL,
                )
                ProgressRoute(progress, onAnalyticsEvent = integrationViewModel::trackProgressEvent)
            }
            dialog(COMMUNITY_ROUTES_ROUTE, dialogProperties = DialogProperties(usePlatformDefaultWidth = false)) {
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
                                CommunityRouteScreen(integration.routes, integration.routeScope, integrationViewModel::scope, integrationViewModel::refreshRoutes, integrationViewModel::search, { launch -> recordingLaunch=launch;navController.popBackStack();navController.navigate(RECORDING_ROUTE) }, integrationViewModel::bookmark,integrationViewModel::trackRouteImport,routeDetail=integration.selectedCommunityRoute,routeDetailLoading=integration.communityRouteLoading,onLoadDetail=integrationViewModel::loadCommunityRoute,onRemovePublished=integrationViewModel::removePublishedRoute,onClearDetail=integrationViewModel::clearCommunityRoute,unitSystem=measurementUnitSystem,searchQuery=integration.routeQuery,selectionMode=selectingRouteForToday,initialSelection=todaySelectedRoute,initialSelectionReverse=todayRouteReversed,onSelectRoute={route,reverse->val removedRoute=todaySelectedRoute.takeIf{route==null};todaySelectedRoute=route;todayRouteReversed=reverse;selectingRouteForToday=false;integrationViewModel.clearCommunityRoute();navController.popBackStack();if(removedRoute!=null)integrationViewModel.trackTodayRouteRemoved(removedRoute) else route?.let{integrationViewModel.trackTodayRouteSelected(it)}},onDismissSelection={selectingRouteForToday=false;integrationViewModel.clearCommunityRoute();navController.popBackStack()})
                            }
                        }
                    }
                }
            }
            composable(SAFETY_ROUTE) { SafetyRoute(safetyTarget?.second, safetyTarget?.first ?: "group", integration.connections, accountId, measurementUnitSystem) }
            composable(TRUSTED_CONTACTS_ROUTE) {
                TrustedContactsSettingsScreen(
                    connections = integration.connections,
                    trustedContacts = trustedContacts,
                    sharesWithTrustedContactsByDefault = sharesWithTrustedContactsByDefault,
                    onTrustedChange = cheerPickerViewModel::setTrusted,
                    onDefaultSharingChange = cheerPickerViewModel::setSharesWithTrustedContactsByDefault,
                    onBack = { navController.popBackStack() },
                    onOpenConnections = {
                        socialTarget = SocialNavigationTarget("connections", entrySource = "trusted_contacts")
                        navController.navigate(TopLevelDestination.Social.route) { launchSingleTop = true }
                    },
                )
            }
            composable(HEALTH_ROUTE) { HealthDestination(healthPermissions, healthViewModel::refresh) { navController.popBackStack() } }
            composable(NOTIFICATIONS_ROUTE, deepLinks = listOf(navDeepLink { uriPattern = "plainstride://notification/{destination}?id={id}&notification={notification}" })) {
                LaunchedEffect(Unit) { integrationViewModel.openInbox() }
                NotificationInbox(integration.notifications) { item ->
                    integrationViewModel.openNotification(item)
                    when(val destination = item.presentation.destination){ NotificationDestination.Connections -> { socialTarget=SocialNavigationTarget("connections", entrySource = "notification");navController.navigate(TopLevelDestination.Social.route) };is NotificationDestination.Activity -> { activityTarget=destination.id;navController.navigate(ACTIVITY_HISTORY_ROUTE) };is NotificationDestination.Post -> {socialTarget=SocialNavigationTarget("post", destination.id);navController.navigate(TopLevelDestination.Social.route)};is NotificationDestination.Event -> {socialTarget=SocialNavigationTarget("event", destination.id);navController.navigate(TopLevelDestination.Social.route)};is NotificationDestination.Invitation -> {socialTarget=SocialNavigationTarget("invitation", destination.id);navController.navigate(TopLevelDestination.Social.route)};is NotificationDestination.Group -> {socialTarget=SocialNavigationTarget("group", destination.id);navController.navigate(TopLevelDestination.Social.route)};is NotificationDestination.GroupRun -> {safetyTarget="group" to destination.id;navController.navigate(SAFETY_ROUTE)};is NotificationDestination.Live -> {safetyTarget="live" to destination.id;navController.navigate(SAFETY_ROUTE)};NotificationDestination.Inbox -> {notificationDetailID=item.primary.id;navController.navigate(NOTIFICATION_DETAIL_ROUTE)} }
                }
            }
            composable(NOTIFICATION_DETAIL_ROUTE) {
                NotificationDetail(integration.notifications.firstOrNull { it.id == notificationDetailID })
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
                    safetyTarget = null
                    navController.navigate(TRUSTED_CONTACTS_ROUTE)
                },
                onDone = { ids ->
                    cheerPickerViewModel.configureCheerRecipients(ids)
                    cheerPickerVisible = false
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
private const val ASSISTANT_ROUTE = "assistant"
private const val MY_QR_ROUTE = "my_qr"
private const val MUSIC_ROUTE = "music"
private const val ACTIVITY_HISTORY_ROUTE = "activity_history"
private const val SOCIAL_ACTIVITY_DETAIL_ROUTE = "social_activity_detail"
private const val SOCIAL_ACTIVITY_EVENT_ROUTE = "social_activity_event"
private const val SOCIAL_PROFILE_ROUTE = "social_profile"
private const val PROGRESS_ROUTE = "progress"
private const val COMMUNITY_ROUTES_ROUTE = "community_routes"
private const val SAFETY_ROUTE = "safety"
private const val TRUSTED_CONTACTS_ROUTE = "trusted_contacts"
private const val HEALTH_ROUTE = "health"
private const val NOTIFICATIONS_ROUTE = "notifications"
private const val NOTIFICATION_DETAIL_ROUTE = "notification_detail"
private const val REWARDS_ROUTE = "rewards"
private const val REWARD_REDEMPTION_ROUTE = "reward-redemption"
private const val INVITATION_CODE_ROUTE = "invitation-code"
private const val PLUS_ROUTE = "plus"

private fun recordingLocationPermission(context: android.content.Context): LocationPermissionState = when {
    context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED -> LocationPermissionState.PRECISE
    context.checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED -> LocationPermissionState.APPROXIMATE
    else -> LocationPermissionState.DENIED
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

private fun WorkoutLaunchIntent.toRecordingLaunch(): RecordingLaunchConfiguration {
    val goal = when {
        targetCalories != null -> RecordingGoal(RecordingGoalType.CALORIES, targetCalories = targetCalories)
        distanceMeters != null -> RecordingGoal(RecordingGoalType.DISTANCE, targetDistanceMeters = distanceMeters)
        steps.isNotEmpty() -> RecordingGoal(RecordingGoalType.WORKOUT, targetDurationSeconds = durationSeconds.toLong())
        else -> RecordingGoal(RecordingGoalType.TIME, targetDurationSeconds = durationSeconds.toLong())
    }
    return RecordingLaunchConfiguration(
        activityKind = when (modality) {
            Modality.walk -> ActivityKind.WALKING
            Modality.bike -> ActivityKind.CYCLING
            Modality.swim -> ActivityKind.SWIMMING
            else -> ActivityKind.RUNNING
        },
        title = title,
        goal = goal,
        workoutSteps = steps.map { StructuredWorkoutStep(it) },
        entrySource = source,
        suggestionId = suggestionId,
        plannedWorkoutId = plannedWorkoutId,
        workoutDetail = effortLabel,
        workoutGuideline = listOf(stimulus.name, intensityModel).filter(String::isNotBlank).joinToString(" · "),
    )
}

private fun TodayManualLaunch.toRecordingLaunch(defaultGearId: String?): RecordingLaunchConfiguration {
    val recordingGoal = when (goal) {
        TodayGoalChoice.DISTANCE -> RecordingGoal(RecordingGoalType.DISTANCE, targetDistanceMeters = distanceMeters)
        TodayGoalChoice.TIME -> RecordingGoal(RecordingGoalType.TIME, targetDurationSeconds = durationSeconds)
        TodayGoalChoice.CALORIES -> RecordingGoal(RecordingGoalType.CALORIES, targetCalories = calories)
        TodayGoalChoice.CURATED -> RecordingGoal(RecordingGoalType.WORKOUT, targetDurationSeconds = curatedWorkout?.targetDurationSeconds?.toLong() ?: durationSeconds)
        TodayGoalChoice.FREE -> RecordingGoal()
    }
    return RecordingLaunchConfiguration(
        activityKind = when (activity) {
            TodayActivityChoice.WALK -> ActivityKind.WALKING
            TodayActivityChoice.HIKE -> ActivityKind.HIKING
            TodayActivityChoice.BIKE -> ActivityKind.CYCLING
            else -> ActivityKind.RUNNING
        },
        title = curatedWorkout?.title,
        goal = recordingGoal,
        workoutSteps = curatedWorkout?.steps?.map {
            StructuredWorkoutStep(
                title = it.label,
                detail = it.detail,
                durationSeconds = it.durationSeconds,
                phase = it.coachingTarget?.phase,
                targetPaceSecondsPerKilometer = it.coachingTarget?.pace?.targetSecondsPerKilometer,
                fasterToleranceSeconds = it.coachingTarget?.pace?.fasterToleranceSeconds,
                slowerToleranceSeconds = it.coachingTarget?.pace?.slowerToleranceSeconds,
                recognizesTargetLock = it.coachingTarget?.recognizesTargetLock == true,
            )
        }.orEmpty(),
        entrySource = "today_manual",
        standaloneWorkoutId = curatedWorkout?.id,
        standaloneWorkoutCatalogVersion = curatedWorkoutCatalogVersion,
        autoStopAtGoal = autoStopAtGoal && goal in setOf(TodayGoalChoice.DISTANCE, TodayGoalChoice.TIME, TodayGoalChoice.CALORIES),
        workoutPhase = curatedWorkout?.coachingTarget?.phase,
        workoutTargetPaceSecondsPerKilometer = curatedWorkout?.coachingTarget?.pace?.targetSecondsPerKilometer,
        workoutFasterToleranceSeconds = curatedWorkout?.coachingTarget?.pace?.fasterToleranceSeconds,
        workoutSlowerToleranceSeconds = curatedWorkout?.coachingTarget?.pace?.slowerToleranceSeconds,
        workoutRecognizesTargetLock = curatedWorkout?.coachingTarget?.recognizesTargetLock == true,
        gearId = defaultGearId,
        indoor = indoor,
        voiceGuideEnabled = voiceGuideEnabled,
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
            WelcomeOrbit(Modifier.fillMaxWidth())
            Text(stringResource(R.string.auth_companion_eyebrow), Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.labelMedium, textAlign = TextAlign.Center)
            Text(stringResource(R.string.auth_companion_headline), Modifier.fillMaxWidth().padding(top = 10.dp), style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center)
            Spacer(Modifier.weight(0.65f))
            OutlinedButton(
                onClick = { viewModel.signIn(context) },
                enabled = state.operation == null,
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(14.dp),
            ) { Text(stringResource(if (state.operation == null) R.string.continue_with_google else R.string.signing_in)) }
            Text(stringResource(R.string.auth_google_explanation), Modifier.fillMaxWidth().padding(top = 8.dp), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall, textAlign = TextAlign.Center)
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
            Text(stringResource(R.string.auth_terms_notice), style = MaterialTheme.typography.bodySmall, modifier = Modifier.fillMaxWidth().padding(top = 8.dp), textAlign = TextAlign.Center)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                TextButton(onClick = { viewModel.trackLegal("terms"); uriHandler.openUri("https://plainstride.ai/terms") }) { Text(stringResource(R.string.auth_terms_link)) }
                TextButton(onClick = { viewModel.trackLegal("privacy"); uriHandler.openUri("https://plainstride.ai/privacy") }) { Text(stringResource(R.string.auth_privacy_link)) }
            }
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
    TodayMessage.CouldNotAdjust -> com.plainstride.outbound.feature.today.R.string.today_adjust_failed
    TodayMessage.AdjustmentApplied -> com.plainstride.outbound.feature.today.R.string.today_adjust_applied
    TodayMessage.OriginalKept -> com.plainstride.outbound.feature.today.R.string.today_original_kept
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
