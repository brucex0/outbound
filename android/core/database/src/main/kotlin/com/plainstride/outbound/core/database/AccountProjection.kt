package com.plainstride.outbound.core.database

import androidx.room.*
import kotlinx.coroutines.flow.Flow

/** One durable baseline and read cursor for the account, including known no-plan snapshots. */
@Entity(tableName = "account_projections")
data class AccountProjectionEntity(
    @PrimaryKey val accountId: String,
    val planningJson: String? = null,
    val planningRevision: Long = -1,
    val requiredPlanningRevision: Long = 0,
    val planningDirty: Boolean = true,
    val statisticsJson: String? = null,
    val statisticsRevision: Long = -1,
    val requiredStatisticsRevision: Long = 0,
    val statisticsTicket: Long = 0,
    val statisticsDirty: Boolean = true,
    val planningUpdatedAtEpochMs: Long = 0,
)

/** Exact receipt and server association survive upload acknowledgement and history deletion. */
@Entity(tableName = "activity_completions", primaryKeys = ["accountId", "activityId"])
data class ActivityCompletionEntity(
    val accountId: String,
    val activityId: String,
    val generation: Long,
    val plannedWorkoutId: String,
    val receiptJson: String?,
    val state: String,
    val canonicalCompletionJson: String? = null,
    val rejectionCode: String? = null,
    val acceptedPlanningRevision: Long? = null,
)

data class AccountProjectionWithCompletions(
    @Embedded val baseline: AccountProjectionEntity,
    @Relation(parentColumn = "accountId", entityColumn = "accountId")
    val completions: List<ActivityCompletionEntity>,
)

@Dao
interface AccountProjectionDao {
    @Transaction
    @Query("SELECT * FROM account_projections WHERE accountId = :accountId")
    fun observe(accountId: String): Flow<AccountProjectionWithCompletions?>
    @Transaction
    @Query("SELECT * FROM account_projections WHERE accountId = :accountId")
    suspend fun snapshot(accountId: String): AccountProjectionWithCompletions?
    @Query("SELECT * FROM account_projections WHERE accountId = :accountId")
    suspend fun get(accountId: String): AccountProjectionEntity?
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(value: AccountProjectionEntity)
    @Query("SELECT * FROM activity_completions WHERE accountId = :accountId AND activityId = :activityId")
    suspend fun completion(accountId: String, activityId: String): ActivityCompletionEntity?
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertCompletion(value: ActivityCompletionEntity)
    @Query("DELETE FROM activity_completions WHERE accountId = :accountId AND activityId = :activityId AND canonicalCompletionJson IS NULL")
    suspend fun removeUnconfirmed(accountId: String, activityId: String)
    @Query("DELETE FROM activity_completions WHERE accountId = :accountId")
    suspend fun deleteCompletions(accountId: String)
    @Query("DELETE FROM account_projections WHERE accountId = :accountId")
    suspend fun deleteForAccount(accountId: String)
}
