package com.plainstride.outbound.core.database

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Entity(
    tableName = "gear",
    primaryKeys = ["accountId", "gearId"],
    indices = [Index("accountId"), Index(value = ["accountId", "isDefault"])],
)
data class GearEntity(
    val accountId: String,
    val gearId: String,
    val purpose: String,
    val name: String,
    val brand: String,
    val model: String,
    val startedAtEpochMs: Long,
    val retiredAtEpochMs: Long?,
    val distanceLimitMeters: Double,
    val notes: String,
    val isDefault: Boolean,
)

@Dao
interface GearDao {
    @Query("SELECT * FROM gear WHERE accountId = :accountId ORDER BY startedAtEpochMs DESC")
    suspend fun forAccount(accountId: String): List<GearEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(items: List<GearEntity>)

    @Query("DELETE FROM gear WHERE accountId = :accountId")
    suspend fun deleteForAccount(accountId: String)
}
