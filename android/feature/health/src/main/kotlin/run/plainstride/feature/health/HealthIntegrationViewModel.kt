package run.plainstride.feature.health

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.Instant
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import run.plainstride.core.data.ActivityRepository
import run.plainstride.feature.recording.ActivityKind
import run.plainstride.feature.recording.RecordedActivityReview

@HiltViewModel
class HealthIntegrationViewModel @Inject constructor(
    private val health: HealthConnectRepository,
    private val activities: ActivityRepository,
    @param:ApplicationContext private val context: Context,
) : ViewModel() {
    private val mutablePermissions = MutableStateFlow<HealthPermissionSnapshot?>(null)
    val permissions = mutablePermissions.asStateFlow()
    private var accountId: String? = null

    fun start(accountId: String) { this.accountId = accountId; refresh() }
    fun refresh() = viewModelScope.launch { mutablePermissions.value = health.permissionSnapshot() }

    fun export(review: RecordedActivityReview) = viewModelScope.launch {
        val snapshot = review.snapshot
        val sessionId = snapshot.sessionId ?: return@launch
        val start = snapshot.startedAtEpochMilliseconds ?: return@launch
        val end = snapshot.recordedAtEpochMilliseconds.takeIf { it > start } ?: System.currentTimeMillis()
        val saved = accountId?.let { activities.activity(it, sessionId) }
        val heartRate = saved?.averageHeartRateBpm?.let {
            listOf(HealthHeartRateSample(Instant.ofEpochMilli(start + (end - start) / 2), it.toLong()))
        }.orEmpty()
        health.write(HealthActivity(
            HealthSourceIdentity(context.packageName, sessionId),
            when (snapshot.activityKind) { ActivityKind.WALKING -> HealthActivityType.WALK; ActivityKind.CYCLING -> HealthActivityType.CYCLE; else -> HealthActivityType.RUN },
            saved?.title, Instant.ofEpochMilli(start), Instant.ofEpochMilli(end), snapshot.distanceMeters,
            saved?.energyKilocalories?.toDouble(),
            snapshot.track.map { HealthRoutePoint(Instant.ofEpochMilli(it.capturedAtEpochMilliseconds), it.latitude, it.longitude, it.altitudeMeters, it.horizontalAccuracyMeters, it.verticalAccuracyMeters) },
            heartRate = heartRate,
        ))
    }
}
