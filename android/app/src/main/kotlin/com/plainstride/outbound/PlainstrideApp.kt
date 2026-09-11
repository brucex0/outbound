package com.plainstride.outbound

import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.material3.Surface
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Today
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Groups2
import android.content.pm.PackageManager
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navDeepLink
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.plainstride.outbound.auth.AuthMessage
import com.plainstride.outbound.auth.AuthOperation
import com.plainstride.outbound.auth.AuthUiState
import com.plainstride.outbound.auth.AuthViewModel
import com.plainstride.outbound.core.auth.SessionState
import com.plainstride.outbound.core.designsystem.PlainstrideFloatingAction
import com.plainstride.outbound.feature.activity.ActivityHistoryRoute
import com.plainstride.outbound.feature.activity.ActivityMessage
import com.plainstride.outbound.feature.activity.RecentActivitiesRoute
import com.plainstride.outbound.reminders.ReminderSettingsRow
import com.plainstride.outbound.feature.onboarding.OnboardingEffect
import com.plainstride.outbound.feature.onboarding.OnboardingRoute
import com.plainstride.outbound.feature.today.TodayMessage
import com.plainstride.outbound.feature.today.TodayRoute
import com.plainstride.outbound.feature.today.TodayViewModel
import com.plainstride.outbound.feature.today.R as TodayR
import com.plainstride.outbound.feature.settings.MeRoute
import com.plainstride.outbound.feature.settings.SettingsMessage
import com.plainstride.outbound.feature.settings.SettingsViewModel
import com.plainstride.outbound.feature.settings.MeConnection
import com.plainstride.outbound.feature.settings.MeInsight
import com.plainstride.outbound.feature.settings.MeMilestone
import com.plainstride.outbound.feature.settings.SettingsGroupTitle
import com.plainstride.outbound.feature.settings.R as SettingsR
import com.plainstride.outbound.feature.recording.ActivityKind
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
import com.plainstride.outbound.feature.social.SocialRoute
import com.plainstride.outbound.feature.today.WorkoutLaunchIntent
import com.plainstride.outbound.feature.today.TodayManualLaunch
import com.plainstride.outbound.feature.today.TodayActivityChoice
import com.plainstride.outbound.feature.today.TodayGoalChoice
import com.plainstride.outbound.core.model.Modality
import com.plainstride.outbound.feature.community.CommunityRouteScreen
import com.plainstride.outbound.feature.community.guidancePoints
import com.plainstride.outbound.feature.health.*
import com.plainstride.outbound.feature.progress.ProgressRoute
import com.plainstride.outbound.feature.safety.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.rememberLauncherForActivityResult
import android.content.Intent
import android.provider.Settings
import kotlinx.coroutines.launch
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
) {
    val settingsState by settingsViewModel.state.collectAsStateWithLifecycle()
    var onboardingResolved by remember { mutableStateOf(false) }
    var forceOnboardingReplay by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val resources = LocalResources.current
    val scope = rememberCoroutineScope()
    val signedInAccountId = when (val session = authState.session) { is SessionState.SignedIn -> session.accountId; is SessionState.Refreshing -> session.accountId; else -> null }
    val onboardingCycleViewModel:CycleAwareViewModel=hiltViewModel()
    LaunchedEffect(signedInAccountId){signedInAccountId?.let{onboardingCycleViewModel.start(it)}}
    if (!onboardingResolved) {
        OnboardingRoute(
            onComplete = { onboardingResolved = true },
            forceReplay = forceOnboardingReplay,
            optionalPrivateSetup = { signedInAccountId?.let { CycleAwareSection(it,onboardingCycleViewModel) } },
            onMessage = { effect ->
                val message = when (effect) {
                    OnboardingEffect.IdentityUnavailable -> R.string.onboarding_identity_unavailable
                    OnboardingEffect.HealthUnavailable -> R.string.onboarding_health_unavailable
                    OnboardingEffect.SavedOffline -> R.string.onboarding_save_unavailable
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
    var socialTarget by remember { mutableStateOf<Pair<String,String>?>(null) }
    var activityTarget by remember { mutableStateOf<String?>(null) }
    var safetyTarget by remember { mutableStateOf<Pair<String,String>?>(null) }
    var reminderWorkoutId by remember { mutableStateOf<String?>(null) }
    var todayStartRequest by remember { mutableStateOf(0) }
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
    val reminderViewModel: ReminderViewModel = hiltViewModel()
    val integration by integrationViewModel.state.collectAsStateWithLifecycle()
    LaunchedEffect(accountId) { accountId?.let { integrationViewModel.start(it, resources.configuration.locales[0].toLanguageTag());cycleViewModel.start(it);healthViewModel.start(it) } }
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
            "assistant" -> navController.navigate(ASSISTANT_ROUTE)
            "inbox" -> navController.navigate(NOTIFICATIONS_ROUTE)
            "activity" -> { activityTarget=navigationUri.getQueryParameter("id");navController.navigate(ACTIVITY_HISTORY_ROUTE) }
            "connections", "event", "circle", "group", "post", "invitation" -> { socialTarget=destination to navigationUri.getQueryParameter("id").orEmpty();navController.navigate(TopLevelDestination.Social.route) }
            "live" -> { safetyTarget="live" to navigationUri.getQueryParameter("id").orEmpty();navController.navigate(SAFETY_ROUTE) }
            else -> navController.navigate(NOTIFICATIONS_ROUTE)
        }
        onNavigationUriConsumed()
    }

    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing,
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            val primaryDestination = TopLevelDestination.entries.firstOrNull { it.route == currentDestination?.route }
            if (primaryDestination != null) {
                Row(
                    Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 16.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    PlainstrideFloatingAction(onClick = {
                        integrationViewModel.trackAssistantOpened(primaryDestination.route)
                        navController.navigate(ASSISTANT_ROUTE) { launchSingleTop = true }
                    }) {
                        Icon(Icons.Default.AutoAwesome, stringResource(R.string.tab_assistant), Modifier.size(22.dp))
                    }
                    Spacer(Modifier.width(10.dp))
                    val contextualStart = primaryDestination == TopLevelDestination.Today && !hasActiveSession
                    NavigationBar(
                        modifier = Modifier.weight(1f).height(64.dp).clip(RoundedCornerShape(32.dp)),
                        containerColor = MaterialTheme.colorScheme.surface,
                        tonalElevation = 8.dp,
                    ) {
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
                                    Icon(
                                        imageVector = when {
                                            isContextualStart -> Icons.Default.PlayCircle
                                            destination == TopLevelDestination.Social -> Icons.Default.Groups
                                            destination == TopLevelDestination.Today -> Icons.Default.Today
                                            else -> Icons.Default.Person
                                        },
                                        contentDescription = stringResource(
                                            if (isContextualStart) TodayR.string.today_start else destination.label,
                                        ),
                                    )
                                },
                                label = null,
                                alwaysShowLabel = false,
                            )
                        }
                    }
                }
            }
        },
    ) { contentPadding ->
        NavHost(
            navController = navController,
            startDestination = TopLevelDestination.Today.route,
            modifier = Modifier.padding(contentPadding),
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
                                recordingLaunch = intent.toRecordingLaunch().copy(gearId = integration.defaultGearId,privateTrainingSignal=cycleState.currentSignal.takeIf{cycleState.enabled&&it!=CycleTrainingSignal.NO_ADJUSTMENT}?.wireValue,startImmediately=true,indoor=options.indoor,voiceGuideEnabled=options.voiceGuideEnabled)
                                navController.navigate(RECORDING_ROUTE) { launchSingleTop = true }
                            },
                            onStartFreestyle = {
                                recordingLaunch = RecordingLaunchConfiguration(gearId = integration.defaultGearId)
                                navController.navigate(RECORDING_ROUTE) { launchSingleTop = true }
                            },
                            onReturnToSession = { navController.navigate(RECORDING_ROUTE) { launchSingleTop = true } },
                            onSetUpPlan = { /* Plan setup is connected by the planning flow. */ },
                            onStartManual = { setup ->
                                recordingLaunch = setup.toRecordingLaunch(integration.defaultGearId)
                                navController.navigate(RECORDING_ROUTE) { launchSingleTop = true }
                            },
                            onOpenMusic = { navController.navigate(MUSIC_ROUTE) },
                            onOpenLiveTrack = { navController.navigate(SAFETY_ROUTE) },
                            onOpenShoes = { navController.navigate(PROGRESS_ROUTE) },
                            onOpenInbox = { navController.navigate(NOTIFICATIONS_ROUTE) },
                            onFindRoute = { navController.navigate(COMMUNITY_ROUTES_ROUTE) },
                            useFahrenheit = settingsState.preferences.temperature == com.plainstride.outbound.feature.settings.TemperatureUnit.Fahrenheit,
                            inboxCount = integration.notifications.count { it.readAt == null },
                            startRequest = todayStartRequest,
                            onMessage = { message ->
                                snackbar.showSnackbar(resources.getString(todayMessageResource(message)))
                            },
                            guidanceContent = { CycleTodayGuidance(cycleState,onKeep={},{ todayViewModel.state.value.primarySuggestion?.let{suggestion->cycleViewModel.requestGentler(suggestion.plannedWorkoutId?:suggestion.id)} }) },
                            initialWorkoutId = reminderWorkoutId,
                        )
                    } else if (destination == TopLevelDestination.Me) {
                        MeRoute(
                            viewModel = settingsViewModel,
                            appVersion = BuildConfig.VERSION_NAME,
                            debugToolsEnabled = BuildConfig.DEBUG,
                            onLinkGoogle = { authViewModel.linkGoogle(context) },
                            onSignOut = authViewModel::signOut,
                            onDeleteAccount = authViewModel::requestDeletion,
                            onReplayOnboarding = {
                                forceOnboardingReplay = true
                                onboardingResolved = false
                            },
                            onActivityHistory = { navController.navigate(ACTIVITY_HISTORY_ROUTE) { launchSingleTop = true } },
                            connections = integration.connections.map { MeConnection(it.id, it.displayName) },
                            insights = integration.insights.map { MeInsight(it.id, it.label, it.value, it.confidence.replaceFirstChar(Char::uppercase)) },
                            milestones = integration.recognitions.map { MeMilestone("${it.badgeId}:${it.awardedAt}", it.badgeId.replace('_', ' ').replaceFirstChar(Char::uppercase)) },
                            localWeeklyMinutes = integration.progress.stats.currentWeek.durationSeconds / 60,
                            localWeeklyDistanceMeters = integration.progress.stats.currentWeek.distanceMeters,
                            localWeeklyActivityCount = integration.progress.stats.currentWeek.activityCount,
                            onConnections = {
                                socialTarget = "connections" to ""
                                navController.navigate(TopLevelDestination.Social.route) { launchSingleTop = true }
                            },
                            onMyRoutes = {
                                integrationViewModel.scope(com.plainstride.outbound.feature.community.RouteScope.MINE)
                                navController.navigate(COMMUNITY_ROUTES_ROUTE) { launchSingleTop = true }
                            },
                            onMeDestination = settingsViewModel::trackMeDestination,
                            activityContent = {
                                accountId?.let { id -> RecentActivitiesRoute(id, { navController.navigate(ACTIVITY_HISTORY_ROUTE) { launchSingleTop = true } }) }
                            },
                            settingsContent = {
                                SettingsGroupTitle(stringResource(SettingsR.string.settings_planned_workouts))
                                ReminderSettingsRow(reminderViewModel)
                                SettingsGroupTitle(stringResource(SettingsR.string.settings_safety))
                                ListItem(headlineContent = { Text(stringResource(R.string.safety_destination)) }, supportingContent = { Text(stringResource(SettingsR.string.settings_safety_body)) }, modifier = Modifier.clickable { navController.navigate(SAFETY_ROUTE) })
                                SettingsGroupTitle(stringResource(SettingsR.string.settings_live_guidance))
                                LiveCoachSettingsSection()
                                SettingsGroupTitle(stringResource(SettingsR.string.settings_health_and_body))
                                accountId?.let { CycleAwareSection(it,cycleViewModel) }
                                SettingsGroupTitle(stringResource(SettingsR.string.settings_integrations))
                                ListItem(headlineContent = { Text(stringResource(R.string.music_settings_title)) }, supportingContent = { Text(stringResource(R.string.music_settings_body)) }, modifier = Modifier.clickable { navController.navigate(MUSIC_ROUTE) })
                                ListItem(headlineContent = { Text(stringResource(R.string.progress_destination)) }, modifier = Modifier.clickable { navController.navigate(PROGRESS_ROUTE) })
                                ListItem(headlineContent = { Text(stringResource(R.string.routes_destination)) }, modifier = Modifier.clickable { navController.navigate(COMMUNITY_ROUTES_ROUTE) })
                                ListItem(headlineContent = { Text(stringResource(R.string.health_destination)) }, modifier = Modifier.clickable { navController.navigate(HEALTH_ROUTE) })
                                ListItem(headlineContent = { Text(stringResource(R.string.notifications_destination)) }, modifier = Modifier.clickable { navController.navigate(NOTIFICATIONS_ROUTE) })
                                ListItem(headlineContent={Text(stringResource(R.string.push_notifications_setting))},supportingContent={Text(stringResource(R.string.push_notifications_body))},trailingContent={Switch(integration.pushEnabled,integrationViewModel::setPushEnabled)})
                            },
                            onMessage = { message -> snackbar.showSnackbar(resources.getString(settingsMessageResource(message))) },
                        )
                    } else if (destination == TopLevelDestination.Social && accountId != null) {
                        SocialRoute(accountId, resources.configuration.locales[0].toLanguageTag(),socialTarget?.first,socialTarget?.second,onConditions={navController.navigate(TopLevelDestination.Today.route)},onCommunity={navController.navigate(COMMUNITY_ROUTES_ROUTE)},onNotifications={navController.navigate(NOTIFICATIONS_ROUTE)},onActivity={id->activityTarget=id;navController.navigate(ACTIVITY_HISTORY_ROUTE)})
                    } else {
                        FoundationScreen(destination, authState, authViewModel)
                    }
                }
            }
            composable(ASSISTANT_ROUTE) {
                AssistantRoute(
                    requireNotNull(accountId),
                    onClose = { navController.popBackStack() },
                )
            }
            composable(RECORDING_ROUTE) {
                RecordingRoute(
                    accountId = requireNotNull(accountId) { "Authenticated session is missing its account identifier." },
                    launch = recordingLaunch,
                    onSaved = { review: RecordedActivityReview ->
                        suppressRecordingRecovery = true
                        healthViewModel.export(review)
                        integrationViewModel.completePlannedWorkout(recordingLaunch, review)
                        navController.navigate(TopLevelDestination.Me.route) {
                            popUpTo(RECORDING_ROUTE) { inclusive = true }
                        }
                    },
                    onExit = {
                        suppressRecordingRecovery = true
                        navController.navigate(TopLevelDestination.Today.route) {
                            popUpTo(RECORDING_ROUTE) { inclusive = true }
                        }
                    },
                    sessionEffect = { snapshot -> LiveCoachRecordingEffect(recordingLaunch);RecordingSafetyEffect(snapshot) },
                )
            }
            composable(ACTIVITY_HISTORY_ROUTE) {
                ActivityHistoryRoute(
                    accountId = requireNotNull(accountId) { "Authenticated session is missing its account identifier." },
                    initialActivityId = activityTarget,
                    onBack = { navController.popBackStack() },
                    onMessage = { message -> snackbar.showSnackbar(resources.getString(activityMessageResource(message))) },
                )
            }
            composable(MUSIC_ROUTE) { MusicRoute(onClose = { navController.popBackStack() }) }
            composable(PROGRESS_ROUTE) { ProgressRoute(requireNotNull(accountId), integration.progress) }
            composable(COMMUNITY_ROUTES_ROUTE) { CommunityRouteScreen(integration.routes, integration.routeScope, integrationViewModel::scope, integrationViewModel::refreshRoutes, integrationViewModel::search, { launch -> recordingLaunch=launch;navController.navigate(RECORDING_ROUTE) }, integrationViewModel::bookmark,integration.publishableActivities,integrationViewModel::publishRoute) }
            composable(SAFETY_ROUTE) { SafetyRoute(safetyTarget?.second, safetyTarget?.first ?: "group") }
            composable(HEALTH_ROUTE) { HealthDestination(healthPermissions, healthViewModel::refresh) { navController.popBackStack() } }
            composable(NOTIFICATIONS_ROUTE, deepLinks = listOf(navDeepLink { uriPattern = "plainstride://notification/{destination}?id={id}&notification={notification}" })) {
                LaunchedEffect(Unit) { integrationViewModel.openInbox() }
                NotificationInbox(integration.notifications) { destination -> when(destination){ NotificationDestination.Connections -> { socialTarget="connections" to "";navController.navigate(TopLevelDestination.Social.route) };is NotificationDestination.Activity -> { activityTarget=destination.id;navController.navigate(ACTIVITY_HISTORY_ROUTE) };is NotificationDestination.Post -> {socialTarget="post" to destination.id;navController.navigate(TopLevelDestination.Social.route)};is NotificationDestination.Event -> {socialTarget="event" to destination.id;navController.navigate(TopLevelDestination.Social.route)};is NotificationDestination.Invitation -> {socialTarget="invitation" to destination.id;navController.navigate(TopLevelDestination.Social.route)};is NotificationDestination.Circle -> {socialTarget="circle" to destination.id;navController.navigate(TopLevelDestination.Social.route)};is NotificationDestination.Group -> {safetyTarget="group" to destination.id;navController.navigate(SAFETY_ROUTE)};is NotificationDestination.Live -> {safetyTarget="live" to destination.id;navController.navigate(SAFETY_ROUTE)};NotificationDestination.Inbox -> Unit } }
            }
        }
    }
    if (authState.confirmDeletion) AlertDialog(
        onDismissRequest = authViewModel::cancelDeletion,
        title = { Text(stringResource(R.string.delete_account_title)) },
        text = { Text(stringResource(R.string.delete_account_body)) },
        confirmButton = { TextButton(onClick = { authViewModel.deleteAccount(context) }) { Text(stringResource(R.string.delete_account_confirm)) } },
        dismissButton = { TextButton(onClick = authViewModel::cancelDeletion) { Text(stringResource(R.string.cancel)) } },
    )
}

