package run.plainstride.app

import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import androidx.compose.material3.Switch
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.platform.LocalContext
import android.content.pm.PackageManager
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navDeepLink
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import run.plainstride.app.auth.AuthMessage
import run.plainstride.app.auth.AuthOperation
import run.plainstride.app.auth.AuthUiState
import run.plainstride.app.auth.AuthViewModel
import run.plainstride.core.auth.SessionState
import run.plainstride.feature.activity.ActivityHistoryRoute
import run.plainstride.feature.activity.ActivityMessage
import run.plainstride.feature.activity.RecentActivitiesRoute
import run.plainstride.feature.onboarding.OnboardingEffect
import run.plainstride.feature.onboarding.OnboardingRoute
import run.plainstride.feature.today.TodayMessage
import run.plainstride.feature.today.TodayRoute
import run.plainstride.feature.today.TodayViewModel
import run.plainstride.feature.settings.MeRoute
import run.plainstride.feature.settings.SettingsMessage
import run.plainstride.feature.settings.SettingsViewModel
import run.plainstride.feature.recording.ActivityKind
import run.plainstride.feature.recording.RecordedActivityReview
import run.plainstride.feature.recording.RecordingGoal
import run.plainstride.feature.recording.RecordingGoalType
import run.plainstride.feature.recording.RecordingLaunchConfiguration
import run.plainstride.feature.recording.RecordingRoute
import run.plainstride.feature.recording.StructuredWorkoutStep
import run.plainstride.feature.livecoach.LiveCoachRecordingEffect
import run.plainstride.feature.livecoach.LiveCoachSettingsSection
import run.plainstride.feature.assistant.AssistantRoute
import run.plainstride.feature.assistant.MusicRoute
import run.plainstride.feature.social.SocialRoute
import run.plainstride.feature.today.WorkoutLaunchIntent
import run.plainstride.core.model.Modality
import run.plainstride.feature.community.CommunityRouteScreen
import run.plainstride.feature.health.*
import run.plainstride.feature.progress.ProgressScreen
import run.plainstride.feature.safety.*
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.rememberLauncherForActivityResult
import android.content.Intent
import android.provider.Settings
import kotlinx.coroutines.launch
import run.plainstride.app.reminders.ReminderViewModel

