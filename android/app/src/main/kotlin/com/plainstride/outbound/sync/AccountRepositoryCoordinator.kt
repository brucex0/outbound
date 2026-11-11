package com.plainstride.outbound.sync

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.util.Log
import android.content.Context
import com.plainstride.outbound.core.auth.*
import com.plainstride.outbound.core.data.*
import com.plainstride.outbound.connectivity.NetworkConnectivityMonitor
import com.plainstride.outbound.feature.today.TodayRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.Instant
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.*

/** App-owned reconciliation resumes durable work without requiring a particular screen. */
@Singleton
class AccountRepositoryCoordinator @Inject constructor(
    @ApplicationContext private val context: Context,
    private val sessions: SessionCoordinator,
    private val activities: ActivityRepository,
    private val reads: AccountReadRepository,
    private val today: TodayRepository,
    private val connectivity: NetworkConnectivityMonitor,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val signals = Channel<Unit>(Channel.CONFLATED)
    private var started = false
    fun start() {
        if (started) return
        started = true
        (context.applicationContext as Application).registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) { signals.trySend(Unit) }
            override fun onActivityCreated(activity: Activity, state: Bundle?) {}
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
        scope.launch { connectivity.isOffline.collect { if (!it) signals.trySend(Unit) } }
        scope.launch { while (isActive) { delay(60_000); signals.trySend(Unit) } }
        scope.launch {
            sessions.state.map { state ->
                when (state) {
                    is SessionState.SignedIn -> state.accountId
                    is SessionState.Refreshing -> state.accountId
                    else -> null
                } to sessions.generation
            }.distinctUntilChanged().collectLatest { (accountId, _) ->
                if (accountId == null) return@collectLatest
                coroutineScope {
                    launch {
                        combine(reads.observe(accountId), activities.observePendingSyncCount(accountId)) { row, pending ->
                            listOf(row?.baseline?.planningDirty, row?.baseline?.statisticsDirty, row?.baseline?.statisticsTicket, pending)
                        }.distinctUntilChanged().collect { signals.trySend(Unit) }
                    }
                    signals.trySend(Unit)
                    var previousDay: String? = null
                    for (signal in signals) {
                        reads.updateCalendar()
                        val owner = reads.context(accountId) ?: break
                        val planning = reads.observePlanning(accountId).first()?.value
                        val day = Instant.now().atZone(planning?.calendar?.zone() ?: java.time.ZoneId.of("UTC")).toLocalDate().toString()
                        if (previousDay != null && previousDay != day) reads.invalidate(owner)
                        previousDay = day
                        if (connectivity.isOffline.value) continue
                        for (attempt in 0..2) {
                            if (!reads.isCurrent(owner)) break
                            try {
                                activities.synchronize(accountId)
                                if (!reads.isCurrent(owner)) break
                                today.refresh(accountId, Locale.getDefault().toLanguageTag())
                                val row = reads.observe(accountId).first()?.baseline
                                if (row != null && !row.planningDirty && !row.statisticsDirty) break
                            } catch (error: CancellationException) { throw error }
                            catch (error: Exception) { Log.w("PlainstrideRepository", "reconcile_failed type=${error.javaClass.simpleName}") }
                            delay(if (attempt == 0) 1_000 else 5_000)
                        }
                    }
                }
            }
        }
    }
}