private const val RECORDING_ROUTE = "recording"
private const val ASSISTANT_ROUTE = "assistant"
private const val MUSIC_ROUTE = "music"
private const val ACTIVITY_HISTORY_ROUTE = "activity_history"
private const val PROGRESS_ROUTE = "progress"
private const val COMMUNITY_ROUTES_ROUTE = "community_routes"
private const val SAFETY_ROUTE = "safety"
private const val HEALTH_ROUTE = "health"
private const val NOTIFICATIONS_ROUTE = "notifications"

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
        workoutSteps = curatedWorkout?.steps?.map { StructuredWorkoutStep(it.label, it.detail, it.durationSeconds, it.coachingTarget?.phase, it.coachingTarget?.pace?.targetSecondsPerKilometer) }.orEmpty(),
        entrySource = "today_manual",
        gearId = defaultGearId,
        indoor = indoor,
        voiceGuideEnabled = voiceGuideEnabled,
        startImmediately = true,
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
                TextButton(onClick = { viewModel.trackLegal("terms"); uriHandler.openUri("https://run.plainstride.com/terms") }) { Text(stringResource(R.string.auth_terms_link)) }
                TextButton(onClick = { viewModel.trackLegal("privacy"); uriHandler.openUri("https://run.plainstride.com/privacy") }) { Text(stringResource(R.string.auth_privacy_link)) }
            }
        }
    }
}