private enum class TopLevelDestination(
    val route: String,
    @param:StringRes val label: Int,
    @param:StringRes val headline: Int,
    @param:StringRes val body: Int,
) {
    Social("social", R.string.tab_social, R.string.social_headline, R.string.social_body),
    Today("today", R.string.tab_today, R.string.today_headline, R.string.today_body),
    Assistant("assistant", R.string.tab_assistant, R.string.assistant_headline, R.string.assistant_body),
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
    var onboardingResolved by remember { mutableStateOf(false) }
    var forceOnboardingReplay by remember { mutableStateOf(false) }
    val resources = LocalResources.current
    val scope = rememberCoroutineScope()
    if (!onboardingResolved) {
        OnboardingRoute(
            onComplete = { onboardingResolved = true },
            forceReplay = forceOnboardingReplay,
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
    var hasActiveSession by remember { mutableStateOf(false) }
    val accountId = when (val session = authState.session) {
        is SessionState.SignedIn -> session.accountId
        is SessionState.Refreshing -> session.accountId
        else -> null
    }
    val integrationViewModel: P0IntegrationViewModel = hiltViewModel()
    val reminderViewModel: ReminderViewModel = hiltViewModel()
    val reminderEnabled by reminderViewModel.enabled.collectAsStateWithLifecycle()
    val integration by integrationViewModel.state.collectAsStateWithLifecycle()
    LaunchedEffect(accountId) { accountId?.let { integrationViewModel.start(it, resources.configuration.locales[0].toLanguageTag()) } }
    LaunchedEffect(navigationUri) {
        val destination = navigationUri?.pathSegments?.firstOrNull() ?: return@LaunchedEffect
        when (destination) {
            "today" -> navController.navigate(TopLevelDestination.Today.route)
            "assistant" -> navController.navigate(TopLevelDestination.Assistant.route)
            "inbox" -> navController.navigate(NOTIFICATIONS_ROUTE)
            "connections", "activity", "event", "circle", "group" -> navController.navigate(TopLevelDestination.Social.route)
            "live" -> navController.navigate(SAFETY_ROUTE)
            else -> navController.navigate(NOTIFICATIONS_ROUTE)
        }
        onNavigationUriConsumed()
    }

    Scaffold(
        contentWindowInsets = WindowInsets.safeDrawing,
        snackbarHost = { SnackbarHost(snackbar) },
        bottomBar = {
            if (currentDestination?.route != RECORDING_ROUTE && currentDestination?.route != ACTIVITY_HISTORY_ROUTE) NavigationBar {
                TopLevelDestination.entries.forEach { destination ->
                    NavigationBarItem(
                        selected = currentDestination?.hierarchy?.any {
                            it.route == destination.route
                        } == true,
                        onClick = {
                            navController.navigate(destination.route) {
                                popUpTo(TopLevelDestination.Today.route) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = { Text(stringResource(destination.label).take(1)) },
                        label = { Text(stringResource(destination.label)) },
                    )
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
                            onStartWorkout = { intent ->
                                recordingLaunch = intent.toRecordingLaunch()
                                hasActiveSession = true
                                navController.navigate(RECORDING_ROUTE) { launchSingleTop = true }
                            },
                            onStartFreestyle = {
                                recordingLaunch = RecordingLaunchConfiguration()
                                hasActiveSession = true
                                navController.navigate(RECORDING_ROUTE) { launchSingleTop = true }
                            },
                            onReturnToSession = { navController.navigate(RECORDING_ROUTE) { launchSingleTop = true } },
                            onSetUpPlan = { /* Plan setup is connected by the planning flow. */ },
                            onMessage = { message ->
                                snackbar.showSnackbar(resources.getString(todayMessageResource(message)))
                            },
                        )
                    } else if (destination == TopLevelDestination.Me) {
                        MeRoute(
                            viewModel = settingsViewModel,
                            appVersion = BuildConfig.VERSION_NAME,
                            debugToolsEnabled = BuildConfig.DEBUG,
                            onLinkGoogle = authViewModel::linkGoogle,
                            onSignOut = authViewModel::signOut,
                            onDeleteAccount = authViewModel::requestDeletion,
                            onReplayOnboarding = {
                                forceOnboardingReplay = true
                                onboardingResolved = false
                            },
                            onActivityHistory = { navController.navigate(ACTIVITY_HISTORY_ROUTE) { launchSingleTop = true } },
                            activityContent = {
                                accountId?.let { id -> RecentActivitiesRoute(id, { navController.navigate(ACTIVITY_HISTORY_ROUTE) { launchSingleTop = true } }) }
                            },
                            settingsContent = {
                                LiveCoachSettingsSection()
                                ListItem(headlineContent = { Text(stringResource(R.string.music_settings_title)) }, supportingContent = { Text(stringResource(R.string.music_settings_body)) }, modifier = Modifier.clickable { navController.navigate(MUSIC_ROUTE) })
                                ListItem(headlineContent = { Text(stringResource(R.string.progress_destination)) }, modifier = Modifier.clickable { navController.navigate(PROGRESS_ROUTE) })
                                ListItem(headlineContent = { Text(stringResource(R.string.routes_destination)) }, modifier = Modifier.clickable { navController.navigate(COMMUNITY_ROUTES_ROUTE) })
                                ListItem(headlineContent = { Text(stringResource(R.string.health_destination)) }, modifier = Modifier.clickable { navController.navigate(HEALTH_ROUTE) })
                                ListItem(headlineContent = { Text(stringResource(R.string.safety_destination)) }, modifier = Modifier.clickable { navController.navigate(SAFETY_ROUTE) })
                                ListItem(headlineContent = { Text(stringResource(R.string.notifications_destination)) }, modifier = Modifier.clickable { navController.navigate(NOTIFICATIONS_ROUTE) })
                                ListItem(headlineContent = { Text(stringResource(R.string.reminder_setting)) }, supportingContent = { Text(stringResource(R.string.reminder_setting_body)) }, trailingContent = { Switch(reminderEnabled, reminderViewModel::setEnabled) })
                            },
                            onMessage = { message -> snackbar.showSnackbar(resources.getString(settingsMessageResource(message))) },
                        )
                    } else if (destination == TopLevelDestination.Social && accountId != null) {
                        SocialRoute(accountId, resources.configuration.locales[0].toLanguageTag())
                    } else if (destination == TopLevelDestination.Assistant && accountId != null) {
                        AssistantRoute(accountId, onClose = { navController.navigate(TopLevelDestination.Today.route) })
                    } else {
                        FoundationScreen(destination, authState, authViewModel)
                    }
                }
            }
            composable(RECORDING_ROUTE) {
                RecordingRoute(
                    accountId = requireNotNull(accountId) { "Authenticated session is missing its account identifier." },
                    launch = recordingLaunch,
                    onSaved = { review: RecordedActivityReview ->
                        integrationViewModel.export(review)
                        integrationViewModel.completePlannedWorkout(recordingLaunch, review)
                        hasActiveSession = false
                        navController.navigate(TopLevelDestination.Me.route) {
                            popUpTo(RECORDING_ROUTE) { inclusive = true }
                        }
                    },
                    onExit = {
                        hasActiveSession = false
                        navController.navigate(TopLevelDestination.Today.route) {
                            popUpTo(RECORDING_ROUTE) { inclusive = true }
                        }
                    },
                    sessionEffect = { LiveCoachRecordingEffect(recordingLaunch) },
                )
            }
            composable(ACTIVITY_HISTORY_ROUTE) {
                ActivityHistoryRoute(
                    accountId = requireNotNull(accountId) { "Authenticated session is missing its account identifier." },
                    onBack = { navController.popBackStack() },
                    onMessage = { message -> snackbar.showSnackbar(resources.getString(activityMessageResource(message))) },
                )
            }
            composable(MUSIC_ROUTE) { MusicRoute(onClose = { navController.popBackStack() }) }
            composable(PROGRESS_ROUTE) { ProgressScreen(integration.progress) }
            composable(COMMUNITY_ROUTES_ROUTE) { CommunityRouteScreen(integration.routes, integration.routeScope, integrationViewModel::scope, integrationViewModel::refreshRoutes, integrationViewModel::search, {}, integrationViewModel::bookmark) }
            composable(SAFETY_ROUTE) { SafetyDestination() }
            composable(HEALTH_ROUTE) { HealthDestination(integration.health, integrationViewModel::refreshHealth) }
            composable(NOTIFICATIONS_ROUTE, deepLinks = listOf(navDeepLink { uriPattern = "plainstride://notification/{destination}?id={id}&notification={notification}" })) { NotificationInbox(integration.notifications) { destination -> when(destination){ NotificationDestination.Connections -> navController.navigate(TopLevelDestination.Social.route); is NotificationDestination.Post -> navController.navigate(TopLevelDestination.Social.route); is NotificationDestination.Event -> navController.navigate(TopLevelDestination.Social.route); is NotificationDestination.Circle -> navController.navigate(TopLevelDestination.Social.route); NotificationDestination.Inbox -> Unit } } }
        }
    }
    if (authState.confirmDeletion) AlertDialog(
        onDismissRequest = authViewModel::cancelDeletion,
        title = { Text(stringResource(R.string.delete_account_title)) },
        text = { Text(stringResource(R.string.delete_account_body)) },
        confirmButton = { TextButton(onClick = authViewModel::deleteAccount) { Text(stringResource(R.string.delete_account_confirm)) } },
        dismissButton = { TextButton(onClick = authViewModel::cancelDeletion) { Text(stringResource(R.string.cancel)) } },
    )
}

private const val RECORDING_ROUTE = "recording"
private const val MUSIC_ROUTE = "music"
private const val ACTIVITY_HISTORY_ROUTE = "activity_history"
private const val PROGRESS_ROUTE = "progress"
private const val COMMUNITY_ROUTES_ROUTE = "community_routes"
private const val SAFETY_ROUTE = "safety"
private const val HEALTH_ROUTE = "health"
private const val NOTIFICATIONS_ROUTE = "notifications"

private fun notificationPermissionState(context: android.content.Context): NotificationPermissionState = if(android.os.Build.VERSION.SDK_INT<33||context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)==PackageManager.PERMISSION_GRANTED) NotificationPermissionState.GRANTED else NotificationPermissionState.DENIED

@Composable private fun SafetyDestination() {
    val context=LocalContext.current
    var permission by remember { mutableStateOf(notificationPermissionState(context)) }
    val launcher=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()){permission=notificationPermissionState(context)}
    SafetySettingsScreen(emptyList(),permission,{launcher.launch(android.Manifest.permission.POST_NOTIFICATIONS)},{context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,android.net.Uri.parse("package:${context.packageName}")))},{},{})
}

