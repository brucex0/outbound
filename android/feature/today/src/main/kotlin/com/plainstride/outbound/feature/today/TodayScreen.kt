package com.plainstride.outbound.feature.today

import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Autorenew
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Checklist
import androidx.compose.material.icons.filled.DirectionsBike
import androidx.compose.material.icons.filled.DirectionsRun
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Hiking
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Speaker
import androidx.compose.material.icons.filled.SpeakerNotesOff
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material.icons.filled.HomeWork
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Mail
import androidx.compose.material.icons.filled.Notifications
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
import android.Manifest
import android.graphics.Bitmap
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.text.DateFormat
import java.util.Date
import kotlin.math.roundToInt
import com.plainstride.outbound.core.model.ActivitySuggestion
import com.plainstride.outbound.core.model.AdjustmentProposal
import com.plainstride.outbound.core.model.StandaloneWorkout
import com.plainstride.outbound.core.designsystem.PlainstrideRouteMap
import com.plainstride.outbound.core.designsystem.PlainstrideFloatingAction
import com.plainstride.outbound.core.model.activity.PlannedCalorieEstimate

enum class TodayActivityChoice { PLANNED, RUN, WALK, HIKE, BIKE }
enum class TodayGoalChoice { CURATED, FREE, DISTANCE, TIME, CALORIES }

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
)
data class TodayLaunchOptions(val indoor: Boolean, val voiceGuideEnabled: Boolean)

@Composable
fun TodayRoute(
    accountId: String,
    localeTag: String,
    viewModel: TodayViewModel,
    activeSession: Boolean,
    completedToday: Boolean,
    onStartWorkout: (WorkoutLaunchIntent, TodayLaunchOptions) -> Unit,
    onStartFreestyle: () -> Unit,
    onReturnToSession: () -> Unit,
    onSetUpPlan: () -> Unit,
    onStartManual: (TodayManualLaunch) -> Unit,
    onOpenMusic: () -> Unit,
    onOpenLiveTrack: () -> Unit,
    onOpenShoes: () -> Unit,
    onOpenInbox: () -> Unit,
    onFindRoute: () -> Unit,
    useFahrenheit: Boolean,
    inboxCount: Int,
    onMessage: suspend (TodayMessage) -> Unit,
    initialWorkoutId: String? = null,
    guidanceContent: @Composable () -> Unit = {},
    startRequest: Int = 0,
    refreshRequest: Int = 0,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    LaunchedEffect(accountId, localeTag) { viewModel.configure(accountId, localeTag) }
    LaunchedEffect(refreshRequest) { if (refreshRequest > 0) viewModel.refresh() }
    val state by viewModel.state.collectAsStateWithLifecycle()
    val weather by viewModel.weather.collectAsStateWithLifecycle()
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        viewModel.refreshWeather()
    }
    LaunchedEffect(activeSession, completedToday) { viewModel.updateSessionState(activeSession, completedToday) }
    LaunchedEffect(viewModel) {
        viewModel.weatherPermissionRequests.collect {
            permissionLauncher.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
    }
    LaunchedEffect(viewModel) { viewModel.messages.collect(onMessage) }
    TodayScreen(
        state = state,
        weather = weather,
        onRefresh = viewModel::refresh,
        onStart = { suggestion, source, options ->
            viewModel.trackWorkoutStarted(source)
            onStartWorkout(viewModel.launchIntent(suggestion, source), options)
        },
        onStartFreestyle = onStartFreestyle,
        onReturnToSession = onReturnToSession,
        onSetUpPlan = onSetUpPlan,
        onStartManual = { setup -> viewModel.trackManualWorkoutStarted(setup.activity, setup.goal); onStartManual(setup) },
        onOpenMusic = onOpenMusic,
        onOpenLiveTrack = onOpenLiveTrack,
        onOpenShoes = onOpenShoes,
        onOpenInbox = onOpenInbox,
        onFindRoute = onFindRoute,
        useFahrenheit = useFahrenheit,
        inboxCount = inboxCount,
        onSubmitConstraint = viewModel::submitConstraint,
        onDecideAdjustment = viewModel::decideAdjustment,
        onCardDisplayChanged = viewModel::trackCardDisplayChanged,
        onLaunchConfigurationChanged = viewModel::trackLaunchConfiguration,
        calorieEstimate = viewModel::calorieEstimate,
        guidanceContent = guidanceContent,
        startRequest = startRequest,
        initialWorkoutId = initialWorkoutId,
        locationGranted = context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED,
        modifier = modifier,
    )
}

