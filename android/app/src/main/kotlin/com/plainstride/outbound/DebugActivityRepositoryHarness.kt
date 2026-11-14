package com.plainstride.outbound

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.room.Room
import com.plainstride.outbound.connectivity.ConnectivityUiState
import com.plainstride.outbound.core.analytics.*
import com.plainstride.outbound.core.data.*
import com.plainstride.outbound.core.database.PlainstrideDatabase
import com.plainstride.outbound.core.model.*
import com.plainstride.outbound.core.model.activity.*
import com.plainstride.outbound.core.network.*
import com.plainstride.outbound.feature.today.DebugRunningPlanDetails
import java.io.File
import java.lang.reflect.Proxy
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.Response

/** Explicit DEBUG route: isolated synthetic Room database and in-process transport; no real account/API. */
private class RepositoryFixture(private val context: Context) {
    val account = "synthetic-repository"
    var owner = account
    var epoch = 1L
    var conflict = false
    var uploadHook: (() -> Unit)? = null
    var canonical = false
    var serverRevision = 30L
    private val anchor = Instant.parse("2026-11-11T20:00:00Z")
    val tokens = object : AccessTokenProvider {
        override suspend fun validAccessToken() = "synthetic"
        override fun captureAccount(accountId: String) = AccountRequestContext(accountId, epoch).takeIf { accountId == owner }
        override fun isCurrent(context: AccountRequestContext) = context.accountId == owner && context.generation == epoch
    }
    val database = Room.databaseBuilder(context, PlainstrideDatabase::class.java, "repository-review-fixture-v9.db").build()
    val reads = AccountReadRepository(database, tokens)
    private val analytics = ProductAnalytics(object : AnalyticsSink {
        override fun setUserId(userId: String?) {}
        override fun record(event: SanitizedAnalyticsEvent) {}
    })
    private val media = ActivityMediaStore(context)
    private var lastRequest: ActivityUploadRequest? = null
    private val api = Proxy.newProxyInstance(ActivitiesApiService::class.java.classLoader, arrayOf(ActivitiesApiService::class.java)) { _, method, args ->
        when (method.name) {
            "upload" -> {
                val request = args!![1] as ActivityUploadRequest
                lastRequest = request
                uploadHook?.also { uploadHook = null }?.invoke()
                if (conflict) Response.error<ActivityUploadResponse>(409, "{\"code\":\"performed_workout_conflict\"}".toResponseBody("application/json".toMediaType()))
                else {
                    val reference = request.clientData["performedWorkoutReference"]?.takeUnless { it == JsonNull }?.jsonObject
                    val completion = reference?.let { CanonicalWorkoutCompletion("server-activity", it.getValue("plannedWorkoutId").jsonPrimitive.content, "version", "completed", 1800) }
                    // Encode/decode the actual DTO adapter, including the private acceptance receipt.
                    val response = ActivityUploadResponse("server-${if (canonical) "canonical" else request.clientActivityId}", if (canonical) "canonical-activity" else request.clientActivityId, "created",
                        anchor.toString(), anchor.toString(), ActivityReconciliation(serverRevision++, 5, completion))
                    Response.success(PlainstrideJson.decodeFromString<ActivityUploadResponse>(PlainstrideJson.encodeToString(response)))
                }
            }
            "statistics" -> Response.success(PlainstrideJson.parseToJsonElement(File(context.filesDir, "repository-statistics.json").readText()).jsonObject)
            "activities" -> {
                val request = lastRequest
                val remote = if (canonical && request != null && args?.get(4) == "server-canonical") listOf(RemoteActivityDto(
                    "server-canonical", "canonical-activity", request.clientData, request.type, request.title,
                    startedAt = request.startedAt, endedAt = request.endedAt, durationSecs = request.durationSecs,
                    distanceM = request.distanceM, clientUpdatedAt = request.clientUpdatedAt, createdAt = request.startedAt, updatedAt = anchor.toString())) else emptyList()
                Response.success(ActivityListResponse(remote, false))
            }
            "cachedChanges" -> Response.success(ActivityListResponse(emptyList(), false))
            else -> throw java.io.IOException("Synthetic unsupported operation: ${method.name}")
        }
    } as ActivitiesApiService
    private val photos = ActivityPhotoRepository(context, api, tokens, database.activityDao(), media, analytics) { owner }
    val activities = OfflineFirstActivityRepository(database, api, tokens, media, photos, analytics, { owner })
    val receipt = PerformedWorkoutReference("performed-workout-v1", "synthetic-issuance", "a".repeat(64), "slot-1", "version", true)
    val baseline = PlanningState(revision = 20, calendar = PlanningCalendarContext("monday-v1", "America/Los_Angeles", 2,
        "2026-11-09T08:00:00Z", "2026-11-16T08:00:00Z", "2026-11-11", 1, true),
        plan = TrainingPlan("synthetic-plan", "foundation", "generated", "2026-11-11T08:00:00Z"),
        workouts = listOf(11, 13, 15).mapIndexed { index, day -> PlannedWorkout("slot-${index + 1}", "2026-11-${day}T00:00:00Z",
            Modality.run, TrainingStimulus.easyAerobic, "Easy run", 1800, isKeyWorkout = false, status = "planned", performedWorkoutReference = if (index == 0) receipt else null) },
        planningStatus = PlanningStatus.stable)
    val saved = SavedActivity("fixture-activity", account, type = ActivityType.running, title = "Synthetic saved run",
        createdAt = anchor.toString(), startedAt = anchor.toString(), endedAt = anchor.plusSeconds(1800).toString(),
        durationSecs = 1800, distanceM = 3000.0, localUpdatedAt = anchor.toString(), performedWorkoutReference = receipt)
    val checks = linkedMapOf<String, Boolean>().apply {
        val previous = File(context.filesDir, "repository-review-report.json")
        if (previous.exists()) try { PlainstrideJson.parseToJsonElement(previous.readText()).jsonObject.forEach { (key, value) -> put(key, value.jsonPrimitive.boolean) } }
        catch (error: Exception) { android.util.Log.w("RepositoryFixture", "previous_report_decode_failed type=${error.javaClass.simpleName}") }
    }
    private suspend fun check(name: String, value: Boolean) { checks[name] = value; report() }
    private fun report() { File(context.filesDir, "repository-review-report.json").writeText(buildJsonObject { checks.forEach { (key, value) -> put(key, value) } }.toString()) }
    suspend fun initialize() {
        reads.updateCalendar(anchor)
        val owner = reads.context(account)!!
        val previous = database.accountProjectionDao().get(account)
        if (previous != null) {
            serverRevision = maxOf(serverRevision, previous.requiredPlanningRevision + 1)
            check("restart_retains_baseline", previous.planningJson != null)
            check("restart_retains_receipt", database.accountProjectionDao().completion(account, saved.id)?.receiptJson != null)
            return
        }
        reads.acceptPlanning(owner, baseline)
        activities.save(saved)
        activities.save(saved) // One exact slot credit and only the latest unsent mutation.
        check("pending_exact_slot", reads.observePlanning(account).first()!!.value.workouts.count { it.status == "pending" } == 1)
        check("outbox_payload_generation", database.syncOutboxDao().pending(account, Long.MAX_VALUE, 100).single().let {
            it.mutationGeneration == database.activityDao().get(account, saved.id)!!.activity.mutationGeneration && it.payloadJson.contains("synthetic-issuance") })
        check("older_planning_rejected", !reads.acceptPlanning(owner, baseline.copy(revision = 19)))
        val ticket = reads.statisticsTicket(owner)!!
        reads.invalidate(owner)
        val stats = PlainstrideJson.parseToJsonElement(File(context.filesDir, "repository-statistics.json").readText()).jsonObject
        check("pre_command_statistics_rejected", !reads.acceptStatistics(owner, stats, ticket))
        check("complete_server_totals_retained", reads.acceptStatistics(owner, stats, reads.statisticsTicket(owner)!!)
            && reads.observeStatistics(account).first() == stats)
        this.owner = "other-account"; epoch++
        check("old_owner_read_rejected", !reads.acceptPlanning(owner, baseline.copy(revision = 999)))
        check("account_projection_isolated", database.accountProjectionDao().get(this.owner) == null)
        this.owner = account; epoch++
        check("same_account_old_epoch_rejected", !reads.acceptPlanning(owner, baseline.copy(revision = 999)))
        reads.acceptPlanning(reads.context(account)!!, baseline)
    }
    suspend fun accept() {
        conflict = false
        activities.synchronize(account)
        check("acceptance_before_ack", database.syncOutboxDao().count(account) == 0
            && database.accountProjectionDao().completion(account, saved.id)?.state == "confirmed"
            && database.accountProjectionDao().get(account)!!.requiredPlanningRevision >= 30L)
        val credited = database.accountProjectionDao().completion(account, saved.id)!!.canonicalCompletionJson!!.let { PlainstrideJson.decodeFromString<CanonicalWorkoutCompletion>(it).plannedWorkoutId }
        check("confirmed_exact_slot", reads.observePlanning(account).first()!!.value.workouts.single { it.id == credited }.status == "completed")
        val revision = database.accountProjectionDao().get(account)!!.requiredPlanningRevision
        reads.acceptPlanning(reads.context(account)!!, baseline.copy(revision = revision,
            workouts = baseline.workouts.map { if (it.id == credited) it.copy(status = "completed") else it }))
    }
    suspend fun reject() {
        activities.edit(activities.activity(account, saved.id)!!.copy(performedWorkoutReference = receipt.copy(plannedWorkoutId = "slot-2")))
        conflict = true
        activities.synchronize(account)
        check("terminal_conflict_retains_activity_receipt", activities.activity(account, saved.id) != null && database.accountProjectionDao().completion(account, saved.id)?.state == "rejected")
        check("terminal_conflict_stops_automatic_upload", database.syncOutboxDao().pending(account, Long.MAX_VALUE, 100).isEmpty())
        check("rejected_pending_withdrawn", reads.observePlanning(account).first()!!.value.workouts.none { it.id == "slot-2" && it.status == "pending" })
    }
    suspend fun retry() { activities.retryRejected(account); conflict = false; accept() }
    suspend fun races() {
        conflict = false
        val racing = saved.copy(id = "race-activity", title = "Before upload")
        activities.save(racing)
        uploadHook = { runBlocking { activities.edit(racing.copy(title = "Edited during upload")) } }
        activities.synchronize(account)
        check("delayed_ack_preserves_edit", activities.activity(account, racing.id)?.title == "Edited during upload"
            && database.syncOutboxDao().pending(account, Long.MAX_VALUE, 100).any { it.aggregateId == racing.id })
        activities.synchronize(account)
        val conflictEdit = saved.copy(id = "conflict-edit-activity")
        activities.save(conflictEdit)
        conflict = true
        uploadHook = { runBlocking { activities.edit(conflictEdit.copy(title = "Edited before rejected acknowledgement")) } }
        activities.synchronize(account)
        check("delayed_conflict_supersedes_old_generation", database.syncOutboxDao().count(account) == 1
            && database.syncOutboxDao().pending(account, Long.MAX_VALUE, 100).single().aggregateId == conflictEdit.id
            && database.accountProjectionDao().completion(account, conflictEdit.id)?.state == "pending")
        conflict = false
        activities.synchronize(account)
        val switching = saved.copy(id = "owner-race-activity")
        activities.save(switching)
        uploadHook = { owner = "other-account"; epoch++ }
        activities.synchronize(account)
        check("upload_owner_switch_retains_outbox", database.syncOutboxDao().count(account) > 0
            && database.activityDao().get(account, switching.id)?.activity?.serverActivityId == null)
        owner = account; epoch++
        activities.synchronize(account)
        val originalBytes = "synthetic-original-jpeg-bytes".toByteArray()
        val targetBytes = "synthetic-existing-target-bytes".toByteArray()
        val target = saved.copy(id = "canonical-activity", performedWorkoutReference = null,
            photos = listOf(ActivityPhoto("target-photo", anchor.toString(), localRelativePath = media.write(account, "canonical-activity", targetBytes), remotePhotoId = "remote-target-photo")))
        val targetRoute = listOf(ActivityTrackPoint(anchor.toString(), 1.0, 2.0), ActivityTrackPoint(anchor.plusSeconds(30).toString(), 1.1, 2.1))
        val terrain = ActivityElevationMetadata("terrain-v2", "synthetic", "Synthetic", "https://example.invalid", false)
        activities.save(target.copy(track = targetRoute, elevationMetadata = terrain))
        activities.synchronize(account)
        val source = saved.copy(id = "canonical-source", performedWorkoutReference = null,
            photos = listOf(ActivityPhoto("source-photo", anchor.toString(), localRelativePath = media.write(account, "canonical-source", originalBytes), remotePhotoId = "remote-source-photo")))
        activities.save(source)
        canonical = true
        activities.synchronize(account)
        canonical = false
        val adopted = activities.activity(account, target.id)
        check("canonical_bytes_and_existing_media_retained", adopted?.photos?.size == 2
            && adopted.photos.any { it.id == "source-photo" && media.read(it.localRelativePath!!).contentEquals(originalBytes) }
            && adopted.photos.any { it.id == "target-photo" && media.read(it.localRelativePath!!).contentEquals(targetBytes) }
            && activities.activity(account, source.id)?.deletedAt != null)
        check("canonical_existing_target_route_retained", adopted?.track == targetRoute && adopted.elevationMetadata == terrain)
        check("canonical_ack_durable", database.syncOutboxDao().count(account) == 0)
    }
    private val today by lazy {
        val planningApi = Proxy.newProxyInstance(PlanningApiService::class.java.classLoader, arrayOf(PlanningApiService::class.java)) { _, _, _ -> throw java.io.IOException("Synthetic transport disabled") } as PlanningApiService
        com.plainstride.outbound.feature.today.OfflineFirstTodayRepository(context, planningApi, tokens, database.accountCacheDao(), reads)
    }
    fun observeSuggestion() = today.observeSuggestion(account, "en")
    suspend fun pendingToday() {
        reads.acceptPlanning(reads.context(account)!!, baseline.copy(revision = maxOf(200, database.accountProjectionDao().get(account)!!.planningRevision + 1)))
        activities.save(saved.copy(id = "today-pending-activity"))
        seedSuggestion()
        reads.updateCalendar(anchor)
        val planning = reads.observePlanning(account).first()!!
        val suggestion = today.observeSuggestion(account, "en").first()
        val state = com.plainstride.outbound.feature.today.TodayUiState(planning = com.plainstride.outbound.feature.today.CachedResource.Available(planning.value, true, planning.updatedAt), suggestion = suggestion)
        check("today_exact_pending_is_labeled", state.pendingWorkoutToday?.id == "slot-1")
        check("today_saved_suggestion_not_launchable", state.primarySuggestion == null)
    }
    private suspend fun seedSuggestion(plannedWorkoutId: String? = "slot-1") {
        val primary = ActivitySuggestion("synthetic-suggestion", "Easy run", Modality.run, TrainingStimulus.easyAerobic, 30,
            effortLabel = "Easy", intensityModel = "rpe", why = "", steps = emptyList(), startLabel = "Start", optional = false, plannedWorkoutId = plannedWorkoutId)
        val envelope = ActivitySuggestionEnvelope("ready", "plan", "planned", primary, guideLine = "", planningStatus = PlanningStatus.stable,
            generatedAt = "2026-11-11T19:00:00Z", validForDate = "2026-11-11", validUntil = "2026-11-12T00:00:00Z", planContext = SuggestionPlanContext("synthetic-plan"),
            activityWatermark = ActivityWatermark(), decision = SuggestionDecision("synthetic", emptyList(), emptyList()))
        database.accountCacheDao().upsert(com.plainstride.outbound.core.database.AccountCacheEntity(account, "planning.suggestion", "current", "en",
            PlainstrideJson.encodeToString(envelope), null, anchor.toEpochMilli(), anchor.plusSeconds(300).toEpochMilli()))
    }
    suspend fun expiredSuggestion() {
        seedSuggestion(null)
        reads.updateCalendar(anchor)
        val initial = today.observeSuggestion(account, "en").first() as com.plainstride.outbound.feature.today.CachedResource.Available
        check("same_day_suggestion_launchable", initial.value.primary != null)
        reads.updateCalendar(Instant.parse("2026-11-12T00:01:00Z"))
        val expired = today.observeSuggestion(account, "en").first() as com.plainstride.outbound.feature.today.CachedResource.Available
        check("old_day_suggestion_expires_without_cache_write", expired.value.primary == null && expired.value.alternates.isEmpty() && expired.isStale)
        check("expired_today_has_no_launch_recipe", com.plainstride.outbound.feature.today.TodayUiState(suggestion = expired).primarySuggestion == null)
        reads.updateCalendar(anchor)
        val context = reads.context(account)!!
        val current = reads.observePlanning(account).first()!!.value
        val row = database.accountProjectionDao().get(account)!!
        val revision = maxOf(row.requiredPlanningRevision, row.planningRevision) + 1
        reads.acceptPlanning(context, current.copy(revision = revision, workouts = current.workouts.map { it.copy(status = "skipped") }))
        check("newer_authoritative_state_supersedes_completion_overlay", reads.observePlanning(account).first()!!.value.workouts.all { it.status == "skipped" })
    }
    suspend fun noPlan() {
        val context = reads.context(account)!!
        reads.acceptPlanning(context, baseline.copy(revision = maxOf(100, database.accountProjectionDao().get(account)!!.planningRevision + 1), plan = null, workouts = emptyList()))
        check("known_no_plan_distinct_from_unknown", reads.observePlanning(account).first()?.value?.plan == null
            && database.accountProjectionDao().get(account)?.planningJson != null)
    }
    suspend fun rollover() {
        reads.acceptPlanning(reads.context(account)!!, baseline.copy(revision = maxOf(101, database.accountProjectionDao().get(account)!!.planningRevision + 1)))
        reads.updateCalendar(Instant.parse("2026-11-16T20:00:00Z"))
        val projected = reads.observePlanning(account).first()!!.value
        check("monday_rollover_rebucketed", projected.calendar?.planWeekIndex == 2 && !projected.cachedScheduleCoverageAvailable)
    }
}