@Composable private fun HealthDestination(snapshot: HealthPermissionSnapshot?, refresh:()->Unit) {
    val context=LocalContext.current
    val launcher=rememberLauncherForActivityResult(androidx.health.connect.client.PermissionController.createRequestPermissionResultContract()){refresh()}
    if(snapshot==null) Box(Modifier.fillMaxSize(),contentAlignment=Alignment.Center){CircularProgressIndicator()} else HealthConnectEducation(snapshot,{launcher.launch(it)},{context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,android.net.Uri.parse("package:${context.packageName}")))},{})
}

@StringRes
private fun activityMessageResource(message: ActivityMessage): Int = when (message) {
    ActivityMessage.SAVED -> run.plainstride.feature.activity.R.string.activity_saved
    ActivityMessage.UPDATED -> run.plainstride.feature.activity.R.string.activity_updated
    ActivityMessage.DELETED -> run.plainstride.feature.activity.R.string.activity_deleted
    ActivityMessage.FAILED -> run.plainstride.feature.activity.R.string.activity_failed
    ActivityMessage.EXPORT_UNAVAILABLE -> run.plainstride.feature.activity.R.string.activity_export_unavailable
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
    )
}

@Composable
private fun FoundationScreen(destination: TopLevelDestination, authState: AuthUiState, authViewModel: AuthViewModel) {
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
                Button(onClick = authViewModel::linkGoogle, enabled = authState.operation == null) {
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
    var showsTransfer by remember { mutableStateOf(initialTransferCode != null) }
    var transferCode by remember { mutableStateOf(initialTransferCode.orEmpty()) }
    LaunchedEffect(initialTransferCode) {
        if (initialTransferCode != null) {
            showsTransfer = true
            transferCode = initialTransferCode
        }
    }
    Scaffold(snackbarHost = { SnackbarHost(snackbar) }) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(stringResource(R.string.auth_welcome), style = MaterialTheme.typography.headlineLarge, textAlign = TextAlign.Center)
            Text(stringResource(R.string.auth_welcome_body), modifier = Modifier.padding(vertical = 16.dp), textAlign = TextAlign.Center)
            Button(onClick = viewModel::signIn, enabled = state.operation == null) {
                Text(stringResource(if (state.operation == null) R.string.continue_with_google else R.string.signing_in))
            }
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
                        viewModel.redeemTransfer(transferCode)
                        onTransferCodeConsumed()
                    },
                    enabled = state.operation == null && transferCode.isNotBlank(),
                    modifier = Modifier.padding(top = 8.dp),
                ) {
                    Text(stringResource(if (state.operation == AuthOperation.Redeem) R.string.transfer_connecting else R.string.transfer_connect))
                }
            }
            Text(stringResource(R.string.auth_terms_notice), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 16.dp), textAlign = TextAlign.Center)
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
    TodayMessage.CouldNotRefresh -> run.plainstride.feature.today.R.string.today_refresh_failed
    TodayMessage.CouldNotAdjust -> run.plainstride.feature.today.R.string.today_adjust_failed
    TodayMessage.AdjustmentApplied -> run.plainstride.feature.today.R.string.today_adjust_applied
    TodayMessage.OriginalKept -> run.plainstride.feature.today.R.string.today_original_kept
}

@StringRes
private fun settingsMessageResource(message: SettingsMessage) = when (message) {
    SettingsMessage.Refreshed -> run.plainstride.feature.settings.R.string.settings_refreshed
    SettingsMessage.Saved -> run.plainstride.feature.settings.R.string.settings_saved
    SettingsMessage.SaveFailed -> run.plainstride.feature.settings.R.string.settings_save_failed
    SettingsMessage.RefreshFailed -> run.plainstride.feature.settings.R.string.settings_refresh_failed
}
