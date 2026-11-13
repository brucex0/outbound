package com.plainstride.outbound.feature.today

import com.plainstride.outbound.core.data.AccountConfigurationStore
import androidx.compose.runtime.collectAsState

import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.Surface
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Checkbox
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Hiking
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Mail
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Route
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.provider.Settings
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalUriHandler
import android.widget.Toast
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Battery2Bar
import androidx.compose.material.icons.filled.Healing
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Sync
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp

import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonArray
import androidx.compose.foundation.rememberScrollState
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.runtime.DisposableEffect
import java.text.DateFormat
import java.util.Date
import kotlin.math.roundToInt
import com.plainstride.outbound.core.model.ActivitySuggestion
import com.plainstride.outbound.core.model.AdjustmentProposal
import com.plainstride.outbound.core.model.Modality
import com.plainstride.outbound.core.model.StandaloneWorkout
import com.plainstride.outbound.core.designsystem.MapCameraSnapshotReader
import com.plainstride.outbound.core.designsystem.PlainstrideRouteMap
import com.plainstride.outbound.core.designsystem.PrimaryBottomToolbarClearance
import com.plainstride.outbound.core.designsystem.PlainstrideFloatingAction
import com.plainstride.outbound.core.designsystem.LocationEnableChip
import com.plainstride.outbound.core.designsystem.LocationPermissionEducationDialog
import com.plainstride.outbound.core.location.LocationPermissionAccess
import com.plainstride.outbound.core.model.activity.PlannedCalorieEstimate

data class TodayShoeOption(val id: String, val displayName: String)
data class TodayRouteSelection(
    val id: String,
    val name: String,
    val distanceLabel: String,
    val points: List<com.plainstride.outbound.core.designsystem.MapCoordinate>,
    val reverse: Boolean = false,
)

enum class TodayActivityChoice { PLANNED, RUN, WALK, HIKE, BIKE }
enum class TodayGoalChoice { CURATED, RACE, FREE, DISTANCE, TIME, CALORIES }

data class TodayManualLaunch(
    val activity: TodayActivityChoice,
    val goal: TodayGoalChoice,
    val distanceMeters: Double = 5_000.0,
    val durationSeconds: Long = 1_800,
    val calories: Int = 300,
    val indoor: Boolean = false,
    val voiceGuideEnabled: Boolean = true,
    val curatedWorkout: StandaloneWorkout? = null,
    val curatedWorkoutCatalogVersion: Int? = null,
    val companionType: com.plainstride.outbound.core.model.activity.ActivityCompanionType? = null,
    val autoStopAtGoal: Boolean = false,
    val racePlan: TodayRacePlan? = null,
    val raceTitle: String? = null,
    val raceGuideline: String? = null,
    val aiCoachEnabled: Boolean = true,
)
data class TodayLaunchOptions(
    val indoor: Boolean,
    val voiceGuideEnabled: Boolean,
    val companionType: com.plainstride.outbound.core.model.activity.ActivityCompanionType? = null,
    val aiCoachEnabled: Boolean = true,
)

@Composable
fun TodayRoute(
    accountId: String,
    localeTag: String,
    viewModel: TodayViewModel,
    activeSession: Boolean,
    completedToday: Boolean,
    onStartWorkout: (WorkoutLaunchIntent, TodayLaunchOptions) -> Unit,
    onStartFreestyle: (TodayLaunchOptions) -> Unit,
    onReturnToSession: () -> Unit,
    onSetUpPlan: () -> Unit,
    onBuildPlan: () -> Unit = onSetUpPlan,
    onStartManual: (TodayManualLaunch) -> Unit,
    shoes: List<TodayShoeOption> = emptyList(),
    selectedShoeId: String? = null,
    onSelectShoe: (TodayShoeOption) -> Unit = {},
    onAddShoe: () -> Unit,
    onOpenLiveTrack: () -> Unit,
    cheerRecipientsSelected: Boolean = false,
    onOpenInbox: () -> Unit,
    onOpenStretch: () -> Unit,
    plannedWorkoutWarmupDuration: String? = null,
    onFindRoute: () -> Unit,
    selectedRoute: TodayRouteSelection? = null,
    onRemoveRoute: () -> Unit = {},
    onRouteDirectionChanged: (Boolean) -> Unit = {},
    unitSystem: com.plainstride.outbound.core.model.activity.MeasurementUnitSystem = com.plainstride.outbound.core.model.activity.MeasurementUnitSystem.metric,
    useFahrenheit: Boolean,
    inboxCount: Int,
    onMessage: suspend (TodayMessage) -> Unit,
    initialWorkoutId: String? = null,
    guidanceContent: @Composable () -> Unit = {},
    groupActivityContent: (@Composable () -> Unit)? = null,
    startRequest: Int = 0,
    refreshRequest: Int = 0,
    mapLocation: android.location.Location? = null,
    onMapCameraSnapshotReader: ((MapCameraSnapshotReader?) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(accountId, localeTag) { viewModel.configure(accountId, localeTag) }
    LaunchedEffect(refreshRequest) { if (refreshRequest > 0) viewModel.refresh() }
    val state by viewModel.state.collectAsStateWithLifecycle()
    val weather by viewModel.weather.collectAsStateWithLifecycle()
    val planPicker by viewModel.planPicker.collectAsStateWithLifecycle()
    var locationGranted by remember(context) { mutableStateOf(LocationPermissionAccess.hasPermission(context)) }
    var showsLocationPermission by remember { mutableStateOf(false) }
    var pendingWeatherRefresh by remember { mutableStateOf(false) }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        locationGranted = LocationPermissionAccess.hasPermission(context)
        pendingWeatherRefresh = false
        if (locationGranted) viewModel.refreshWeather()
    }
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                locationGranted = LocationPermissionAccess.hasPermission(context)
                if (locationGranted && pendingWeatherRefresh) {
                    pendingWeatherRefresh = false
                    viewModel.refreshWeather()
                }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(activeSession, completedToday) { viewModel.updateSessionState(activeSession, completedToday) }
    LaunchedEffect(viewModel) { viewModel.messages.collect(onMessage) }
    val raceHistory by viewModel.raceHistory.collectAsStateWithLifecycle()
    TodayScreen(
        raceHistory = raceHistory,
        unitSystem = unitSystem,
        state = state,
        groupActivityContent = groupActivityContent,
        weather = weather,
        onRefresh = viewModel::refresh,
        onStart = { suggestion, source, options ->
            viewModel.trackWorkoutStarted(source)
            onStartWorkout(viewModel.launchIntent(suggestion, source), options)
        },
        onStartChangedRun = { reason, minutes, options ->
            val source = "today_changed_run"
            viewModel.trackWorkoutStarted(source)
            onStartWorkout(WorkoutLaunchIntent(
                suggestionId = "changed-${reason.wireValue}-$minutes",
                plannedWorkoutId = null,
                title = context.getString(R.string.today_changed_run_title, minutes),
                modality = Modality.run,
                stimulus = com.plainstride.outbound.core.model.TrainingStimulus.easyAerobic,
                durationSeconds = minutes * 60,
                distanceMeters = null,
                targetCalories = null,
                effortLabel = context.getString(R.string.today_changed_run_detail, minutes),
                intensityModel = "veryEasy",
                steps = emptyList(),
                source = source,
                guideLine = context.getString(R.string.today_changed_run_guide),
            ), options)
        },
        onStartFreestyle = onStartFreestyle,
        onReturnToSession = onReturnToSession,
        onSetUpPlan = onSetUpPlan,
        onBuildPlan = onBuildPlan,
        planPicker = planPicker,
        onRunningBenchmarkOpened = viewModel::trackRunningBenchmarkOpened,
        onUpdateRunningBenchmark = viewModel::updateRunningBenchmark,
        onUpdateRaceGoal = viewModel::updateRaceGoal,
        onRaceGoalOpened = viewModel::trackRaceGoalOpened,
        onWorkoutChangeOpened = viewModel::trackWorkoutChangeOpened,
        onRecoveryAdviceShown = viewModel::trackRecoveryAdviceShown,
        onDismissPlanPicker = viewModel::closePlanPicker,
        onRetryPlanPicker = { viewModel.openPlanPicker() },
        onChangePlan = { viewModel.openPlanPicker("plan_details_change") },
        onEndPlan = viewModel::endPlan,
        onPlanDetailsOpened = viewModel::trackPlanDetailsOpened,
        onDailyRecommendationDetailsOpened = viewModel::trackDailyRecommendationDetailsOpened,
        onEndPlanConfirmation = viewModel::trackEndPlanConfirmation,
        onSelectPlan = viewModel::selectPlanRecommendation,
        onUsePlan = { recommendation, replacing -> viewModel.confirmPlanRecommendation(recommendation, replacing) },
        onStartManual = { setup -> viewModel.trackManualWorkoutStarted(setup.activity, setup.goal); onStartManual(setup) },
        shoes = shoes,
        selectedShoeId = selectedShoeId,
        onSelectShoe = onSelectShoe,
        onAddShoe = onAddShoe,
        onOpenLiveTrack = onOpenLiveTrack,
        cheerRecipientsSelected = cheerRecipientsSelected,
        onOpenInbox = onOpenInbox,
        onOpenStretch = onOpenStretch,
        plannedWorkoutWarmupDuration = plannedWorkoutWarmupDuration,
        onOpenPlannedWorkoutWarmup = { viewModel.trackPlannedWorkoutWarmupOpened(); onOpenStretch() },
        onFindRoute = onFindRoute,
        selectedRoute = selectedRoute,
        onRemoveRoute = onRemoveRoute,
        onRouteDirectionChanged = onRouteDirectionChanged,
        useFahrenheit = useFahrenheit,
        inboxCount = inboxCount,
        onSubmitConstraint = viewModel::submitConstraint,
        onDecideAdjustment = viewModel::decideAdjustment,
        onCardDisplayChanged = viewModel::trackCardDisplayChanged,
        onWeatherDetailsOpened = viewModel::trackWeatherDetailsOpened,
        onWeatherAttributionOpened = viewModel::trackWeatherAttributionOpened,
        onRacePlanApplied = viewModel::trackRacePlanApplied,
        onRacePlannerOpened = viewModel::trackRacePlannerOpened,
        onLaunchConfigurationChanged = viewModel::trackLaunchConfiguration,
        calorieEstimate = viewModel::calorieEstimate,
        guidanceContent = guidanceContent,
        startRequest = startRequest,
        initialWorkoutId = initialWorkoutId,
        locationGranted = locationGranted,
        mapLocation = mapLocation,
        onMapCameraSnapshotReader = onMapCameraSnapshotReader,
        onRequestLocationAccess = {
            if (locationGranted) viewModel.refreshWeather()
            else showsLocationPermission = true
        },
        modifier = modifier,
    )
    if (showsLocationPermission) LocationPermissionEducationDialog(
        onEnable = {
            showsLocationPermission = false
            pendingWeatherRefresh = true
            if (LocationPermissionAccess.wasRequestedBefore(context)) {
                context.openAppLocationSettings()
            } else {
                LocationPermissionAccess.markRequested(context)
                permissionLauncher.launch(LocationPermissionAccess.requestPermissions)
            }
        },
        onClose = { showsLocationPermission = false },
    )
}