@Composable
fun TodayScreen(
    state: TodayUiState,
    weather: WeatherGuidance?,
    onRefresh: () -> Unit,
    onStart: (ActivitySuggestion, String, TodayLaunchOptions) -> Unit,
    onStartFreestyle: () -> Unit,
    onReturnToSession: () -> Unit,
    onSetUpPlan: () -> Unit,
    onStartManual: (TodayManualLaunch) -> Unit = {},
    onOpenMusic: () -> Unit = {},
    onOpenLiveTrack: () -> Unit = {},
    onOpenShoes: () -> Unit = {},
    onOpenInbox: () -> Unit = {},
    onFindRoute: () -> Unit = {},
    useFahrenheit: Boolean = false,
    inboxCount: Int = 0,
    onSubmitConstraint: (TodayConstraint, String, String?) -> Unit,
    onDecideAdjustment: (String, Boolean) -> Unit,
    onCardDisplayChanged: (Boolean) -> Unit = {},
    onLaunchConfigurationChanged: (String, String) -> Unit = { _, _ -> },
    calorieEstimate:suspend (TodayActivityChoice,Int)->PlannedCalorieEstimate?={_,_->null},
    guidanceContent: @Composable () -> Unit = {},
    startRequest: Int = 0,
    initialWorkoutId: String? = null,
    locationGranted: Boolean = false,
    modifier: Modifier = Modifier,
) {
    var showsDetail by rememberSaveable { mutableStateOf(false) }
    var showsChange by rememberSaveable { mutableStateOf(false) }
    var showsWeather by rememberSaveable { mutableStateOf(false) }
    var showsCatalog by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    val displayPreferences = remember(context) { context.getSharedPreferences("today_display", android.content.Context.MODE_PRIVATE) }
    var cardMinimized by rememberSaveable { mutableStateOf(displayPreferences.getBoolean("planned_workout_minimized", true)) }
    var activityChoice by rememberSaveable { mutableStateOf(TodayActivityChoice.PLANNED) }
    var goalChoice by rememberSaveable { mutableStateOf(TodayGoalChoice.FREE) }
    var indoor by rememberSaveable { mutableStateOf(false) }
    var voiceGuideEnabled by rememberSaveable { mutableStateOf(true) }
    var curatedWorkout by remember { mutableStateOf<StandaloneWorkout?>(null) }
    var distanceMeters by rememberSaveable { mutableStateOf(5_000.0) }
    var durationSeconds by rememberSaveable { mutableStateOf(1_800L) }
    var calories by rememberSaveable { mutableStateOf(300) }
    var caloriePlan by remember { mutableStateOf<PlannedCalorieEstimate?>(null) }
    var editingGoal by rememberSaveable { mutableStateOf(false) }
    var overflowExpanded by rememberSaveable { mutableStateOf(false) }
    var handledStartRequest by rememberSaveable { mutableStateOf(startRequest) }
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
    val launchPreparedActivity = {
        if (activityChoice == TodayActivityChoice.PLANNED) {
            suggestion?.let { onStart(it, "today_planned", TodayLaunchOptions(indoor, voiceGuideEnabled)) }
                ?: onStartFreestyle()
        } else {
            val catalogVersion = (state.catalog as? CachedResource.Available)?.value?.version
            onStartManual(TodayManualLaunch(activityChoice, goalChoice, distanceMeters, durationSeconds, calories, indoor, voiceGuideEnabled, curatedWorkout, catalogVersion))
        }
    }
    LaunchedEffect(startRequest) {
        if (startRequest != handledStartRequest) {
            handledStartRequest = startRequest
            if (!state.activeSession) launchPreparedActivity()
        }
    }
    LaunchedEffect(initialWorkoutId, suggestion?.id, suggestion?.plannedWorkoutId) {
        if (initialWorkoutId != null && (suggestion?.id == initialWorkoutId || suggestion?.plannedWorkoutId == initialWorkoutId)) showsDetail = true
    }

    Box(modifier.fillMaxSize()) {
        PlainstrideRouteMap(
            points = emptyList(),
            modifier = Modifier.fillMaxSize(),
            showUserLocation = locationGranted,
            preciseLocationGranted = locationGranted,
            focusOnUser = true,
        )
        Column(Modifier.fillMaxSize()) {
            Box(Modifier.fillMaxWidth().weight(1f)) {
            Row(Modifier.align(Alignment.TopEnd).padding(16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                TodayTopControls(weather, useFahrenheit, inboxCount, { if (weather != null) showsWeather = true }, onOpenInbox)
                Box {
                    PlainstrideFloatingAction(onClick = { overflowExpanded = true }) {
                        setupPhoto?.let { Image(it.asImageBitmap(), stringResource(R.string.today_more), Modifier.size(48.dp).clip(CircleShape)) }
                            ?: Icon(Icons.Default.MoreVert, stringResource(R.string.today_more), Modifier.size(22.dp))
                    }
                    DropdownMenu(overflowExpanded, { overflowExpanded = false }) {
                        DropdownMenuItem({ Text(stringResource(R.string.today_take_photo)) }, { overflowExpanded = false; photoLauncher.launch(null) }, leadingIcon = { Icon(Icons.Default.PhotoCamera, null) })
                        DropdownMenuItem({ Text(stringResource(R.string.today_find_route)) }, { overflowExpanded = false; onFindRoute() }, leadingIcon = { Icon(Icons.Default.Route, null) })
                    }
                }
            }
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                when {
                    state.suggestion is CachedResource.Loading && state.refreshError == null -> TodaySkeleton()
                    suggestion != null && activityChoice == TodayActivityChoice.PLANNED -> WorkoutRecommendationCard(
                        suggestion = suggestion,
                        stale = state.isStale,
                        updatedAtEpochMs = state.suggestionUpdatedAtEpochMs,
                        completedToday = state.completedToday,
                        weather = weather,
                        minimized = cardMinimized,
                        onToggleMinimized = {
                            cardMinimized = !cardMinimized
                            displayPreferences.edit().putBoolean("planned_workout_minimized", cardMinimized).apply()
                            onCardDisplayChanged(cardMinimized)
                        },
                        onOpen = { showsDetail = true },
                        onChange = { showsChange = true },
                    )
                    state.hasNoCachedSuggestion -> NoSuggestionCard(
                        noPlan = (state.planning as? CachedResource.Available)?.value?.plan == null,
                        onStartFreestyle = onStartFreestyle,
                        onSetUpPlan = onSetUpPlan,
                        onRefresh = onRefresh,
                    )
                }
                if (activityChoice != TodayActivityChoice.PLANNED && goalChoice != TodayGoalChoice.FREE) {
                    ManualGoalCard(activityChoice, goalChoice, curatedWorkout, distanceMeters, durationSeconds, calories,caloriePlan) {
                        if (goalChoice == TodayGoalChoice.CURATED) showsCatalog = true else editingGoal = true
                    }
                }
                guidanceContent()
                if (state.refreshing) Surface(shape = RoundedCornerShape(20.dp), tonalElevation = 3.dp) {
                    Row(Modifier.padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(8.dp))
                        Text(stringResource(R.string.today_updating), style = MaterialTheme.typography.labelLarge)
                    }
                }
            }
            }
            ActivityLaunchDock(
                suggestion = suggestion,
                activeSession = state.activeSession,
                completedToday = state.completedToday,
                activityChoice = activityChoice,
                goalChoice = goalChoice,
                indoor = indoor,
                voiceGuideEnabled = voiceGuideEnabled,
                onActivityChoice = { activityChoice = it; onLaunchConfigurationChanged("activity_type", it.name.lowercase()) },
                onGoalChoice = { goalChoice = it; if (it == TodayGoalChoice.CURATED) showsCatalog = true; onLaunchConfigurationChanged("goal", it.name.lowercase()) },
                onIndoorChanged = { indoor = it; onLaunchConfigurationChanged("environment", if (it) "indoor" else "outdoor") },
                onVoiceGuideChanged = { voiceGuideEnabled = it; onLaunchConfigurationChanged("voice_guide", if (it) "on" else "off") },
                onReturnToSession = onReturnToSession,
                onOpenDetails = { showsDetail = true },
                onOpenMusic = onOpenMusic,
                onOpenLiveTrack = onOpenLiveTrack,
                onOpenShoes = onOpenShoes,
            )
        }
    }

    if (showsDetail && suggestion != null) WorkoutDetailSheet(
        suggestion,
        onDismiss = { showsDetail = false },
        onStart = { showsDetail = false; onStart(suggestion, "today_detail", TodayLaunchOptions(indoor, voiceGuideEnabled)) },
    )
    if (showsChange && suggestion != null) ChangeWorkoutSheet(
        original = suggestion,
        pending = state.pendingAdjustment,
        busy = state.mutationInFlight,
        onDismiss = { showsChange = false },
        onSubmit = onSubmitConstraint,
        onDecision = { id, accept -> onDecideAdjustment(id, accept); showsChange = false },
    )
    if (showsWeather && weather != null) AlertDialog(
        onDismissRequest = { showsWeather = false },
        title = { Text(weather.headline) },
        text = { Text(weather.detail) },
        confirmButton = { TextButton(onClick = { showsWeather = false }) { Text(stringResource(R.string.today_done)) } },
    )
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
    if (editingGoal) GoalValueDialog(goalChoice, distanceMeters, durationSeconds, calories, { editingGoal = false },
        { distanceMeters = it; editingGoal = false; onLaunchConfigurationChanged("goal_value", "preset") },
        { durationSeconds = it; editingGoal = false; onLaunchConfigurationChanged("goal_value", "preset") },
        { calories = it; editingGoal = false; onLaunchConfigurationChanged("goal_value", "preset") })
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
        Surface(onClick = onWeather, shape = CircleShape, color = MaterialTheme.colorScheme.surface, tonalElevation = 8.dp, shadowElevation = 6.dp) {
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

@Composable
private fun ManualGoalCard(activity: TodayActivityChoice, goal: TodayGoalChoice, curatedWorkout: StandaloneWorkout?, distanceMeters: Double, durationSeconds: Long, calories: Int, caloriePlan: PlannedCalorieEstimate?, onEdit: () -> Unit) {
    Card(onClick = onEdit, colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = .96f))) {
        Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(stringResource(activity.labelResource()), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
            Text(when (goal) {
                TodayGoalChoice.CURATED -> curatedWorkout?.title ?: stringResource(goal.valueResource())
                TodayGoalChoice.DISTANCE -> stringResource(R.string.today_distance_format, distanceMeters / 1_000)
                TodayGoalChoice.TIME -> stringResource(R.string.today_time_format, durationSeconds / 60)
                TodayGoalChoice.CALORIES -> stringResource(R.string.today_calories_format, calories)
                TodayGoalChoice.FREE -> stringResource(goal.valueResource())
            }, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            val editHint = if (goal == TodayGoalChoice.CALORIES && caloriePlan != null) {
                "${stringResource(R.string.today_distance_format, caloriePlan.distanceMeters / 1_000)} · ${stringResource(R.string.today_time_format, caloriePlan.durationSeconds / 60)}"
            } else {
                stringResource(R.string.today_goal_edit_hint)
            }
            Text(editHint, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Icon(Icons.Default.ChevronRight, null)
        }
    }
}

@Composable
private fun GoalValueDialog(goal: TodayGoalChoice, distanceMeters: Double, durationSeconds: Long, calories: Int, onDismiss: () -> Unit, onDistance: (Double) -> Unit, onTime: (Long) -> Unit, onCalories: (Int) -> Unit) {
    var customValue by rememberSaveable(goal) { mutableStateOf("") }
    AlertDialog(onDismissRequest = onDismiss, title = { Text(stringResource(R.string.today_change_goal)) }, text = {
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
    }, confirmButton = { TextButton(onClick={when(goal){TodayGoalChoice.DISTANCE->customValue.toDoubleOrNull()?.takeIf{it>0}?.let{onDistance(it*1_000)};TodayGoalChoice.TIME->customValue.toLongOrNull()?.takeIf{it>0}?.let{onTime(it*60)};TodayGoalChoice.CALORIES->customValue.toIntOrNull()?.takeIf{it>0}?.let(onCalories);else->onDismiss()}},enabled=customValue.toDoubleOrNull()?.let{it>0}==true){Text(stringResource(R.string.today_done))} }, dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.today_change)) } })
}

