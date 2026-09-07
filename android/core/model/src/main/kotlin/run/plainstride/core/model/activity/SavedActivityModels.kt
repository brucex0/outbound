package run.plainstride.core.model.activity

import kotlinx.serialization.Serializable

@Serializable data class ActivitySource(val kind: String = "outbound", val displayName: String = "Plainstride", val deviceName: String? = null, val externalId: String? = null, val importedAt: String? = null)
@Serializable data class ActivityReflection(val title: String, val body: String, val highlight: String, val progressNote: String? = null)
@Serializable data class ActivityTrackPoint(val timestamp: String, val latitude: Double, val longitude: Double, val altitude: Double? = null, val verticalAccuracy: Double? = null, val startsNewSegment: Boolean = false)
@Serializable data class ActivitySplit(val index: Int, val distanceM: Double, val durationSecs: Int, val paceSecsPerKm: Double? = null, val elevationGainM: Double? = null, val averageHeartRateBpm: Int? = null)
@Serializable data class ActivityPhoto(
    val id: String, val takenAt: String, val paceAtShot: Double? = null, val heartRateAtShot: Int? = null,
    val distanceAtShotM: Double? = null, val latitude: Double? = null, val longitude: Double? = null,
    val captureContext: String? = null, val localRelativePath: String? = null, val remotePhotoId: String? = null,
    val remoteUpdatedAt: String? = null, val byteSize: Long? = null, val sha256: String? = null,
)

@Serializable
data class SavedActivity(
    val id: String,
    val accountId: String,
    val serverActivityId: String? = null,
    val type: ActivityType,
    val title: String,
    val guideNudge: String = "",
    val reflection: ActivityReflection? = null,
    val createdAt: String,
    val startedAt: String,
    val endedAt: String,
    val durationSecs: Int,
    val distanceM: Double,
    val averagePaceSecsPerKm: Double? = null,
    val elevationGainM: Double? = null,
    val walkingStepCount: Int? = null,
    val averageHeartRateBpm: Int? = null,
    val maximumHeartRateBpm: Int? = null,
    val heartRateSampleCount: Int? = null,
    val energyKilocalories: Int? = null,
    val source: ActivitySource = ActivitySource(),
    val gearJson: String? = null,
    val goalJson: String? = null,
    val indoorJson: String? = null,
    val cadenceJson: String? = null,
    val heartRateZonesJson: String? = null,
    val activityEventId: String? = null,
    val followedRouteId: String? = null,
    val followedRouteCompleted: Boolean = false,
    val recognitionBadgeIds: List<String> = emptyList(),
    val track: List<ActivityTrackPoint> = emptyList(),
    val splits: List<ActivitySplit> = emptyList(),
    val photos: List<ActivityPhoto> = emptyList(),
    val localUpdatedAt: String,
    val serverUpdatedAt: String? = null,
    val deletedAt: String? = null,
)

data class ActivityPage(val activities: List<SavedActivity>, val offset: Int, val limit: Int, val hasMore: Boolean)