@Composable
fun TodayScreen(
    state: TodayUiState,
    raceHistory: List<com.plainstride.outbound.core.model.activity.SavedActivity> = emptyList(),
    weather: WeatherGuidance?,
    onRefresh: () -> Unit,
    onStart: (ActivitySuggestion, String, TodayLaunchOptions) -> Unit,
    onStartChangedRun: (TodayConstraint, Int, TodayLaunchOptions) -> Unit = { _, _, _ -> },
    onStartFreestyle: (TodayLaunchOptions) -> Unit,
    onReturnToSession: () -> Unit,
    onSetUpPlan: () -> Unit,
    onBuildPlan: () -> Unit,
    planPicker: PlanPickerUiState = PlanPickerUiState(),
    onChangePlan: () -> Unit = {},
    onEndPlan: () -> Unit = {},
    onPlanDetailsOpened: (Int, String) -> Unit = { _, _ -> },
    onDailyRecommendationDetailsOpened: (String) -> Unit = {},
    onEndPlanConfirmation: () -> Unit = {},
    onUpdateRaceGoal: suspend (String, com.plainstride.outbound.core.network.RaceGoalUpdateRequest) -> Boolean = { _, _ -> false },
    onRunningBenchmarkOpened: () -> Unit = {},
    onUpdateRunningBenchmark: suspend (String, com.plainstride.outbound.core.model.RunningBenchmarkReport?) -> Boolean = { _, _ -> false },
    onRaceGoalOpened: () -> Unit = {},
    onWorkoutChangeOpened: () -> Unit = {},
    onRecoveryAdviceShown: () -> Unit = {},
    onDismissPlanPicker: () -> Unit = {},
    onRetryPlanPicker: () -> Unit = {},
    onSelectPlan: (com.plainstride.outbound.core.network.PlanRecommendation?) -> Unit = {},
    onUsePlan: (com.plainstride.outbound.core.network.PlanRecommendation, Boolean) -> Unit = { _, _ -> },
    onStartManual: (TodayManualLaunch) -> Unit = {},
    shoes: List<TodayShoeOption> = emptyList(),
    selectedShoeId: String? = null,
    onSelectShoe: (TodayShoeOption) -> Unit = {},
    onAddShoe: () -> Unit = {},
    onOpenLiveTrack: () -> Unit = {},
    cheerRecipientsSelected: Boolean = false,
    onOpenInbox: () -> Unit = {},
    onOpenStretch: () -> Unit = {},
    plannedWorkoutWarmupDuration: String? = null,
    onOpenPlannedWorkoutWarmup: () -> Unit = onOpenStretch,
    onFindRoute: () -> Unit = {},
    selectedRoute: TodayRouteSelection? = null,
    onRemoveRoute: () -> Unit = {},
    onRouteDirectionChanged: (Boolean) -> Unit = {},
    unitSystem: com.plainstride.outbound.core.model.activity.MeasurementUnitSystem = com.plainstride.outbound.core.model.activity.MeasurementUnitSystem.metric,
    useFahrenheit: Boolean = false,
    inboxCount: Int = 0,
    onSubmitConstraint: (TodayConstraint, ActivitySuggestion, String?, Int) -> Unit,
    onDecideAdjustment: (String, Boolean) -> Unit,
    onCardDisplayChanged: (Boolean) -> Unit = {},
    onWeatherDetailsOpened: () -> Unit = {},
    onWeatherAttributionOpened: () -> Unit = {},
    onRacePlanApplied: (TodayRacePlan) -> Unit = {},
    onRacePlannerOpened: () -> Unit = {},
    onLaunchConfigurationChanged: (String, String) -> Unit = { _, _ -> },
    calorieEstimate:suspend (TodayActivityChoice,Int)->PlannedCalorieEstimate?={_,_->null},
    guidanceContent: @Composable () -> Unit = {},
    groupActivityContent: (@Composable () -> Unit)? = null,
    startRequest: Int = 0,
    initialWorkoutId: String? = null,
    locationGranted: Boolean = false,
    mapLocation: android.location.Location? = null,
    onMapCameraSnapshotReader: ((MapCameraSnapshotReader?) -> Unit)? = null,
    onRequestLocationAccess: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    var showsPlanDetails by rememberSaveable { mutableStateOf(false) }
    var resolvesPlanSetup by rememberSaveable { mutableStateOf(false) }
    var detailsActivePlanId by rememberSaveable { mutableStateOf<String?>(null) }
    val planning = state.planningSnapshot
    val activePlan = planning?.plan
    val dailyRecommendation = state.currentRecommendationSnapshot
    val confirmedNoPlan = state.hasConfirmedNoPlan && dailyRecommendation == null
    val hasPlanDetails = !confirmedNoPlan
    fun openPlanDetails(entrySource: String) {
        if (activePlan == null && dailyRecommendation != null) onDailyRecommendationDetailsOpened(entrySource)
        else onPlanDetailsOpened(planning?.planWeekSnapshot()?.targetSessions ?: 0, entrySource)
        resolvesPlanSetup = activePlan == null && dailyRecommendation == null
        detailsActivePlanId = activePlan?.id
        showsPlanDetails = true
        if (activePlan == null && dailyRecommendation == null) onRefresh()
    }
    LaunchedEffect(showsPlanDetails, activePlan?.id, dailyRecommendation?.primary?.id, confirmedNoPlan) {
        if (showsPlanDetails && detailsActivePlanId != null && planning != null && activePlan == null) {
            // A successful End plan must dismiss its page even if a standalone recommendation arrives.
            showsPlanDetails = false
            resolvesPlanSetup = false
            detailsActivePlanId = null
        }
        if (activePlan != null || dailyRecommendation != null) {
            resolvesPlanSetup = false
            if (showsPlanDetails) detailsActivePlanId = activePlan?.id
        }
        if (showsPlanDetails && confirmedNoPlan) {
            showsPlanDetails = false
            if (resolvesPlanSetup) onSetUpPlan()
            resolvesPlanSetup = false
        }
    }
    var showsChange by rememberSaveable { mutableStateOf(false) }
    var showsWeather by rememberSaveable { mutableStateOf(false) }
    var showsRacePlanner by rememberSaveable { mutableStateOf(false) }
    var racePlan by rememberSaveable(saver = androidx.compose.runtime.saveable.listSaver<androidx.compose.runtime.MutableState<TodayRacePlan?>, Any>(
        save = { state -> state.value?.let { listOf(it.distanceMeters, it.goalTimeSeconds ?: -1, it.targetPaceSecondsPerKilometer ?: -1.0, it.pacingStrategy, it.recommendationSource) } ?: emptyList() },
        restore = { values -> mutableStateOf(if (values.isEmpty()) null else TodayRacePlan(values[0] as Double, (values[1] as Int).takeIf { it >= 0 }, (values[2] as Double).takeIf { it >= 0 }, values[3] as String, values[4] as String)) },
    )) { mutableStateOf<TodayRacePlan?>(null) }
    var showsCatalog by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    val displayPreferences = remember(context) { context.getSharedPreferences("today_display", android.content.Context.MODE_PRIVATE) }
    var cardMinimized by rememberSaveable { mutableStateOf(displayPreferences.getBoolean("planned_workout_minimized", true)) }
    var activityChoice by rememberSaveable { mutableStateOf(TodayActivityChoice.PLANNED) }
    var goalChoice by rememberSaveable { mutableStateOf(TodayGoalChoice.FREE) }
    var indoor by rememberSaveable { mutableStateOf(false) }
    val audioPreferences = remember(context) { com.plainstride.outbound.core.model.activity.ActivityAudioPreferences(context) }
    var voiceGuideEnabled by remember { mutableStateOf(audioPreferences.voiceEnabled) }
    var aiCoachEnabled by remember { mutableStateOf(audioPreferences.aiCoachEnabled) }
    androidx.compose.runtime.DisposableEffect(audioPreferences) {
        val listener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, _ ->
            voiceGuideEnabled = audioPreferences.voiceEnabled
            aiCoachEnabled = audioPreferences.aiCoachEnabled
        }
        audioPreferences.storage.registerOnSharedPreferenceChangeListener(listener)
        onDispose { audioPreferences.storage.unregisterOnSharedPreferenceChangeListener(listener) }
    }
    var companionType by rememberSaveable { mutableStateOf<com.plainstride.outbound.core.model.activity.ActivityCompanionType?>(null) }
    var curatedWorkout by remember { mutableStateOf<StandaloneWorkout?>(null) }
    var distanceMeters by rememberSaveable { mutableStateOf(5_000.0) }
    var durationSeconds by rememberSaveable { mutableStateOf(1_800L) }
    var calories by rememberSaveable { mutableStateOf(300) }
    var caloriePlan by remember { mutableStateOf<PlannedCalorieEstimate?>(null) }
    val configurationRevision by AccountConfigurationStore.changes.collectAsState()
    val manualDrafts = remember(AccountConfigurationStore.accountId) { mutableMapOf<TodayActivityChoice, Triple<Double, Long, Int>>() }
    val manualModes = remember(AccountConfigurationStore.accountId) { mutableMapOf<TodayActivityChoice, TodayGoalChoice>() }
    val locallyEdited = remember(AccountConfigurationStore.accountId) { mutableSetOf<TodayActivityChoice>() }
    fun saveManualDraft(markEdited: Boolean = true) {
        if (activityChoice != TodayActivityChoice.PLANNED) {
            manualDrafts[activityChoice] = Triple(distanceMeters, durationSeconds, calories)
            manualModes[activityChoice] = goalChoice
            if (markEdited) locallyEdited.add(activityChoice)
        }
    }
    LaunchedEffect(activityChoice, configurationRevision) {
        if (activityChoice == TodayActivityChoice.PLANNED) return@LaunchedEffect
        val sport = activityChoice.name.lowercase()
        val saved = AccountConfigurationStore.record("launch/$sport")?.value?.launch
        val draft = manualDrafts[activityChoice]
        if (activityChoice in locallyEdited && draft != null) {
            distanceMeters = draft.first; durationSeconds = draft.second; calories = draft.third
            goalChoice = manualModes[activityChoice] ?: TodayGoalChoice.FREE
        } else {
            distanceMeters = saved?.distanceMeters ?: 5_000.0
            durationSeconds = saved?.timeSeconds?.toLong() ?: 1_800L
            calories = saved?.calories ?: 300
            goalChoice = when (saved?.preferredGoalModeRawValue) {
                "distance" -> TodayGoalChoice.DISTANCE; "time" -> TodayGoalChoice.TIME
                "calories" -> TodayGoalChoice.CALORIES; else -> TodayGoalChoice.FREE
            }
        }
    }

    var editingGoal by rememberSaveable { mutableStateOf(false) }
    var autoStopAtGoal by rememberSaveable { mutableStateOf(displayPreferences.getBoolean("auto_stop_at_goal", false)) }
    var overflowExpanded by rememberSaveable { mutableStateOf(false) }
    var handledStartRequest by rememberSaveable { mutableStateOf(startRequest) }
    var mapOverlayBottomPadding by remember { mutableStateOf(0.dp) }
    val density = LocalDensity.current
    var setupPhoto by remember { mutableStateOf<Bitmap?>(null) }
    val photoLauncher = rememberLauncherForActivityResult(ActivityResultContracts.TakePicturePreview()) { photo ->
        if (photo != null) setupPhoto = photo
    }
    val suggestion = state.primarySuggestion
    LaunchedEffect(activityChoice, calories, goalChoice) {
        caloriePlan = if (goalChoice == TodayGoalChoice.CALORIES) {
            calorieEstimate(activityChoice, calories)
        } else {
            null
        }
    }
    val raceTitle = stringResource(R.string.race_planner_race_day)
    val raceGuideline = racePlan?.let { raceExecution(it, unitSystem) }
    val launchPreparedActivity = launch@ {
        if (activityChoice == TodayActivityChoice.PLANNED) {
            if (state.restRecommended || state.mutationInFlight) return@launch
            suggestion?.let { onStart(it, "today_planned", TodayLaunchOptions(indoor, voiceGuideEnabled, companionType, aiCoachEnabled)) }
                ?: onStartFreestyle(TodayLaunchOptions(indoor, voiceGuideEnabled, companionType, aiCoachEnabled))
        } else {
            val catalogVersion = (state.catalog as? CachedResource.Available)?.value?.version
            if (goalChoice == TodayGoalChoice.RACE && racePlan == null) { showsRacePlanner = true; return@launch }
            onStartManual(TodayManualLaunch(activityChoice, goalChoice, distanceMeters, durationSeconds, calories, indoor, voiceGuideEnabled, curatedWorkout, catalogVersion, companionType, autoStopAtGoal, racePlan.takeIf { goalChoice == TodayGoalChoice.RACE }, raceTitle.takeIf { goalChoice == TodayGoalChoice.RACE }, raceGuideline.takeIf { goalChoice == TodayGoalChoice.RACE }, aiCoachEnabled))
        }
    }
    LaunchedEffect(startRequest) {
        if (startRequest != handledStartRequest) {
            handledStartRequest = startRequest
            if (!state.activeSession) launchPreparedActivity()
        }
    }
    LaunchedEffect(initialWorkoutId, suggestion?.id, suggestion?.plannedWorkoutId) {
        if (initialWorkoutId != null && (suggestion?.id == initialWorkoutId || suggestion?.plannedWorkoutId == initialWorkoutId)) openPlanDetails("today_planned_card")
    }

    // Keep the map in the upper region, matching iOS Today; the dock owns the separate lower region.
    Column(modifier.fillMaxSize().padding(bottom = PrimaryBottomToolbarClearance)) {
        BoxWithConstraints(Modifier.fillMaxWidth().weight(1f)) {
            PlainstrideRouteMap(
                points = selectedRoute?.let { if (it.reverse) it.points.reversed() else it.points }.orEmpty(),
                modifier = Modifier.fillMaxSize(),
                showUserLocation = locationGranted,
                useSuppliedUserLocation = true,
                suppliedUserLocation = mapLocation,
                onCameraSnapshotReader = onMapCameraSnapshotReader,
                preciseLocationGranted = locationGranted,
                focusOnUser = true,
                bottomContentPadding = mapOverlayBottomPadding,
            )
            if (!state.activeSession) {
                Surface(Modifier.align(Alignment.TopStart).padding(16.dp), shape = CircleShape, tonalElevation = 3.dp) {
                    TextButton(onClick = onOpenStretch) { Text(stringResource(R.string.today_stretch)) }
                }
            }
            Row(Modifier.align(Alignment.TopEnd).padding(16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                TodayTopControls(weather, useFahrenheit, inboxCount, {
                    if (locationGranted && weather != null) {
                        onWeatherDetailsOpened()
                        showsWeather = true
                    } else onRequestLocationAccess()
                }, onOpenInbox)
                Box {
                    PlainstrideFloatingAction(onClick = { overflowExpanded = true }) {
                        setupPhoto?.let { Image(it.asImageBitmap(), stringResource(R.string.today_more), Modifier.size(48.dp).clip(CircleShape)) }
                            ?: Icon(Icons.Default.MoreVert, stringResource(R.string.today_more), Modifier.size(22.dp))
                    }
                    DropdownMenu(overflowExpanded, { overflowExpanded = false }) {
                        DropdownMenuItem({ Text(stringResource(R.string.today_take_photo)) }, { overflowExpanded = false; photoLauncher.launch(null) }, leadingIcon = { Icon(Icons.Default.PhotoCamera, null) })
                        DropdownMenuItem(
                            text = { Text(stringResource(if (selectedRoute == null) R.string.today_find_route else R.string.today_change_route)) },
                            onClick = { overflowExpanded = false; onFindRoute() },
                            leadingIcon = { Icon(Icons.Default.Route, null) },
                        )
                        if (selectedRoute != null) DropdownMenuItem(
                            text = { Text(stringResource(R.string.today_remove_route)) },
                            onClick = { overflowExpanded = false; onRemoveRoute() },
                            leadingIcon = { Icon(Icons.Default.Route, null) },
                        )
                    }
                }
            }
            Column(
                Modifier.align(Alignment.BottomCenter).fillMaxWidth()
                    .heightIn(max = maxHeight * .65f)
                    .onSizeChanged { mapOverlayBottomPadding = with(density) { it.height.toDp() } }
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                selectedRoute?.let { route ->
                    SelectedRouteCard(
                        route = route,
                        onChange = onFindRoute,
                        onRemove = onRemoveRoute,
                        onDirectionChanged = onRouteDirectionChanged,
                    )
                }
                when {
                    groupActivityContent != null -> groupActivityContent()
                    state.pendingWorkoutToday != null && activityChoice == TodayActivityChoice.PLANNED -> Card {
                        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(state.pendingWorkoutToday!!.title, style = MaterialTheme.typography.titleLarge)
                            Text(stringResource(R.string.plan_details_pending), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    state.suggestion is CachedResource.Loading && state.refreshError == null -> TodaySkeleton()
                    suggestion != null && activityChoice == TodayActivityChoice.PLANNED -> WorkoutRecommendationCard(
                        suggestion = suggestion,
                        stale = state.isStale,
                        updatedAtEpochMs = state.suggestionUpdatedAtEpochMs,
                        completedToday = state.currentRecommendationSnapshot?.relationship == "optionalRecovery",
                        recoveryChangeRecommended = state.recoveryChangeRecommended,
                        onRecoveryAdviceShown = onRecoveryAdviceShown,
                        weather = weather,
                        minimized = cardMinimized,
                        warmupDuration = plannedWorkoutWarmupDuration.takeIf { !state.activeSession && suggestion.modality == Modality.run },
                        onOpenWarmup = onOpenPlannedWorkoutWarmup,
                        onToggleMinimized = {
                            cardMinimized = !cardMinimized
                            displayPreferences.edit().putBoolean("planned_workout_minimized", cardMinimized).apply()
                            onCardDisplayChanged(cardMinimized)
                        },
                        onOpen = { openPlanDetails("today_planned_card") },
                        onChange = { onWorkoutChangeOpened(); showsChange = true },
                        onOpenPlan = if (hasPlanDetails) ({ openPlanDetails("today_planned_card_plan") }) else null,
                    )
                    state.restRecommended && activityChoice == TodayActivityChoice.PLANNED -> Card {
                        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(stringResource(R.string.today_change_rest_heading), style = MaterialTheme.typography.titleLarge)
                            Text(stringResource(R.string.today_change_rest_body), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    state.hasNoCachedSuggestion -> NoSuggestionCard(
                        noPlan = confirmedNoPlan,
                        onStartFreestyle = { onStartFreestyle(TodayLaunchOptions(indoor, voiceGuideEnabled, companionType, aiCoachEnabled)) },
                        onSetUpPlan = onSetUpPlan,
                        onRefresh = onRefresh,
                    )
                }
                if (hasPlanDetails && activityChoice == TodayActivityChoice.PLANNED && (suggestion == null || groupActivityContent != null)) {
                    OutlinedButton(onClick = { openPlanDetails("today_planned_card_plan") }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                        Text(stringResource(R.string.plan_details_title))
                    }
                }
                if (activityChoice != TodayActivityChoice.PLANNED && goalChoice != TodayGoalChoice.FREE) {
                    ManualGoalCard(goalChoice, racePlan, unitSystem, curatedWorkout, distanceMeters, durationSeconds, calories,caloriePlan, autoStopAtGoal) {
                        if (goalChoice == TodayGoalChoice.RACE) showsRacePlanner = true else if (goalChoice == TodayGoalChoice.CURATED) showsCatalog = true else editingGoal = true
                    }
                }
                guidanceContent()
            }
            }
            if (!locationGranted && !indoor && !state.activeSession) {
                Box(Modifier.fillMaxWidth().padding(bottom = 8.dp), contentAlignment = Alignment.Center) {
                    LocationEnableChip(onClick = onRequestLocationAccess)
                }
            }
            if (companionType != null && !activityChoice.isCompanionEligible(suggestion)) {
                companionType = null
                Toast.makeText(context, context.getString(R.string.today_companion_cleared_message), Toast.LENGTH_SHORT).show()
            }
            ActivityLaunchDock(
                suggestion = suggestion,
                activeSession = state.activeSession,
                completedToday = state.completedToday && suggestion?.plannedWorkoutId == null,
                activityChoice = activityChoice,
                goalChoice = goalChoice,
                indoor = indoor,
                voiceGuideEnabled = voiceGuideEnabled,
                aiCoachEnabled = aiCoachEnabled,
                companionType = companionType,
                onActivityChoice = {
                    if (it == TodayActivityChoice.PLANNED && activePlan == null) {
                        if (state.hasConfirmedNoPlan) onSetUpPlan() else onRefresh()
                    } else if (it == activityChoice) {
                        // Re-selecting the active choice must not reset its goal or setup draft.
                    } else {
                        saveManualDraft(markEdited = false)
                        activityChoice = it
                        if (it != TodayActivityChoice.RUN && goalChoice == TodayGoalChoice.RACE) goalChoice = TodayGoalChoice.FREE
                        onLaunchConfigurationChanged("activity_type", it.name.lowercase())
                    }
                },
                onGoalChoice = { choice ->
                    if (choice == TodayGoalChoice.RACE) {
                        showsRacePlanner = true
                    } else {
                        goalChoice = choice
                        saveManualDraft()
                        if (choice == TodayGoalChoice.CURATED) showsCatalog = true
                        onLaunchConfigurationChanged("goal", choice.name.lowercase())
                    }
                },
                onIndoorChanged = { indoor = it; onLaunchConfigurationChanged("environment", if (it) "indoor" else "outdoor") },
                onVoiceGuideChanged = { voiceGuideEnabled = it; audioPreferences.voiceEnabled = it; onLaunchConfigurationChanged("voice_guide", if (it) "enabled" else "disabled") },
                onAICoachChanged = { aiCoachEnabled = it; audioPreferences.aiCoachEnabled = it; onLaunchConfigurationChanged("ai_coach", if (it) "enabled" else "disabled") },
                onCompanionChanged = { enabled ->
                    companionType = if (enabled) com.plainstride.outbound.core.model.activity.ActivityCompanionType.dog else null
                    onLaunchConfigurationChanged("companion", if (enabled) "on" else "off")
                },
                onReturnToSession = onReturnToSession,
                onOpenDetails = { openPlanDetails("today_planned_card") },
                shoes = shoes,
                selectedShoeId = selectedShoeId,
                onSelectShoe = onSelectShoe,
                onAddShoe = onAddShoe,
                onOpenLiveTrack = onOpenLiveTrack,
                cheerRecipientsSelected = cheerRecipientsSelected,
            )
    }

    if (showsPlanDetails && planning != null && activePlan != null) {
        ActivePlanDetailsSheet(
            units = unitSystem,
            onRaceGoalOpened = onRaceGoalOpened,
            onRunningBenchmarkOpened = onRunningBenchmarkOpened,
            onUpdateRunningBenchmark = onUpdateRunningBenchmark,
            onUpdateRaceGoal = onUpdateRaceGoal,
            planning = planning,
            suggestion = (state.suggestion as? CachedResource.Available)?.value,
            suggestionStale = (state.suggestion as? CachedResource.Available)?.isStale == true || state.suggestion is CachedResource.Failed,
            busy = state.mutationInFlight,
            stale = (state.planning as? CachedResource.Available)?.isStale == true || state.planning is CachedResource.Failed,
            onDismiss = { showsPlanDetails = false },
            onChangePlan = { showsPlanDetails = false; onChangePlan() },
            onEndPlan = onEndPlan,
            onEndConfirmation = onEndPlanConfirmation,
            onRefresh = onRefresh,
            onChangeWorkout = suggestion?.let { { showsPlanDetails = false; onWorkoutChangeOpened(); showsChange = true } },
        )
    }

    if (showsPlanDetails && activePlan == null && dailyRecommendation != null) {
        DailyRecommendationDetailsSheet(
            recommendation = dailyRecommendation,
            stale = state.isStale || state.suggestion is CachedResource.Failed,
            busy = state.mutationInFlight,
            onDismiss = { showsPlanDetails = false },
            onChangeWorkout = { showsPlanDetails = false; onWorkoutChangeOpened(); showsChange = true },
            onSetUpPlan = { showsPlanDetails = false; onSetUpPlan() },
        )
    }

    if (showsPlanDetails && activePlan == null && dailyRecommendation == null && !confirmedNoPlan) {
        PlanDetailsSyncingSheet(onDismiss = { showsPlanDetails = false }, onRefresh = onRefresh)
    }

    if (planPicker.open) {
        PlanPickerDialog(
            picker = planPicker,
            hasActivePlan = (state.planning as? CachedResource.Available)?.value?.plan != null,
            onDismiss = onDismissPlanPicker,
            onRetry = onRetryPlanPicker,
            onSelect = onSelectPlan,
            onUse = onUsePlan,
            onBuild = { onDismissPlanPicker(); onBuildPlan() },
        )
    }

    val changeSuggestion = suggestion ?: dailyRecommendation?.primary
    if (showsChange && changeSuggestion != null) ChangeWorkoutSheet(
        original = changeSuggestion,
        pending = state.pendingAdjustment,
        busy = state.mutationInFlight,
        onDismiss = { showsChange = false },
        onApply = { reason, note, minutes ->
            showsChange = false
            onSubmitConstraint(reason, changeSuggestion, note, minutes)
        },
        onDecision = { id, accept -> showsChange = false; onDecideAdjustment(id, accept) },
    )
    if (showsWeather && weather != null) {
        val uriHandler = LocalUriHandler.current
        AlertDialog(
            onDismissRequest = { showsWeather = false },
            title = { Text(weather.headline) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(weather.detail)
                    Text(
                        weather.attribution,
                        modifier = Modifier.clickable(role = Role.Button) {
                            onWeatherAttributionOpened()
                            uriHandler.openUri(weather.attributionUrl)
                        },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            },
            confirmButton = { TextButton(onClick = { showsWeather = false }) { Text(stringResource(R.string.today_done)) } },
        )
    }
    LaunchedEffect(showsRacePlanner) { if (showsRacePlanner) onRacePlannerOpened() }
    if (showsRacePlanner) RacePlannerDialog(raceHistory, unitSystem, onDismiss = { showsRacePlanner = false }, onUse = {
        racePlan = it
        distanceMeters = it.distanceMeters
        curatedWorkout = null
        goalChoice = TodayGoalChoice.RACE
        showsRacePlanner = false
        onRacePlanApplied(it)
    })
    if (showsCatalog) CuratedWorkoutSheet(
        workouts = (state.catalog as? CachedResource.Available)?.value?.workouts.orEmpty()
            .filter { it.sport.lowercase() in activityChoice.catalogSportNames() },
        onDismiss = { showsCatalog = false; if (curatedWorkout == null) goalChoice = TodayGoalChoice.FREE },
        onChoose = {
            curatedWorkout = it
            showsCatalog = false
            onLaunchConfigurationChanged("curated_workout", "selected")
        },
    )
    if (editingGoal) GoalValueDialog(goalChoice, distanceMeters, durationSeconds, calories, autoStopAtGoal, { editingGoal = false },
        { enabled ->
            autoStopAtGoal = enabled
            displayPreferences.edit().putBoolean("auto_stop_at_goal", enabled).apply()
            onLaunchConfigurationChanged("auto_stop_at_goal", if (enabled) "enabled" else "disabled")
        },
        { distanceMeters = it; saveManualDraft(); editingGoal = false; onLaunchConfigurationChanged("goal_value", "preset") },
        { durationSeconds = it; saveManualDraft(); editingGoal = false; onLaunchConfigurationChanged("goal_value", "preset") },
        { calories = it; saveManualDraft(); editingGoal = false; onLaunchConfigurationChanged("goal_value", "preset") })
}

@Composable
internal fun PlanPickerDialog(
    picker: PlanPickerUiState,
    hasActivePlan: Boolean,
    onDismiss: () -> Unit,
    onRetry: () -> Unit,
    onSelect: (com.plainstride.outbound.core.network.PlanRecommendation?) -> Unit,
    onUse: (com.plainstride.outbound.core.network.PlanRecommendation, Boolean) -> Unit,
    onBuild: () -> Unit,
) {
    var confirmingReplacement by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    LaunchedEffect(picker.error, picker.constraintError) {
        if (picker.error) Toast.makeText(context, context.getString(when (picker.constraintError) {
            TodayDataError.RunningScheduleConflict -> R.string.planning_running_schedule_conflict
            TodayDataError.ProgrammeTimelineConflict -> R.string.planning_programme_timeline_conflict
            TodayDataError.ProgrammeConstraintsConflict -> R.string.planning_programme_constraints_conflict
            else -> if (picker.loadingError) R.string.plan_picker_load_error else R.string.plan_picker_activation_error
        }), Toast.LENGTH_SHORT).show()
    }
    val selected = picker.selected
    val recommendation = selected
    if (recommendation != null) {
        val template = recommendation.template
        PlanPage(
            title = stringResource(R.string.plan_details_title),
            onDismiss = { if (!picker.replacing) onSelect(null) },
            onDone = onDismiss,
            dismissEnabled = !picker.replacing,
            bottomActions = {
                FlowRow(
                    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedButton(onClick = { onSelect(null) }, enabled = !picker.replacing) { Text(stringResource(R.string.plan_picker_more)) }
                    Button(onClick = { if (hasActivePlan) confirmingReplacement = true else onUse(recommendation, false) }, enabled = !picker.replacing) {
                        if (picker.replacing) {
                            CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(8.dp))
                        }
                        Text(stringResource(R.string.plan_picker_use_this))
                    }
                }
            },
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(planRecommendationTitle(template["focus"]?.jsonPrimitive?.contentOrNull), Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text(template["subtitle"]?.jsonPrimitive?.contentOrNull.orEmpty(), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val singleColumn = maxWidth < 320.dp || LocalDensity.current.fontScale > 1.3f
                FlowRow(
                    maxItemsInEachRow = if (singleColumn) 1 else 2,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    listOf(
                        stringResource(R.string.plan_picker_length) to stringResource(R.string.plan_picker_weeks, recommendation.durationWeeks),
                        stringResource(R.string.plan_picker_rhythm) to stringResource(R.string.plan_picker_weekly_sessions, recommendation.sessionsPerWeek),
                        stringResource(R.string.plan_picker_target_time) to stringResource(R.string.plan_picker_minutes, recommendation.targetWeeklyMinutes),
                        stringResource(R.string.plan_picker_long_day) to stringResource(R.string.plan_picker_minutes, recommendation.longSessionMinutes),
                    ).forEach { (label, value) -> RecommendationStat(Modifier.weight(1f), label, value) }
                }
            }
            val isCurated = template["source"]?.jsonObject?.get("name")?.jsonPrimitive?.contentOrNull == "Plainstride plan standards"
            RecommendationDetailSection(stringResource(R.string.plan_picker_standard), stringResource(if (isCurated) R.string.plan_picker_curated_standard else R.string.plan_picker_standard_detail))
            RecommendationDetailSection(stringResource(R.string.plan_picker_why), recommendation.rationale)
            RecommendationDetailSection(stringResource(R.string.plan_picker_expect), template["summary"]?.jsonPrimitive?.contentOrNull.orEmpty())
            RecommendationDetailSection(stringResource(R.string.plan_picker_tradeoff), recommendation.tradeoff)
            (template["highlights"] as? JsonArray)?.takeIf { it.isNotEmpty() }?.let { highlights ->
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(stringResource(R.string.plan_picker_shape), style = MaterialTheme.typography.titleMedium)
                    highlights.forEach { item ->
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
                            Icon(Icons.Default.CheckCircle, null, Modifier.size(20.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(item.jsonPrimitive.contentOrNull.orEmpty(), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            (template["weeks"] as? JsonArray)?.take(2)?.takeIf { it.isNotEmpty() }?.let { weeks ->
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(stringResource(R.string.plan_picker_preview_title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    weeks.forEach { week ->
                        Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest), shape = RoundedCornerShape(18.dp)) {
                            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(
                                    stringResource(R.string.plan_picker_week_focus, week.jsonObject["index"]?.jsonPrimitive?.contentOrNull.orEmpty(), week.jsonObject["focus"]?.jsonPrimitive?.contentOrNull.orEmpty()),
                                    style = MaterialTheme.typography.titleSmall,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                Text(week.jsonObject["summary"]?.jsonPrimitive?.contentOrNull.orEmpty(), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                (week.jsonObject["workouts"] as? JsonArray)?.filter { (it.jsonObject["durationSeconds"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 0) > 0 }?.take(3)?.forEach { workout ->
                                    RecommendationWorkoutPreview(workout.jsonObject)
                                }
                            }
                        }
                    }
                }
            }
        }
    } else {
        PlanPage(
            title = stringResource(R.string.plan_picker_title),
            onDismiss = onDismiss,
            dismissEnabled = !picker.replacing,
            contentSpacing = 16.dp,
        ) {
            Card(
                onClick = onBuild,
                enabled = !picker.replacing,
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(20.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.55f)),
            ) {
                Row(Modifier.fillMaxWidth().padding(18.dp), horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.AutoAwesome, null, tint = MaterialTheme.colorScheme.primary)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(stringResource(R.string.plan_picker_build), style = MaterialTheme.typography.titleMedium)
                        Text(stringResource(R.string.plan_picker_build_detail), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Icon(Icons.Default.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (picker.loading && picker.recommendations.isEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) { CircularProgressIndicator(Modifier.size(20.dp)); Text(stringResource(R.string.plan_picker_loading), color = MaterialTheme.colorScheme.onSurfaceVariant) }
            if (picker.loading && picker.recommendations.isNotEmpty()) Text(stringResource(R.string.plan_picker_refreshing), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (picker.error) Text(stringResource(R.string.plan_picker_load_error), color = MaterialTheme.colorScheme.error)
            if (picker.loadingError) TextButton(onClick = onRetry) { Text(stringResource(R.string.today_retry)) }
            picker.recommendations.forEach { item ->
                Card(Modifier.fillMaxWidth().clickable(enabled = !picker.replacing) { onSelect(item) }, shape = RoundedCornerShape(20.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)) {
                    Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(planRecommendationTitle(item.template["focus"]?.jsonPrimitive?.contentOrNull), style = MaterialTheme.typography.titleMedium)
                        Text(item.template["subtitle"]?.jsonPrimitive?.contentOrNull.orEmpty(), style = MaterialTheme.typography.bodyLarge)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            listOf(stringResource(R.string.plan_picker_weeks, item.durationWeeks), stringResource(R.string.plan_picker_sessions, item.sessionsPerWeek), stringResource(R.string.plan_picker_minutes, item.targetWeeklyMinutes)).forEach { stat ->
                                Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surface) { Text(stat, Modifier.padding(horizontal = 12.dp, vertical = 8.dp), style = MaterialTheme.typography.bodySmall) }
                            }
                        }
                        val isCurated = item.template["source"]?.jsonObject?.get("name")?.jsonPrimitive?.contentOrNull == "Plainstride plan standards"
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.Verified, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                            Text(stringResource(if (isCurated) R.string.plan_picker_curated else R.string.plan_picker_reviewed), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                        }
                        (item.template["weeks"] as? JsonArray)?.firstOrNull()?.jsonObject?.get("summary")?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                        Text(item.rationale, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            OutlinedButton(onClick = { onSelect(item) }, enabled = !picker.replacing) { Text(stringResource(R.string.plan_picker_details)) }
                            Button(onClick = { if (hasActivePlan) { onSelect(item); confirmingReplacement = true } else onUse(item, false) }, enabled = !picker.replacing) { Text(stringResource(R.string.plan_picker_use)) }
                        }
                    }
                }
            }
            if (!picker.loading && picker.recommendations.isEmpty() && !picker.error) {
                Text(stringResource(R.string.plan_picker_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    if (confirmingReplacement && recommendation != null) AlertDialog(
        onDismissRequest = { confirmingReplacement = false },
        title = { Text(stringResource(R.string.plan_picker_replace_title)) },
        text = { Text(stringResource(R.string.plan_picker_replace_body)) },
        confirmButton = {
            TextButton(onClick = { confirmingReplacement = false; onUse(recommendation, true) }, enabled = !picker.replacing) {
                Text(stringResource(R.string.plan_picker_replace))
            }
        },
        dismissButton = { TextButton(onClick = { confirmingReplacement = false }) { Text(stringResource(R.string.today_cancel)) } },
    )
}

@Composable
private fun planRecommendationTitle(focus: String?): String = stringResource(when (focus) {
    "comeback" -> R.string.plan_picker_focus_comeback
    "fiveK" -> R.string.plan_picker_focus_5k
    "tenK" -> R.string.plan_picker_focus_10k
    "tenMile" -> R.string.plan_picker_focus_10mile
    "halfMarathon" -> R.string.plan_picker_focus_half
    "marathon" -> R.string.plan_picker_focus_marathon
    else -> R.string.plan_picker_focus_base
})

@Composable
private fun RecommendationDetailSection(title: String, detail: String) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, Modifier.semantics { heading() }, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Text(detail, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun RecommendationWorkoutPreview(workout: JsonObject) {
    val day = workout["dayLabel"]?.jsonPrimitive?.contentOrNull.orEmpty()
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        if (maxWidth < 320.dp || LocalDensity.current.fontScale > 1.3f) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(day, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                RecommendationWorkoutSummary(workout)
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                Text(day, Modifier.width(36.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                Column(Modifier.weight(1f)) { RecommendationWorkoutSummary(workout) }
            }
        }
    }
}

@Composable
private fun RecommendationWorkoutSummary(workout: JsonObject) {
    Text(workout["title"]?.jsonPrimitive?.contentOrNull.orEmpty(), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
    val minutes = ((workout["durationSeconds"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 0) + 59) / 60
    val effort = workout["intervalEffortLabel"]?.jsonPrimitive?.contentOrNull ?: workout["effortLabel"]?.jsonPrimitive?.contentOrNull.orEmpty()
    Text(
        if (effort.isBlank()) stringResource(R.string.plan_picker_preview_duration, minutes)
        else stringResource(R.string.plan_picker_preview_duration_effort, minutes, effort),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun RecommendationStat(modifier: Modifier, label: String, value: String) {
    Card(modifier, shape = RoundedCornerShape(18.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLowest)) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun CuratedWorkoutSheet(workouts: List<StandaloneWorkout>, onDismiss: () -> Unit, onChoose: (StandaloneWorkout) -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(R.string.today_choose_curated), style = MaterialTheme.typography.headlineSmall)
            if (workouts.isEmpty()) Text(stringResource(R.string.today_no_curated), color = MaterialTheme.colorScheme.onSurfaceVariant)
            workouts.forEach { workout -> OutlinedButton(onClick = { onChoose(workout) }, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text("${workout.title} · ${workout.durationLabel}") } }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun TodayTopControls(weather: WeatherGuidance?, useFahrenheit: Boolean, inboxCount: Int, onWeather: () -> Unit, onInbox: () -> Unit) {
    val inboxDescription = if (inboxCount > 0) stringResource(R.string.today_inbox_count, inboxCount) else stringResource(R.string.today_inbox)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Surface(onClick = onWeather, shape = CircleShape, color = MaterialTheme.colorScheme.surface, contentColor = MaterialTheme.colorScheme.primary, tonalElevation = 8.dp, shadowElevation = 6.dp) {
            Row(Modifier.heightIn(min = 48.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Cloud, null, Modifier.size(18.dp)); Spacer(Modifier.width(5.dp))
                Text(weather?.compactLabel(useFahrenheit) ?: stringResource(R.string.today_weather), style = MaterialTheme.typography.labelLarge, maxLines = 1)
            }
        }
        PlainstrideFloatingAction(onClick = onInbox) {
            Box {
                BadgedBox(badge = { if (inboxCount > 0) Badge(containerColor = MaterialTheme.colorScheme.error, contentColor = MaterialTheme.colorScheme.onError) { Text(inboxCount.coerceAtMost(99).toString()) } }) {
                    Icon(Icons.Default.Notifications, inboxDescription, Modifier.size(22.dp))
                }
            }
        }
    }
}

private fun WeatherGuidance.compactLabel(useFahrenheit: Boolean): String {
    val temperature = if (useFahrenheit) temperatureCelsius * 9 / 5 + 32 else temperatureCelsius
    val unit = if (useFahrenheit) "°F" else "°C"
    return listOfNotNull(placeName?.takeIf(String::isNotBlank), "${temperature.roundToInt()}$unit").joinToString(" ")
}

private fun Context.openAppLocationSettings() {
    startActivity(
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
    )
}

@Composable
private fun SelectedRouteCard(
    route: TodayRouteSelection,
    onChange: () -> Unit,
    onRemove: () -> Unit,
    onDirectionChanged: (Boolean) -> Unit,
) {
    val removeRouteLabel = stringResource(R.string.today_remove_route)
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = .96f))) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Route, null, tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(10.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(route.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(route.distanceLabel, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            TextButton(onClick = onChange) { Text(stringResource(R.string.today_change_route)) }
            IconButton(onClick = onRemove, modifier = Modifier.size(44.dp).semantics { contentDescription = removeRouteLabel }) {
                Icon(Icons.Default.Close, removeRouteLabel, tint = MaterialTheme.colorScheme.error)
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = !route.reverse, onClick = { onDirectionChanged(false) }, label = { Text(stringResource(R.string.today_route_as_saved)) })
            FilterChip(selected = route.reverse, onClick = { onDirectionChanged(true) }, label = { Text(stringResource(R.string.today_route_reverse)) })
        }
    }
}

@Composable
private fun ManualGoalCard(goal: TodayGoalChoice, racePlan: TodayRacePlan?, unitSystem: com.plainstride.outbound.core.model.activity.MeasurementUnitSystem, curatedWorkout: StandaloneWorkout?, distanceMeters: Double, durationSeconds: Long, calories: Int, caloriePlan: PlannedCalorieEstimate?, autoStopAtGoal: Boolean, onEdit: () -> Unit) {
    Card(onClick = onEdit, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = .96f))) {
        Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(when (goal) {
                TodayGoalChoice.CURATED -> curatedWorkout?.title ?: stringResource(goal.valueResource())
                TodayGoalChoice.RACE -> {
                    val distance = com.plainstride.outbound.core.model.activity.SessionFormatting.distance(racePlan?.distanceMeters ?: distanceMeters, unitSystem)
                    stringResource(R.string.race_distance_format, distance.value, if (unitSystem == com.plainstride.outbound.core.model.activity.MeasurementUnitSystem.metric) "km" else "mi") + " · " + (racePlan?.goalTimeSeconds?.let(::raceDuration) ?: stringResource(R.string.race_planner_start))
                }
                TodayGoalChoice.DISTANCE -> stringResource(R.string.today_distance_format, distanceMeters / 1_000)
                TodayGoalChoice.TIME -> stringResource(R.string.today_time_format, durationSeconds / 60)
                TodayGoalChoice.CALORIES -> stringResource(R.string.today_calories_format, calories)
                TodayGoalChoice.FREE -> stringResource(goal.valueResource())
            }, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            val pauseAtGoalEligible = autoStopAtGoal && goal in setOf(TodayGoalChoice.DISTANCE, TodayGoalChoice.TIME, TodayGoalChoice.CALORIES)
            val editHint = if (goal == TodayGoalChoice.RACE) stringResource(R.string.race_planner_tap_change) else if (goal == TodayGoalChoice.CALORIES && caloriePlan != null && !pauseAtGoalEligible) {
                "${stringResource(R.string.today_distance_format, caloriePlan.distanceMeters / 1_000)} · ${stringResource(R.string.today_time_format, caloriePlan.durationSeconds / 60)}"
            } else {
                ""
            }
            if (pauseAtGoalEligible) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.Pause, contentDescription = null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(4.dp))
                    Text(stringResource(R.string.today_stop_at_goal), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                }
            } else if (editHint.isNotEmpty()) {
                Text(editHint, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Icon(Icons.Default.ChevronRight, null)
        }
    }
}

@Composable
private fun GoalValueDialog(goal: TodayGoalChoice, distanceMeters: Double, durationSeconds: Long, calories: Int, autoStopAtGoal: Boolean, onDismiss: () -> Unit, onAutoStopAtGoalChanged: (Boolean) -> Unit, onDistance: (Double) -> Unit, onTime: (Long) -> Unit, onCalories: (Int) -> Unit) {
    var customValue by rememberSaveable(goal) { mutableStateOf("") }
    AlertDialog(onDismissRequest = onDismiss, title = {
        Row(
            // Own the full touch target so taps around the visual checkbox toggle exactly once.
            Modifier.fillMaxWidth().heightIn(min = 48.dp).toggleable(
                value = autoStopAtGoal,
                role = Role.Checkbox,
                onValueChange = onAutoStopAtGoalChanged,
            ),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(stringResource(R.string.today_stop_at_goal), modifier = Modifier.weight(1f))
            Checkbox(checked = autoStopAtGoal, onCheckedChange = null)
        }
    }, text = {
        Column(verticalArrangement=Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                when (goal) {
                    TodayGoalChoice.DISTANCE -> listOf(3_000.0, 5_000.0, 10_000.0).forEach { value -> OutlinedButton({ onDistance(value) }) { Text(stringResource(R.string.today_distance_format, value / 1_000), fontWeight = if (value == distanceMeters) FontWeight.Bold else FontWeight.Normal) } }
                    TodayGoalChoice.TIME -> listOf(1_200L, 1_800L, 2_700L).forEach { value -> OutlinedButton({ onTime(value) }) { Text(stringResource(R.string.today_time_format, value / 60), fontWeight = if (value == durationSeconds) FontWeight.Bold else FontWeight.Normal) } }
                    TodayGoalChoice.CALORIES -> listOf(200, 300, 500).forEach { value -> OutlinedButton({ onCalories(value) }) { Text(stringResource(R.string.today_calories_format, value), fontWeight = if (value == calories) FontWeight.Bold else FontWeight.Normal) } }
                    else -> Text(stringResource(R.string.today_goal_edit_hint))
                }
            }
            if(goal in setOf(TodayGoalChoice.DISTANCE,TodayGoalChoice.TIME,TodayGoalChoice.CALORIES)) OutlinedTextField(customValue,{customValue=it.filter{character->character.isDigit()||character=='.'}.take(7)},Modifier.fillMaxWidth(),singleLine=true,label={Text(stringResource(when(goal){TodayGoalChoice.DISTANCE->R.string.today_distance;TodayGoalChoice.TIME->R.string.today_time;else->R.string.today_calories}))},keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Decimal))
        }
    }, confirmButton = {
        val validCustomValue = when (goal) {
            TodayGoalChoice.DISTANCE -> customValue.toDoubleOrNull()?.let { it.isFinite() && it > 0 } == true
            TodayGoalChoice.TIME -> customValue.toLongOrNull()?.let { it > 0 } == true
            TodayGoalChoice.CALORIES -> customValue.toIntOrNull()?.let { it > 0 } == true
            else -> false
        }
        TextButton(
            onClick = {
                if (customValue.isBlank()) {
                    // Pause at goal is persisted when toggled, independently of target edits, like iOS.
                    onDismiss()
                } else {
                    when (goal) {
                        TodayGoalChoice.DISTANCE -> onDistance(customValue.toDouble() * 1_000)
                        TodayGoalChoice.TIME -> onTime(customValue.toLong() * 60)
                        TodayGoalChoice.CALORIES -> onCalories(customValue.toInt())
                        else -> onDismiss()
                    }
                }
            },
            enabled = customValue.isBlank() || validCustomValue,
        ) { Text(stringResource(R.string.today_done)) }
    }, dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.today_change)) } })
}

@Composable
private fun WorkoutRecommendationCard(
    suggestion: ActivitySuggestion,
    stale: Boolean,
    updatedAtEpochMs: Long?,
    completedToday: Boolean,
    recoveryChangeRecommended: Boolean,
    onRecoveryAdviceShown: () -> Unit,
    weather: WeatherGuidance?,
    minimized: Boolean,
    onToggleMinimized: () -> Unit,
    onOpen: () -> Unit,
    onChange: () -> Unit,
    onOpenPlan: (() -> Unit)? = null,
    warmupDuration: String? = null,
    onOpenWarmup: () -> Unit = {},
) {
    val toggleDescription = stringResource(if (minimized) R.string.today_expand_card else R.string.today_collapse_card)
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = .96f))) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f).clickable(role = Role.Button, onClick = onOpen)) {
                    Text(stringResource(if (completedToday) R.string.today_up_next else R.string.today_workout), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                    Text(suggestion.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                Text(stringResource(R.string.today_minutes, suggestion.durationMinutes), style = MaterialTheme.typography.titleSmall)
                TextButton(
                    onClick = onToggleMinimized,
                    modifier = Modifier.size(48.dp).semantics {
                        contentDescription = toggleDescription
                    },
                ) {
                    Text(if (minimized) "⌄" else "⌃", style = MaterialTheme.typography.titleLarge)
                }
            }
            if (recoveryChangeRecommended) {
                Text(stringResource(R.string.today_recovery_caution), style = MaterialTheme.typography.bodyMedium)
                TextButton(onClick = onChange, modifier = Modifier.heightIn(min = 48.dp)) {
                    Text(stringResource(R.string.today_change_workout))
                }
                LaunchedEffect(Unit) { onRecoveryAdviceShown() }
            }
            if (minimized && onOpenPlan != null) {
                TextButton(onClick = onOpenPlan, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                    Text(stringResource(R.string.plan_details_title))
                }
            }
            if (!minimized) {
                weather?.let {
                    Text("${it.headline} · ${it.detail}", style = MaterialTheme.typography.bodySmall, color = if (it.unsafe) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
                }
                PhasePreview(suggestion.steps)
                if (stale) Text(
                    stringResource(R.string.today_cached_at, updatedAtEpochMs?.let { DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(it)) }.orEmpty()),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.tertiary,
                )
                warmupDuration?.let { duration ->
                    val hint = stringResource(R.string.today_planned_warmup_hint)
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp)
                            .clickable(role = Role.Button, onClickLabel = hint, onClick = onOpenWarmup),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            stringResource(R.string.today_planned_warmup_title),
                            modifier = Modifier.weight(1f),
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.primary,
                        )
                        Text(duration, style = MaterialTheme.typography.labelMedium.copy(fontFeatureSettings = "tnum"))
                        Icon(Icons.Default.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                    }
                }
                HorizontalDivider()
                Row(Modifier.fillMaxWidth()) {
                    TextButton(onClick = onOpenPlan ?: onOpen, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) {
                        Icon(Icons.Default.CalendarMonth, null)
                        Spacer(Modifier.width(6.dp))
                        Text(stringResource(if (onOpenPlan != null) R.string.plan_details_title else R.string.today_details))
                    }
                    TextButton(onClick = onChange, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) {
                        Icon(Icons.Default.Edit, null)
                        Spacer(Modifier.width(6.dp))
                        Text(stringResource(R.string.today_change))
                    }
                }
            }
        }
    }
}

@Composable
private fun PhasePreview(steps: List<String>) {
    if (steps.isEmpty()) return
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        steps.forEachIndexed { index, step ->
            Box(
                Modifier.width(92.dp).height(38.dp).clip(RoundedCornerShape(9.dp))
                    .background(if (index % 2 == 0) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.secondaryContainer)
                    .semantics { contentDescription = step },
                contentAlignment = Alignment.Center,
            ) { Text(step, Modifier.padding(horizontal = 6.dp), style = MaterialTheme.typography.labelSmall, maxLines = 2, overflow = TextOverflow.Ellipsis) }
        }
    }
}

@Composable
private fun ActivityLaunchDock(
    suggestion: ActivitySuggestion?,
    activeSession: Boolean,
    completedToday: Boolean,
    activityChoice: TodayActivityChoice,
    goalChoice: TodayGoalChoice,
    indoor: Boolean,
    voiceGuideEnabled: Boolean,
    aiCoachEnabled: Boolean,
    companionType: com.plainstride.outbound.core.model.activity.ActivityCompanionType?,
    onActivityChoice: (TodayActivityChoice) -> Unit,
    onGoalChoice: (TodayGoalChoice) -> Unit,
    onIndoorChanged: (Boolean) -> Unit,
    onVoiceGuideChanged: (Boolean) -> Unit,
    onAICoachChanged: (Boolean) -> Unit,
    onCompanionChanged: (Boolean) -> Unit,
    onReturnToSession: () -> Unit,
    onOpenDetails: () -> Unit,
    shoes: List<TodayShoeOption>,
    selectedShoeId: String?,
    onSelectShoe: (TodayShoeOption) -> Unit,
    onAddShoe: () -> Unit,
    onOpenLiveTrack: () -> Unit,
    cheerRecipientsSelected: Boolean = false,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(0.dp)) {
        if (activityChoice != TodayActivityChoice.PLANNED) {
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TodayGoalChoice.entries.filter { it != TodayGoalChoice.RACE || activityChoice == TodayActivityChoice.RUN }.filter { it != TodayGoalChoice.CALORIES || activityChoice == TodayActivityChoice.RUN || activityChoice == TodayActivityChoice.WALK }.forEach { choice ->
                    GoalPill(stringResource(choice.labelResource()), choice == goalChoice) { onGoalChoice(choice) }
                }
            }
        }
        Surface(color = MaterialTheme.colorScheme.surface.copy(alpha = .98f), tonalElevation = 8.dp) {
        Column(Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TodayActivityChoice.entries.forEach { choice ->
                    ChoiceButton(stringResource(choice.labelResource()), choice.icon(), choice == activityChoice) { onActivityChoice(choice) }
                }
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                UtilityButton(stringResource(R.string.today_voice), onClick = { onVoiceGuideChanged(!voiceGuideEnabled) }, selected = voiceGuideEnabled, toggle = true)
                if (activityChoice == TodayActivityChoice.RUN ||
                    (activityChoice == TodayActivityChoice.PLANNED && (suggestion == null || suggestion.modality == Modality.run))) {
                    UtilityButton(stringResource(R.string.today_ai_coach), onClick = { onAICoachChanged(!aiCoachEnabled) }, selected = aiCoachEnabled, toggle = true)
                }
                if (activityChoice.isCompanionEligible(suggestion)) {
                    UtilityButton(
                        label = stringResource(R.string.today_companion_dog_title),
                        onClick = { onCompanionChanged(companionType == null) },
                        selected = companionType != null,
                    )
                }
                UtilityButton(stringResource(R.string.today_cheer), onClick = onOpenLiveTrack, selected = cheerRecipientsSelected)
                TodayShoePicker(shoes, selectedShoeId, onSelectShoe, onAddShoe)
                UtilityButton(stringResource(if (indoor) R.string.today_indoor else R.string.today_outdoor), onClick = { onIndoorChanged(!indoor) }, selected = true)
            }
            when {
                activeSession -> Unit
                completedToday -> {
                    Text(stringResource(R.string.today_completed_reflection), Modifier.padding(horizontal = 16.dp), style = MaterialTheme.typography.titleMedium)
                    OutlinedButton(onClick = onOpenDetails, enabled = suggestion != null, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).heightIn(min = 52.dp)) {
                        Icon(Icons.Default.CalendarMonth, null)
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.today_view_next))
                    }
                }
                else -> Unit
            }
        }
    }
    }
}

