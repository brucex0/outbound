package com.plainstride.outbound.core.database

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Entity(
    tableName = "account_cache",
    primaryKeys = ["accountId", "namespace", "cacheKey", "localeTag"],
    indices = [Index(value = ["accountId", "namespace", "expiresAtEpochMs"])],
)
data class AccountCacheEntity(
    val accountId: String,
    val namespace: String,
    val cacheKey: String,
    val localeTag: String,
    val payloadJson: String,
    val etag: String?,
    val updatedAtEpochMs: Long,
    val expiresAtEpochMs: Long?,
)

@Dao
interface AccountCacheDao {
    @Query(
        """SELECT * FROM account_cache
           WHERE accountId = :accountId AND namespace = :namespace
             AND cacheKey = :cacheKey AND localeTag = :localeTag
           LIMIT 1""",
    )
    fun observe(
        accountId: String,
        namespace: String,
        cacheKey: String,
        localeTag: String,
    ): Flow<AccountCacheEntity?>

    @Query(
        """SELECT * FROM account_cache
           WHERE accountId = :accountId AND namespace = :namespace
             AND cacheKey = :cacheKey AND localeTag = :localeTag
           LIMIT 1""",
    )
    suspend fun get(
        accountId: String,
        namespace: String,
        cacheKey: String,
        localeTag: String,
    ): AccountCacheEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: AccountCacheEntity)

    @Query("DELETE FROM account_cache WHERE accountId = :accountId AND expiresAtEpochMs IS NOT NULL AND expiresAtEpochMs <= :nowEpochMs")
    suspend fun deleteExpired(accountId: String, nowEpochMs: Long): Int

    @Query("DELETE FROM account_cache WHERE accountId = :accountId")
    suspend fun deleteForAccount(accountId: String)
}