@Composable
private fun WorkoutRecommendationCard(
    suggestion: ActivitySuggestion,
    stale: Boolean,
    updatedAtEpochMs: Long?,
    completedToday: Boolean,
    weather: WeatherGuidance?,
    minimized: Boolean,
    onToggleMinimized: () -> Unit,
    onOpen: () -> Unit,
    onChange: () -> Unit,
) {
    val uriHandler = LocalUriHandler.current
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
            if (!minimized) {
                weather?.let {
                    Text("${it.headline} · ${it.detail}", style = MaterialTheme.typography.bodySmall, color = if (it.unsafe) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(it.attribution, modifier = Modifier.clickable(role = Role.Button) { uriHandler.openUri(it.attributionUrl) }, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                }
                PhasePreview(suggestion.steps)
                if (stale) Text(
                    stringResource(R.string.today_cached_at, updatedAtEpochMs?.let { DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(it)) }.orEmpty()),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.tertiary,
                )
                HorizontalDivider()
                Row(Modifier.fillMaxWidth()) {
                    TextButton(onClick = onOpen, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) {
                        Icon(Icons.Default.CalendarMonth, null)
                        Spacer(Modifier.width(6.dp))
                        Text(stringResource(R.string.today_plan))
                    }
                    TextButton(onClick = onChange, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) {
                        Icon(Icons.Default.Autorenew, null)
                        Spacer(Modifier.width(6.dp))
                        Text(stringResource(R.string.today_change_plan))
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
    onActivityChoice: (TodayActivityChoice) -> Unit,
    onGoalChoice: (TodayGoalChoice) -> Unit,
    onIndoorChanged: (Boolean) -> Unit,
    onVoiceGuideChanged: (Boolean) -> Unit,
    onReturnToSession: () -> Unit,
    onOpenDetails: () -> Unit,
    onOpenMusic: () -> Unit,
    onOpenLiveTrack: () -> Unit,
    onOpenShoes: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(0.dp)) {
        if (activityChoice != TodayActivityChoice.PLANNED) {
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TodayGoalChoice.entries.filter { it != TodayGoalChoice.CALORIES || activityChoice == TodayActivityChoice.RUN || activityChoice == TodayActivityChoice.WALK }.forEach { choice ->
                    GoalPill(stringResource(choice.labelResource()), choice == goalChoice) { onGoalChoice(choice) }
                }
            }
        }
        Surface(color = MaterialTheme.colorScheme.surface.copy(alpha = .98f), tonalElevation = 8.dp) {
        Column(Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TodayActivityChoice.entries.forEach { choice ->
                    ChoiceButton(stringResource(choice.labelResource()), choice.icon(), choice == activityChoice) { onActivityChoice(choice) }
                }
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                UtilityButton(stringResource(R.string.today_music), Icons.Default.LibraryMusic, onOpenMusic)
                UtilityButton(stringResource(R.string.today_voice_guide), if (voiceGuideEnabled) Icons.Default.Speaker else Icons.Default.SpeakerNotesOff, { onVoiceGuideChanged(!voiceGuideEnabled) }, voiceGuideEnabled)
                UtilityButton(stringResource(R.string.today_cheer), Icons.Default.NotificationsActive, onOpenLiveTrack)
                UtilityButton(stringResource(R.string.today_shoes), Icons.Default.DirectionsRun, onOpenShoes)
                UtilityButton(stringResource(if (indoor) R.string.today_indoor else R.string.today_outdoor), if (indoor) Icons.Default.HomeWork else Icons.Default.WbSunny, { onIndoorChanged(!indoor) }, true)
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
    Surface(onClick = onClick, shape = RoundedCornerShape(15.dp), color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant) {
        Column(Modifier.width(76.dp).heightIn(min = 60.dp).padding(horizontal = 8.dp, vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Icon(icon, null, tint = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant)
            Text(label, textAlign = androidx.compose.ui.text.style.TextAlign.Center, color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.labelLarge, maxLines = 1)
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
private fun UtilityButton(label: String, icon: ImageVector, onClick: () -> Unit, selected: Boolean = false) {
    Surface(onClick = onClick, shape = RoundedCornerShape(14.dp), color = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant) {
        Column(Modifier.width(82.dp).heightIn(min = 60.dp).padding(horizontal = 6.dp, vertical = 7.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Icon(icon, null, tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
            Text(label, textAlign = androidx.compose.ui.text.style.TextAlign.Center, color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.labelMedium, maxLines = 1)
        }
    }
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

private fun TodayActivityChoice.labelResource() = when (this) {
    TodayActivityChoice.PLANNED -> R.string.today_planned
    TodayActivityChoice.RUN -> R.string.today_run
    TodayActivityChoice.WALK -> R.string.today_walk
    TodayActivityChoice.HIKE -> R.string.today_hike
    TodayActivityChoice.BIKE -> R.string.today_bike
}

private fun TodayGoalChoice.labelResource() = when (this) {
    TodayGoalChoice.CURATED -> R.string.today_curated
    TodayGoalChoice.FREE -> R.string.today_free
    TodayGoalChoice.DISTANCE -> R.string.today_distance
    TodayGoalChoice.TIME -> R.string.today_time
    TodayGoalChoice.CALORIES -> R.string.today_calories
}

private fun TodayGoalChoice.valueResource() = when (this) {
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
private fun WorkoutDetailSheet(suggestion: ActivitySuggestion, onDismiss: () -> Unit, onStart: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(suggestion.title, Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(stringResource(R.string.today_detail_summary, suggestion.durationMinutes, suggestion.effortLabel), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.today_phases), style = MaterialTheme.typography.titleMedium)
            suggestion.steps.forEachIndexed { index, step ->
                Row(verticalAlignment = Alignment.Top) {
                    Text("${index + 1}", Modifier.size(32.dp).clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.primaryContainer).padding(7.dp), style = MaterialTheme.typography.labelMedium)
                    Spacer(Modifier.width(12.dp)); Text(step, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                }
            }
            HorizontalDivider()
            Text(stringResource(R.string.today_purpose), style = MaterialTheme.typography.titleMedium)
            Text(suggestion.why, style = MaterialTheme.typography.bodyLarge)
            Button(onClick = onStart, Modifier.fillMaxWidth().heightIn(min = 52.dp)) { Text(suggestion.startLabel) }
            Spacer(Modifier.height(20.dp))
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
    onSubmit: (TodayConstraint, String, String?) -> Unit,
    onDecision: (String, Boolean) -> Unit,
) {
    var selected by rememberSaveable { mutableStateOf<TodayConstraint?>(null) }
    var note by rememberSaveable { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(stringResource(R.string.today_change_title), Modifier.semantics { heading() }, style = MaterialTheme.typography.headlineSmall)
            Text(stringResource(R.string.today_change_body), color = MaterialTheme.colorScheme.onSurfaceVariant)
            TodayConstraint.entries.forEach { choice ->
                OutlinedButton(
                    onClick = { selected = choice },
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                ) { Text(stringResource(choice.labelResource())) }
            }
            OutlinedTextField(note, { note = it.take(160) }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.today_optional_note)) }, maxLines = 3)
            if (pending == null) {
                Button(onClick = { selected?.let { onSubmit(it, original.plannedWorkoutId ?: original.id, note.ifBlank { null }) } }, enabled = selected != null && !busy, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.today_show_alternative))
                }
                TextButton(onClick = onDismiss, Modifier.fillMaxWidth()) { Text(stringResource(R.string.today_keep_original)) }
            } else {
                HorizontalDivider()
                Text(stringResource(R.string.today_recommendation), style = MaterialTheme.typography.titleMedium)
                Text(pending.explanation)
                pending.changes.forEach { Text(stringResource(R.string.today_change_comparison, it.beforeTitle, it.afterTitle), style = MaterialTheme.typography.bodyMedium) }
                Button(onClick = { onDecision(pending.id, true) }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.today_apply_change)) }
                OutlinedButton(onClick = { onDecision(pending.id, false) }, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text(stringResource(R.string.today_keep_original)) }
            }
            Spacer(Modifier.height(20.dp))
        }
    }
}

private fun TodayConstraint.labelResource() = when (this) {
    TodayConstraint.LowEnergy -> R.string.today_low_energy
    TodayConstraint.Soreness -> R.string.today_soreness
    TodayConstraint.LimitedTime -> R.string.today_limited_time
    TodayConstraint.FeelingGood -> R.string.today_feeling_good
}
