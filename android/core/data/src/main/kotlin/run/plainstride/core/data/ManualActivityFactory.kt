package run.plainstride.core.data

import java.time.Instant
import java.util.UUID
import run.plainstride.core.model.activity.ActivitySource
import run.plainstride.core.model.activity.ActivityType
import run.plainstride.core.model.activity.SavedActivity

data class ManualActivityInput(
    val accountId: String,
    val type: ActivityType,
    val title: String,
    val startedAt: Instant,
    val durationSecs: Int,
    val distanceM: Double,
    val elevationGainM: Double? = null,
    val averageHeartRateBpm: Int? = null,
    val energyKilocalories: Int? = null,
)

object ManualActivityFactory {
    fun create(input: ManualActivityInput, now: Instant = Instant.now()): SavedActivity {
        require(input.accountId.isNotBlank())
        require(input.title.isNotBlank())
        require(input.durationSecs > 0)
        require(input.distanceM >= 0 && input.distanceM.isFinite())
        require(input.elevationGainM == null || input.elevationGainM >= 0)
        val id = UUID.randomUUID().toString()
        return SavedActivity(
            id = id,
            accountId = input.accountId,
            type = input.type,
            title = input.title.trim(),
            createdAt = now.toString(),
            startedAt = input.startedAt.toString(),
            endedAt = input.startedAt.plusSeconds(input.durationSecs.toLong()).toString(),
            durationSecs = input.durationSecs,
            distanceM = input.distanceM,
            averagePaceSecsPerKm = input.distanceM.takeIf { it > 0 }?.let { input.durationSecs / (it / 1_000.0) },
            elevationGainM = input.elevationGainM,
            averageHeartRateBpm = input.averageHeartRateBpm,
            energyKilocalories = input.energyKilocalories,
            source = ActivitySource(kind = "manual", displayName = "Manual entry"),
            localUpdatedAt = now.toString(),
        )
    }
}