@Composable
internal fun DebugActivityRepositoryHarness(settingsViewModel: com.plainstride.outbound.feature.settings.SettingsViewModel) {
    val context = LocalContext.current
    val fixture = remember { RepositoryFixture(context) }
    val intent = (context as? android.app.Activity)?.intent
    val locale = intent?.getStringExtra("repository_locale") ?: "en"
    val localized = remember(locale) { context.createConfigurationContext(android.content.res.Configuration(context.resources.configuration).apply { setLocale(java.util.Locale.forLanguageTag(locale)) }) }
    var dark by remember { mutableStateOf(intent?.getBooleanExtra("repository_dark", false) == true) }
    var offline by remember { mutableStateOf(intent?.getBooleanExtra("repository_offline", false) == true) }
    val surface = intent?.getStringExtra("repository_surface")
    val scope = rememberCoroutineScope()
    var ready by remember { mutableStateOf(false) }
    var details by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf("Loading synthetic repository") }
    val projection by fixture.reads.observe(fixture.account).collectAsState(initial = null)
    val planning by fixture.reads.observePlanning(fixture.account).collectAsState(initial = null)
    val statistics by fixture.reads.observeStatistics(fixture.account).collectAsState(initial = null)
    val suggestion by fixture.observeSuggestion().collectAsState(initial = com.plainstride.outbound.feature.today.CachedResource.Loading)
    fun action(block: suspend () -> Unit) { scope.launch(Dispatchers.IO) {
        try { block(); result = fixture.checks.toString() }
        catch (error: Exception) { result = "Fixture failed: ${error.javaClass.simpleName}"; android.util.Log.e("RepositoryFixture", "operation_failed", error) }
    } }
    LaunchedEffect(Unit) { withContext(Dispatchers.IO) { try { fixture.initialize()
        when ((context as? android.app.Activity)?.intent?.getStringExtra("repository_action")) {
            "confirm" -> { fixture.accept(); details = true }
            "reject" -> fixture.reject()
            "retry" -> fixture.retry()
            "no_plan" -> fixture.noPlan()
            "rollover" -> { fixture.rollover(); details = true }
            "races" -> fixture.races()
            "expiry" -> fixture.expiredSuggestion()
            "today_pending" -> fixture.pendingToday()
            "pending" -> details = true
        }
        ready = true; result = fixture.checks.toString() } catch (error: Exception) { result = "Add repository-statistics.json then relaunch"; android.util.Log.e("RepositoryFixture", "initialize_failed", error) } } }
    CompositionLocalProvider(
        androidx.activity.compose.LocalActivityResultRegistryOwner provides (context as androidx.activity.result.ActivityResultRegistryOwner),
        androidx.compose.ui.platform.LocalContext provides localized,
        androidx.compose.ui.platform.LocalConfiguration provides localized.resources.configuration,
        androidx.compose.ui.platform.LocalResources provides localized.resources) {
    com.plainstride.outbound.core.designsystem.PlainstrideTheme(
        theme = if (dark) com.plainstride.outbound.core.designsystem.PlainstrideThemeId.Ocean else com.plainstride.outbound.core.designsystem.PlainstrideThemeId.VictoryGold,
        darkTheme = dark,
    ) {
    if (surface == "today" || surface == "me") {
        Column(Modifier.fillMaxSize().padding(top = 32.dp)) {
            Row { TextButton(onClick = { dark = !dark }) { Text("Theme") }; TextButton(onClick = { offline = !offline }) { Text(if (offline) "Offline" else "Online") } }
            val cachedPlanning = planning?.let { com.plainstride.outbound.feature.today.CachedResource.Available(it.value, offline || it.stale, it.updatedAt) }
                ?: com.plainstride.outbound.feature.today.CachedResource.Loading
            if (surface == "today") com.plainstride.outbound.feature.today.TodayScreen(
                state = com.plainstride.outbound.feature.today.TodayUiState(planning = cachedPlanning, suggestion = suggestion, refreshError = if (offline) com.plainstride.outbound.feature.today.TodayDataError.Offline else null),
                weather = null, onRefresh = { action { fixture.activities.refreshStatistics(fixture.account) } }, onStart = { _, _, _ -> },
                onStartFreestyle = {}, onReturnToSession = {}, onSetUpPlan = {}, onBuildPlan = {}, onSubmitConstraint = { _, _, _, _ -> }, onDecideAdjustment = { _, _ -> },
            ) else {
                val weekly = statistics?.get("currentWeek")?.jsonObject
                val goal = statistics?.get("weeklyRunGoal")?.jsonObject
                com.plainstride.outbound.feature.settings.MeRoute(settingsViewModel, "synthetic", false, {}, {}, {}, {},
                    accountWeeklyMinutes = (weekly?.get("durationSeconds")?.jsonPrimitive?.intOrNull ?: 0) / 60,
                    accountWeeklyDistanceMeters = weekly?.get("distanceMeters")?.jsonPrimitive?.doubleOrNull ?: 0.0,
                    weeklyRunGoal = goal?.let { WeeklyRunGoal(it.getValue("completedRuns").jsonPrimitive.int, it["targetRuns"]?.jsonPrimitive?.intOrNull, it["scheduledRunsByToday"]?.jsonPrimitive?.intOrNull) },
                    planSummary = planning?.let { com.plainstride.outbound.feature.settings.MePlanSummary(it.value.plan?.currentPhase, null, null, it.value.plan == null) },
                    statisticsAvailable = statistics != null, statisticsCached = offline || projection?.baseline?.statisticsDirty == true,
                    onRefreshStatistics = { action { fixture.activities.refreshStatistics(fixture.account) } }, onRefreshToday = { fixture.reads.updateCalendar() },
                    onMessage = {},
                )
            }
        }
    } else {
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row { TextButton(onClick = { dark = !dark }) { Text("Theme") }; Text("Synthetic repository", style = MaterialTheme.typography.titleLarge) }
        ConnectivityBanner(ConnectivityUiState(hasRejectedWorkout = projection?.completions?.any { it.state == "rejected" } == true), onRetry = { action { fixture.retry() } })
        Text(if (planning?.value?.plan == null) "No active plan" else "Account Monday schedule")
        Row { TextButton(onClick = { details = true }, enabled = ready) { Text("Plan details") }; TextButton(onClick = { action { fixture.accept() } }, enabled = ready) { Text("Confirm") } }
        Row { TextButton(onClick = { action { fixture.reject() } }, enabled = ready) { Text("Reject") }; TextButton(onClick = { action { fixture.noPlan() } }, enabled = ready) { Text("No plan") }; TextButton(onClick = { action { fixture.rollover() } }, enabled = ready) { Text("Rollover") } }
        Text(result, style = MaterialTheme.typography.bodySmall)
    }
    if (details && planning?.value?.plan != null) DebugRunningPlanDetails(planning!!.value, null, onDismiss = { details = false })
    }
    }
    }
}
