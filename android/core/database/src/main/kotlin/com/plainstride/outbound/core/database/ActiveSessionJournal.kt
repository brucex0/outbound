package com.plainstride.outbound.core.database

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Entity(
    tableName = "active_session_journal",
    primaryKeys = ["accountId", "sessionId"],
    indices = [Index(value = ["accountId", "status", "updatedAtEpochMs"])],
)
data class ActiveSessionJournalEntity(
    val accountId: String,
    val sessionId: String,
    val activityType: String,
    val status: String,
    val revision: Long,
    val startedAtEpochMs: Long,
    val updatedAtEpochMs: Long,
    val stateJson: String,
)

@Dao
interface ActiveSessionJournalDao {
    @Query(
        """SELECT * FROM active_session_journal
           WHERE accountId = :accountId AND status != 'completed'
           ORDER BY updatedAtEpochMs DESC LIMIT 1""",
    )
    fun observeRecoverable(accountId: String): Flow<ActiveSessionJournalEntity?>

    @Query(
        """SELECT * FROM active_session_journal
           WHERE accountId = :accountId AND status != 'completed'
           ORDER BY updatedAtEpochMs DESC LIMIT 1""",
    )
    suspend fun recoverable(accountId: String): ActiveSessionJournalEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: ActiveSessionJournalEntity)

    @Query(
        """UPDATE active_session_journal
           SET status = :status, revision = :revision, updatedAtEpochMs = :updatedAtEpochMs,
               stateJson = :stateJson
           WHERE accountId = :accountId AND sessionId = :sessionId AND revision < :revision""",
    )
    suspend fun updateIfNewer(
        accountId: String,
        sessionId: String,
        status: String,
        revision: Long,
        updatedAtEpochMs: Long,
        stateJson: String,
    ): Int

    @Query("DELETE FROM active_session_journal WHERE accountId = :accountId AND sessionId = :sessionId")
    suspend fun delete(accountId: String, sessionId: String)

    @Query("DELETE FROM active_session_journal WHERE accountId = :accountId")
    suspend fun deleteForAccount(accountId: String)
}
