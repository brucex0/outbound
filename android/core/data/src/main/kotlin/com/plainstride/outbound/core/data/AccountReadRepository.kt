package com.plainstride.outbound.core.data

import android.util.Log
import androidx.room.withTransaction
import com.plainstride.outbound.core.database.*
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.network.*
import java.time.Instant
import kotlinx.coroutines.flow.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*

/** Shared, account-owned baseline. All acknowledgement and read cursors commit in Room. */
class AccountReadRepository(
    private val database: PlainstrideDatabase,
    private val tokens: AccessTokenProvider,
) {
    private val dao get() = database.accountProjectionDao()
    private val clock = MutableStateFlow(Instant.now())
    fun observeClock(): StateFlow<Instant> = clock.asStateFlow()
    fun updateCalendar(now: Instant = Instant.now()) { clock.value = now }
    fun context(accountId: String) = tokens.captureAccount(accountId)
    fun isCurrent(context: AccountRequestContext) = tokens.isCurrent(context)

    fun observe(accountId: String) = dao.observe(accountId)
    fun observePlanning(accountId: String): Flow<PlanningReadModel?> = combine(dao.observe(accountId), clock) { row, now ->
        row?.baseline?.planningJson?.let { json ->
            try {
                val raw = PlainstrideJson.decodeFromString<PlanningState>(json)
                val projected = project(raw, row.completions, now)
                PlanningReadModel(projected, row.baseline.planningDirty || now.toEpochMilli() - row.baseline.planningUpdatedAtEpochMs >= 300_000,
                    row.baseline.planningUpdatedAtEpochMs)
            } catch (error: Exception) {
                Log.e("PlainstridePlanning", "projection_decode_failed type=${error.javaClass.simpleName}")
                null
            }
        }
    }
    fun observeStatistics(accountId: String): Flow<JsonObject?> = dao.observe(accountId).map { row ->
        row?.baseline?.statisticsJson?.let { json ->
            try { PlainstrideJson.parseToJsonElement(json).jsonObject }
            catch (error: Exception) { Log.e("PlainstrideStatistics", "projection_decode_failed type=${error.javaClass.simpleName}"); null }
        }
    }

    suspend fun ensure(accountId: String) { if (dao.get(accountId) == null) dao.upsert(AccountProjectionEntity(accountId)) }
    suspend fun statisticsTicket(context: AccountRequestContext): Long? = database.withTransaction {
        if (!isCurrent(context)) return@withTransaction null
        ensure(context.accountId)
        dao.get(context.accountId)!!.statisticsTicket
    }
    suspend fun invalidate(context: AccountRequestContext) = database.withTransaction {
        if (!isCurrent(context)) return@withTransaction
        ensure(context.accountId)
        val old = dao.get(context.accountId)!!
        dao.upsert(old.copy(planningDirty = true, statisticsDirty = true, statisticsTicket = old.statisticsTicket + 1))
    }
    suspend fun acceptPlanning(context: AccountRequestContext, state: PlanningState, command: Boolean = false): Boolean = database.withTransaction {
        if (!isCurrent(context)) return@withTransaction false
        ensure(context.accountId)
        var old = dao.get(context.accountId)!!
        if (command) {
            old = old.copy(statisticsDirty = true, statisticsTicket = old.statisticsTicket + 1)
            dao.upsert(old)
        }
        if (state.revision < maxOf(old.planningRevision, old.requiredPlanningRevision)) {
            Log.i("PlainstridePlanning", "snapshot_rejected category=older_revision")
            return@withTransaction false
        }
        dao.upsert(old.copy(planningJson = PlainstrideJson.encodeToString(state), planningRevision = state.revision,
            planningDirty = false, planningUpdatedAtEpochMs = System.currentTimeMillis()))
        true
    }
    suspend fun acceptStatistics(context: AccountRequestContext, value: JsonObject, ticket: Long): Boolean = database.withTransaction {
        if (!isCurrent(context)) return@withTransaction false
        val old = dao.get(context.accountId) ?: return@withTransaction false
        val revision = value["revision"]?.jsonPrimitive?.longOrNull ?: return@withTransaction false
        if (value["status"]?.jsonPrimitive?.contentOrNull != "complete" || value["algorithmVersion"]?.jsonPrimitive?.intOrNull != 1
            || revision < maxOf(old.statisticsRevision, old.requiredStatisticsRevision) || ticket != old.statisticsTicket) {
            Log.i("PlainstrideStatistics", "snapshot_rejected category=stale_or_incomplete")
            return@withTransaction false
        }
        val computed = try { Instant.parse(value.getValue("computedAt").jsonPrimitive.content) }
        catch (error: Exception) { Log.w("PlainstrideStatistics", "snapshot_rejected category=invalid_computed_time"); return@withTransaction false }
        val previousComputed = old.statisticsJson?.let { PlainstrideJson.parseToJsonElement(it).jsonObject["computedAt"]?.jsonPrimitive?.contentOrNull }?.let(Instant::parse)
        if (revision == old.statisticsRevision && previousComputed != null && computed < previousComputed) return@withTransaction false
        dao.upsert(old.copy(statisticsJson = value.toString(), statisticsRevision = revision, statisticsDirty = false))
        true
    }

    /** Call inside the same activity save transaction, after its generation and payload are captured. */
    suspend fun saved(activity: com.plainstride.outbound.core.model.activity.SavedActivity, generation: Long) {
        ensure(activity.accountId)
        val old = dao.get(activity.accountId)!!
        dao.upsert(old.copy(statisticsDirty = true, statisticsTicket = old.statisticsTicket + 1))
        val previous = dao.completion(activity.accountId, activity.id)
        val receipt = activity.performedWorkoutReference
        if (receipt != null) dao.upsertCompletion(ActivityCompletionEntity(activity.accountId, activity.id, generation,
            receipt.plannedWorkoutId, PlainstrideJson.encodeToString(receipt), "pending", previous?.canonicalCompletionJson, acceptedPlanningRevision = previous?.acceptedPlanningRevision))
        else dao.removeUnconfirmed(activity.accountId, activity.id)
    }
    suspend fun deleted(accountId: String, activityId: String) {
        ensure(accountId)
        val old = dao.get(accountId)!!
        dao.upsert(old.copy(planningDirty = true, statisticsDirty = true, statisticsTicket = old.statisticsTicket + 1))
        dao.removeUnconfirmed(accountId, activityId)
    }
    /** Durable acceptance precedes outbox removal, including when the uploaded generation has since changed. */
    suspend fun accepted(accountId: String, activityId: String, generation: Long, receipt: ActivityReconciliation) {
        ensure(accountId)
        val old = dao.get(accountId)!!
        dao.upsert(old.copy(requiredPlanningRevision = maxOf(old.requiredPlanningRevision, receipt.planningRevision),
            requiredStatisticsRevision = maxOf(old.requiredStatisticsRevision, receipt.statisticsRevision),
            planningDirty = true, statisticsDirty = true, statisticsTicket = old.statisticsTicket + 1))
        val previous = dao.completion(accountId, activityId)
        if (previous != null) {
            val exactGeneration = previous.generation == generation
            dao.upsertCompletion(previous.copy(state = if (exactGeneration) "confirmed" else previous.state,
                canonicalCompletionJson = receipt.completion?.let { PlainstrideJson.encodeToString(it) }, rejectionCode = if (exactGeneration) null else previous.rejectionCode, acceptedPlanningRevision = receipt.planningRevision))
        } else receipt.completion?.let { completion ->
            dao.upsertCompletion(ActivityCompletionEntity(accountId, activityId, generation, completion.plannedWorkoutId,
                null, "confirmed", PlainstrideJson.encodeToString(completion), acceptedPlanningRevision = receipt.planningRevision))
        }
    }

    suspend fun rejected(accountId: String, activityId: String, generation: Long) {
        val previous = dao.completion(accountId, activityId) ?: return
        if (previous.generation == generation) dao.upsertCompletion(previous.copy(state = "rejected", rejectionCode = "performed_workout_conflict"))
    }
    suspend fun retryRejected(context: AccountRequestContext) = database.withTransaction {
        if (!isCurrent(context)) return@withTransaction
        database.syncOutboxDao().retryRejected(context.accountId, System.currentTimeMillis())
        val row = dao.snapshot(context.accountId)
        row?.completions?.filter { it.state == "rejected" }?.forEach { dao.upsertCompletion(it.copy(state = "pending", rejectionCode = null)) }
    }
    private fun project(raw: PlanningState, completions: List<ActivityCompletionEntity>, now: Instant): PlanningState {
        val confirmed = completions.filter { raw.revision < (it.acceptedPlanningRevision ?: -1) }.mapNotNull { it.canonicalCompletionJson?.let { json -> PlainstrideJson.decodeFromString<CanonicalWorkoutCompletion>(json) } }
            .filter { it.status == "completed" }.mapTo(mutableSetOf()) { it.plannedWorkoutId }
        val pending = completions.filter { it.state == "pending" }.mapTo(mutableSetOf()) { it.plannedWorkoutId }
        fun workout(value: com.plainstride.outbound.core.model.PlannedWorkout) = when {
            value.status == "completed" || value.id in confirmed -> value.copy(status = "completed")
            value.id in pending -> value.copy(status = "pending")
            else -> value
        }
        val calendar = raw.calendar?.resolved(now)
        val today = now.atZone(calendar?.zone() ?: java.time.ZoneId.of("UTC")).toLocalDate().toString()
        val coverage = calendar == null || raw.calendar?.weekEnd == calendar.weekEnd || raw.workouts.any {
            val date = it.scheduledDate.take(10)
            date >= now.atZone(calendar.zone()).toLocalDate().with(java.time.temporal.TemporalAdjusters.previousOrSame(java.time.DayOfWeek.MONDAY)).toString()
        }
        return raw.copy(calendar = calendar, cachedScheduleCoverageAvailable = coverage, workouts = raw.workouts.map(::workout), upcoming = raw.upcoming.map(::workout),
            today = raw.today?.takeIf { it.scheduledDate.take(10) == today }?.let(::workout))
    }
}

data class PlanningReadModel(val value: PlanningState, val stale: Boolean, val updatedAt: Long)
