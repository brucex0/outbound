package run.plainstride.core.database

import androidx.room.Dao
import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Relation
import androidx.room.Transaction
import kotlinx.coroutines.flow.Flow

@Entity(
    tableName = "activities",
    indices = [
        Index(value = ["accountId", "startedAtEpochMs"]),
        Index(value = ["accountId", "serverActivityId"], unique = true),
        Index(value = ["accountId", "deletedAtEpochMs"]),
    ],
)
data class ActivityEntity(
    @PrimaryKey val activityId: String,
    val accountId: String,
    val serverActivityId: String?,
    val type: String,
    val title: String,
    val guideNudge: String,
    val reflectionJson: String?,
    val createdAtEpochMs: Long,
    val startedAtEpochMs: Long,
    val endedAtEpochMs: Long,
    val durationSecs: Int,
    val distanceM: Double,
    val averagePaceSecsPerKm: Double?,
    val elevationGainM: Double?,
    val walkingStepCount: Int?,
    val averageHeartRateBpm: Int?,
    val maximumHeartRateBpm: Int?,
    val heartRateSampleCount: Int?,
    val energyKilocalories: Int?,
    val sourceJson: String,
    val gearJson: String?,
    val goalJson: String?,
    val indoorJson: String?,
    val cadenceJson: String?,
    val heartRateZonesJson: String?,
    val activityEventId: String?,
    val followedRouteId: String?,
    val followedRouteCompleted: Boolean,
    val recognitionBadgeIdsJson: String,
    val localUpdatedAtEpochMs: Long,
    val serverUpdatedAtEpochMs: Long?,
    val deletedAtEpochMs: Long?,
)

@Entity(
    tableName = "activity_track_points",
    primaryKeys = ["activityId", "pointIndex"],
    indices = [Index("accountId"), Index("activityId")],
)
data class ActivityTrackPointEntity(
    val accountId: String,
    val activityId: String,
    val pointIndex: Int,
    val timestampEpochMs: Long,
    val latitude: Double,
    val longitude: Double,
    val altitude: Double?,
    val verticalAccuracy: Double?,
    val startsNewSegment: Boolean,
)

@Entity(
    tableName = "activity_splits",
    primaryKeys = ["activityId", "splitIndex"],
    indices = [Index("accountId"), Index("activityId")],
)
data class ActivitySplitEntity(
    val accountId: String,
    val activityId: String,
    val splitIndex: Int,
    val distanceM: Double,
    val durationSecs: Int,
    val paceSecsPerKm: Double?,
    val elevationGainM: Double?,
    val averageHeartRateBpm: Int?,
)

@Entity(
    tableName = "activity_photos",
    primaryKeys = ["activityId", "photoId"],
    indices = [Index("accountId"), Index("activityId"), Index("remotePhotoId")],
)
data class ActivityPhotoEntity(
    val accountId: String,
    val activityId: String,
    val photoId: String,
    val takenAtEpochMs: Long,
    val paceAtShot: Double?,
    val heartRateAtShot: Int?,
    val distanceAtShotM: Double?,
    val latitude: Double?,
    val longitude: Double?,
    val captureContext: String?,
    val localRelativePath: String?,
    val remotePhotoId: String?,
    val remoteUpdatedAtEpochMs: Long?,
    val byteSize: Long?,
    val sha256: String?,
)

data class ActivityWithDetails(
    @Embedded val activity: ActivityEntity,
    @Relation(parentColumn = "activityId", entityColumn = "activityId")
    val track: List<ActivityTrackPointEntity>,
    @Relation(parentColumn = "activityId", entityColumn = "activityId")
    val splits: List<ActivitySplitEntity>,
    @Relation(parentColumn = "activityId", entityColumn = "activityId")
    val photos: List<ActivityPhotoEntity>,
)

@Dao
interface ActivityDao {
    @Query("SELECT * FROM activities WHERE accountId = :accountId AND deletedAtEpochMs IS NULL ORDER BY startedAtEpochMs DESC LIMIT :limit OFFSET :offset")
    fun observePage(accountId: String, limit: Int, offset: Int): Flow<List<ActivityEntity>>

    @Transaction
    @Query("SELECT * FROM activities WHERE accountId = :accountId AND activityId = :activityId LIMIT 1")
    suspend fun get(accountId: String, activityId: String): ActivityWithDetails?

    @Transaction
    @Query("SELECT * FROM activities WHERE accountId = :accountId AND activityId IN (:activityIds)")
    suspend fun getMany(accountId: String, activityIds: List<String>): List<ActivityWithDetails>

    @Query("SELECT COUNT(*) FROM activities WHERE accountId = :accountId AND deletedAtEpochMs IS NULL")
    suspend fun activeCount(accountId: String): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertActivity(entity: ActivityEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertTrack(points: List<ActivityTrackPointEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSplits(splits: List<ActivitySplitEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertPhotos(photos: List<ActivityPhotoEntity>)

    @Query("DELETE FROM activity_track_points WHERE accountId = :accountId AND activityId = :activityId")
    suspend fun deleteTrack(accountId: String, activityId: String)

    @Query("DELETE FROM activity_splits WHERE accountId = :accountId AND activityId = :activityId")
    suspend fun deleteSplits(accountId: String, activityId: String)

    @Query("DELETE FROM activity_photos WHERE accountId = :accountId AND activityId = :activityId")
    suspend fun deletePhotos(accountId: String, activityId: String)

    @Query("UPDATE activities SET deletedAtEpochMs = :deletedAtEpochMs, localUpdatedAtEpochMs = :deletedAtEpochMs WHERE accountId = :accountId AND activityId = :activityId")
    suspend fun tombstone(accountId: String, activityId: String, deletedAtEpochMs: Long): Int

    @Query("DELETE FROM activity_track_points WHERE accountId = :accountId")
    suspend fun deleteAllTrack(accountId: String)
    @Query("DELETE FROM activity_splits WHERE accountId = :accountId")
    suspend fun deleteAllSplits(accountId: String)
    @Query("DELETE FROM activity_photos WHERE accountId = :accountId")
    suspend fun deleteAllPhotos(accountId: String)
    @Query("DELETE FROM activities WHERE accountId = :accountId")
    suspend fun deleteForAccount(accountId: String)
}
