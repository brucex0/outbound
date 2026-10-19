package com.plainstride.outbound.core.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.withTransaction

private const val DATABASE_SCHEMA_VERSION = 5

@Database(
    entities = [
        AccountCacheEntity::class,
        SyncOutboxEntity::class,
        ActiveSessionJournalEntity::class,
        ActivityEntity::class,
        ActivityTrackPointEntity::class,
        ActivityOriginalRouteEntity::class,
        ActivitySplitEntity::class,
        ActivityPhotoEntity::class,
        GearEntity::class,
        CyclePreferenceEntity::class,
        CycleWellbeingEntity::class,
    ],
    version = DATABASE_SCHEMA_VERSION,
    exportSchema = true,
)
abstract class PlainstrideDatabase : RoomDatabase() {
    abstract fun accountCacheDao(): AccountCacheDao
    abstract fun syncOutboxDao(): SyncOutboxDao
    abstract fun activeSessionJournalDao(): ActiveSessionJournalDao
    abstract fun activityDao(): ActivityDao
    abstract fun gearDao(): GearDao
    abstract fun cycleWellbeingDao(): CycleWellbeingDao
}

/** Unreleased Android uses a fresh database per schema version; no migration readers. */
object PlainstrideDatabaseFactory {
    const val DATABASE_NAME = "plainstride-v$DATABASE_SCHEMA_VERSION.db"

    fun create(context: Context): PlainstrideDatabase =
        Room.databaseBuilder(
            context.applicationContext,
            PlainstrideDatabase::class.java,
            DATABASE_NAME,
        )
            .build()
}

class RoomTransactionRunner(
    private val database: PlainstrideDatabase,
) : TransactionRunner {
    override suspend fun <T> inTransaction(block: suspend () -> T): T =
        database.withTransaction(block)
}

class AccountDatabaseOperations(
    private val database: PlainstrideDatabase,
) {
    suspend fun clearAccount(accountId: String) {
        database.withTransaction {
            database.accountCacheDao().deleteForAccount(accountId)
            database.syncOutboxDao().deleteForAccount(accountId)
            database.activeSessionJournalDao().deleteForAccount(accountId)
            database.activityDao().deleteAllOriginalRoutes(accountId)
            database.activityDao().deleteAllTrack(accountId)
            database.activityDao().deleteAllSplits(accountId)
            database.activityDao().deleteAllPhotos(accountId)
            database.activityDao().deleteForAccount(accountId)
            database.gearDao().deleteForAccount(accountId)
            database.cycleWellbeingDao().deleteLogs(accountId)
            database.cycleWellbeingDao().deletePreference(accountId)
        }
    }

    suspend fun saveCacheAndEnqueue(
        cache: AccountCacheEntity,
        operation: SyncOutboxEntity,
    ): Boolean = database.withTransaction {
        require(cache.accountId == operation.accountId) { "Cache and operation must belong to one account." }
        database.accountCacheDao().upsert(cache)
        database.syncOutboxDao().enqueue(operation) != -1L
    }
}
