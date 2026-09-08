package com.plainstride.outbound.core.database

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Entity(
    tableName = "sync_outbox",
    indices = [
        Index(value = ["idempotencyKey"], unique = true),
        Index(value = ["accountId", "state", "nextAttemptAtEpochMs"]),
    ],
)
data class SyncOutboxEntity(
    @androidx.room.PrimaryKey val operationId: String,
    val accountId: String,
    val aggregateType: String,
    val aggregateId: String,
    val operationType: String,
    val idempotencyKey: String,
    val payloadJson: String,
    val createdAtEpochMs: Long,
    val attemptCount: Int = 0,
    val nextAttemptAtEpochMs: Long,
    val state: String = STATE_PENDING,
) {
    companion object {
        const val STATE_PENDING = "pending"
        const val STATE_IN_FLIGHT = "in_flight"
    }
}

@Dao
interface SyncOutboxDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun enqueue(entity: SyncOutboxEntity): Long

    @Query(
        """SELECT * FROM sync_outbox
           WHERE accountId = :accountId AND state = 'pending' AND nextAttemptAtEpochMs <= :nowEpochMs
           ORDER BY createdAtEpochMs ASC LIMIT :limit""",
    )
    suspend fun pending(accountId: String, nowEpochMs: Long, limit: Int): List<SyncOutboxEntity>

    @Query("SELECT COUNT(*) FROM sync_outbox WHERE accountId = :accountId")
    fun observeCount(accountId: String): Flow<Int>

    @Query("SELECT COUNT(*) FROM sync_outbox WHERE accountId = :accountId")
    suspend fun count(accountId: String): Int

    @Query(
        """UPDATE sync_outbox SET state = 'in_flight'
           WHERE operationId = :operationId AND accountId = :accountId AND state = 'pending'""",
    )
    suspend fun claim(accountId: String, operationId: String): Int

    @Query(
        """UPDATE sync_outbox
           SET state = 'pending', attemptCount = attemptCount + 1, nextAttemptAtEpochMs = :nextAttemptAtEpochMs
           WHERE operationId = :operationId AND accountId = :accountId""",
    )
    suspend fun retry(accountId: String, operationId: String, nextAttemptAtEpochMs: Long): Int

    @Query("DELETE FROM sync_outbox WHERE operationId = :operationId AND accountId = :accountId")
    suspend fun acknowledge(accountId: String, operationId: String): Int

    @Query("DELETE FROM sync_outbox WHERE accountId = :accountId")
    suspend fun deleteForAccount(accountId: String)
}