@Composable
private fun WelcomeOrbit(modifier: Modifier = Modifier) {
    Box(modifier.height(220.dp), contentAlignment = Alignment.Center) {
        Surface(shape = RoundedCornerShape(120.dp), color = MaterialTheme.colorScheme.primary.copy(alpha = 0.08f), modifier = Modifier.size(275.dp, 132.dp)) {}
        OrbitPerson(R.string.auth_orbit_family, Icons.Default.Favorite, Modifier.align(Alignment.TopStart).padding(start = 26.dp, top = 22.dp))
        OrbitPerson(R.string.auth_orbit_friends, Icons.Default.Group, Modifier.align(Alignment.TopEnd).padding(end = 26.dp, top = 34.dp))
        OrbitPerson(R.string.auth_orbit_groups, Icons.Default.Groups2, Modifier.align(Alignment.BottomStart).padding(start = 36.dp, bottom = 20.dp))
        Surface(shape = RoundedCornerShape(40.dp), color = MaterialTheme.colorScheme.secondaryContainer, modifier = Modifier.size(76.dp)) {
            Box(contentAlignment = Alignment.Center) { Icon(Icons.Default.Person, stringResource(R.string.auth_orbit_you), Modifier.size(34.dp)) }
        }
        Surface(shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.primaryContainer, modifier = Modifier.align(Alignment.BottomCenter)) {
            Row(Modifier.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.AutoAwesome, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text(stringResource(R.string.auth_better_together), style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

@Composable
private fun OrbitPerson(label: Int, icon: androidx.compose.ui.graphics.vector.ImageVector, modifier: Modifier) {
    Surface(shape = RoundedCornerShape(34.dp), color = MaterialTheme.colorScheme.surfaceVariant, modifier = modifier.size(66.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Icon(icon, null, Modifier.size(21.dp)); Text(stringResource(label), style = MaterialTheme.typography.labelSmall)
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