@Composable
private fun ChoiceButton(label: String, icon: ImageVector, selected: Boolean, onClick: () -> Unit) {
    Surface(
        onClick = onClick,
        modifier = Modifier.size(52.dp).semantics {
            contentDescription = label
            role = Role.RadioButton
            this.selected = selected
        },
        shape = CircleShape,
        color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun GoalPill(label: String, selected: Boolean, onClick: () -> Unit) {
    Surface(onClick = onClick, shape = CircleShape, color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surface) {
        Text(label, Modifier.padding(horizontal = 18.dp, vertical = 12.dp), color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.labelLarge)
    }
}

@Composable
private fun UtilityButton(label: String, onClick: () -> Unit, selected: Boolean = false, toggle: Boolean = false) {
    Surface(
        onClick = onClick,
        modifier = Modifier.heightIn(min = 48.dp).semantics {
            if (toggle) {
                role = Role.Switch
                toggleableState = androidx.compose.ui.state.ToggleableState(selected)
            }
        },
        shape = CircleShape,
        color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Text(
            label,
            Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface,
            style = MaterialTheme.typography.labelLarge,
            maxLines = 1,
        )
    }
}

@Composable
private fun TodayShoePicker(
    shoes: List<TodayShoeOption>,
    selectedShoeId: String?,
    onSelectShoe: (TodayShoeOption) -> Unit,
    onAddShoe: () -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val selected = shoes.firstOrNull { it.id == selectedShoeId }
    val selectedValue = selected?.displayName.orEmpty()
    val orderedShoes = remember(shoes, selectedShoeId) { shoes.sortedByDescending { it.id == selectedShoeId } }
    Box {
        Surface(
            modifier = Modifier.semantics { stateDescription = selectedValue },
            onClick = { if (orderedShoes.isEmpty()) onAddShoe() else expanded = true },
            shape = CircleShape,
            color = if (selected != null) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
        ) {
            Text(
                stringResource(R.string.today_shoes),
                Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                color = if (selected != null) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface,
                style = MaterialTheme.typography.labelLarge,
                maxLines = 1,
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            orderedShoes.forEach { shoe ->
                DropdownMenuItem(
                    text = { Text(shoe.displayName) },
                    leadingIcon = if (shoe.id == selectedShoeId) ({ Icon(Icons.Default.Check, null) }) else null,
                    onClick = { onSelectShoe(shoe); expanded = false },
                )
            }
            if (orderedShoes.isNotEmpty()) HorizontalDivider()
            DropdownMenuItem(
                text = { Text(stringResource(R.string.today_shoes_new)) },
                leadingIcon = { Icon(Icons.Default.Add, null) },
                onClick = { expanded = false; onAddShoe() },
            )
        }
    }
}

private fun TodayActivityChoice.isCompanionEligible(suggestion: ActivitySuggestion?): Boolean = when (this) {
    TodayActivityChoice.PLANNED -> suggestion?.modality in setOf(Modality.run, Modality.walk, Modality.bike)
    else -> com.plainstride.outbound.core.model.activity.ActivityCompanionType.isEligibleFor(toActivityType())
}

private fun TodayActivityChoice.icon(): ImageVector = when (this) {
    TodayActivityChoice.PLANNED -> Icons.Default.Checklist
    TodayActivityChoice.RUN -> Icons.Default.DirectionsRun
    TodayActivityChoice.WALK -> Icons.Default.DirectionsWalk
    TodayActivityChoice.HIKE -> Icons.Default.Hiking
    TodayActivityChoice.BIKE -> Icons.Default.DirectionsBike
}

private fun TodayActivityChoice.catalogSportNames(): Set<String> = when (this) {
    TodayActivityChoice.PLANNED -> emptySet()
    TodayActivityChoice.RUN -> setOf("run", "running")
    TodayActivityChoice.WALK -> setOf("walk", "walking")
    TodayActivityChoice.HIKE -> setOf("hike", "hiking")
    TodayActivityChoice.BIKE -> setOf("bike", "biking", "cycle", "cycling")
}

private fun TodayActivityChoice.toActivityType(): com.plainstride.outbound.core.model.activity.ActivityType = when (this) {
    // PLANNED resolves through the plan; the companion control is never shown for it.
    TodayActivityChoice.PLANNED, TodayActivityChoice.RUN -> com.plainstride.outbound.core.model.activity.ActivityType.running
    TodayActivityChoice.WALK -> com.plainstride.outbound.core.model.activity.ActivityType.walking
    TodayActivityChoice.HIKE -> com.plainstride.outbound.core.model.activity.ActivityType.hiking
    TodayActivityChoice.BIKE -> com.plainstride.outbound.core.model.activity.ActivityType.cycling
}

private fun TodayActivityChoice.labelResource() = when (this) {
    TodayActivityChoice.PLANNED -> R.string.today_planned
    TodayActivityChoice.RUN -> R.string.today_run
    TodayActivityChoice.WALK -> R.string.today_walk
    TodayActivityChoice.HIKE -> R.string.today_hike
    TodayActivityChoice.BIKE -> R.string.today_bike
}

private fun TodayGoalChoice.labelResource() = when (this) {
    TodayGoalChoice.RACE -> R.string.race_planner_mode
    TodayGoalChoice.CURATED -> R.string.today_curated
    TodayGoalChoice.FREE -> R.string.today_free
    TodayGoalChoice.DISTANCE -> R.string.today_distance
    TodayGoalChoice.TIME -> R.string.today_time
    TodayGoalChoice.CALORIES -> R.string.today_calories
}

private fun TodayGoalChoice.valueResource() = when (this) {
    TodayGoalChoice.RACE -> R.string.race_planner_mode
    TodayGoalChoice.CURATED -> R.string.today_curated_value
    TodayGoalChoice.FREE -> R.string.today_free
    TodayGoalChoice.DISTANCE -> R.string.today_distance_value
    TodayGoalChoice.TIME -> R.string.today_time_value
    TodayGoalChoice.CALORIES -> R.string.today_calories_value
}

@Composable
private fun NoSuggestionCard(noPlan: Boolean, onStartFreestyle: () -> Unit, onSetUpPlan: () -> Unit, onRefresh: () -> Unit) {
    OutlinedCard {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(if (noPlan) R.string.today_no_plan else R.string.today_offline_title), style = MaterialTheme.typography.titleLarge)
            Text(stringResource(if (noPlan) R.string.today_no_plan_body else R.string.today_offline_body), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick = onStartFreestyle, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text(stringResource(R.string.today_freestyle)) }
            if (noPlan) TextButton(onClick = onSetUpPlan) { Text(stringResource(R.string.today_set_up_plan)) }
            else TextButton(onClick = onRefresh) { Text(stringResource(R.string.today_retry)) }
        }
    }
}

@Composable
private fun TodaySkeleton() {
    Card {
        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            repeat(3) { index -> Spacer(Modifier.fillMaxWidth(if (index == 1) .72f else 1f).height(if (index == 0) 24.dp else 18.dp).clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.surfaceVariant)) }
        }
    }
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun ChangeWorkoutSheet(
    original: ActivitySuggestion,
    pending: AdjustmentProposal?,
    busy: Boolean,
    onDismiss: () -> Unit,
    onApply: (TodayConstraint, String?, Int) -> Unit,
    onDecision: (String, Boolean) -> Unit,
) {
    var selectedConstraint by rememberSaveable { mutableStateOf<TodayConstraint?>(null) }
    var note by rememberSaveable { mutableStateOf("") }
    var availableMinutes by rememberSaveable { mutableStateOf(15) }
    val focusManager = LocalFocusManager.current
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        BoxWithConstraints(Modifier.fillMaxWidth().fillMaxHeight(.85f)) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min = maxHeight).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.today_change_title), Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
                    TextButton(onClick = onDismiss) { Text(stringResource(R.string.today_change_close)) }
                }
                val reason = selectedConstraint
                when {
                    pending != null -> {
                        Text(stringResource(R.string.today_recommendation), Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall)
                        Text(pending.explanation, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                        pending.changes.forEach { change ->
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(change.beforeTitle, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textDecoration = TextDecoration.LineThrough)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Default.Sync, contentDescription = null)
                                    Text(change.afterTitle, style = MaterialTheme.typography.titleSmall)
                                }
                            }
                        }
                        Spacer(Modifier.weight(1f).heightIn(min = 24.dp))
                        Button(onClick = { onDecision(pending.id, true) }, enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                            Icon(Icons.Default.Check, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.today_apply_change))
                        }
                        TextButton(onClick = { onDecision(pending.id, false) }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.today_change_keep_plan)) }
                    }
                    reason != null -> {
                        Text(stringResource(reason.headingResource()), Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall)
                        Text(stringResource(reason.recommendationResource()), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                        if (reason == TodayConstraint.LimitedTime) {
                            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                                listOf(10, 15, 20).forEachIndexed { index, minutes ->
                                    SegmentedButton(
                                        selected = availableMinutes == minutes,
                                        onClick = { availableMinutes = minutes },
                                        shape = SegmentedButtonDefaults.itemShape(index, 3),
                                        modifier = Modifier.heightIn(min = 48.dp),
                                    ) { Text(stringResource(R.string.today_minutes, minutes)) }
                                }
                            }
                        }
                        OutlinedTextField(note, { note = it }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.today_optional_note)) }, minLines = 2, maxLines = 3)
                        Spacer(Modifier.weight(1f).heightIn(min = 24.dp))
                        Button(onClick = {
                            focusManager.clearFocus()
                            onApply(reason, note.trim().takeIf(String::isNotEmpty), if (reason == TodayConstraint.LimitedTime) availableMinutes else 15)
                        }, enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                            Icon(Icons.Default.Check, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text(stringResource(R.string.today_change_start_action))
                        }
                        TextButton(onClick = onDismiss, Modifier.fillMaxWidth()) { Text(stringResource(R.string.today_keep_original)) }
                    }
                    else -> {
                        Text(stringResource(R.string.today_change_body), Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall)
                        Text(stringResource(R.string.today_change_original, original.title, original.durationMinutes), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                        listOf(TodayConstraint.LimitedTime, TodayConstraint.LowEnergy, TodayConstraint.Soreness).forEach { choice ->
                            OutlinedButton(onClick = { selectedConstraint = choice }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) {
                                Icon(when (choice) {
                                    TodayConstraint.LimitedTime -> Icons.Default.AccessTime
                                    TodayConstraint.LowEnergy -> Icons.Default.Battery2Bar
                                    TodayConstraint.Soreness -> Icons.Default.Healing
                                }, contentDescription = null)
                                Spacer(Modifier.width(8.dp))
                                Text(stringResource(choice.labelResource()), Modifier.weight(1f))
                                Icon(Icons.Default.ChevronRight, contentDescription = null)
                            }
                        }
                    }
                }
                Spacer(Modifier.height(20.dp))
            }
        }
    }
}

private fun TodayConstraint.labelResource() = when (this) {
    TodayConstraint.LowEnergy -> R.string.today_low_energy
    TodayConstraint.Soreness -> R.string.today_soreness
    TodayConstraint.LimitedTime -> R.string.today_limited_time
}

private fun TodayConstraint.headingResource() = when (this) {
    TodayConstraint.LowEnergy -> R.string.today_change_energy_heading
    TodayConstraint.Soreness -> R.string.today_change_rest_heading
    TodayConstraint.LimitedTime -> R.string.today_change_time_heading
}

private fun TodayConstraint.recommendationResource() = when (this) {
    TodayConstraint.LowEnergy -> R.string.today_change_energy_body
    TodayConstraint.Soreness -> R.string.today_change_rest_body
    TodayConstraint.LimitedTime -> R.string.today_change_time_body
}
