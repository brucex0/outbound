package run.plainstride.core.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.withTransaction

@Database(
    entities = [
        AccountCacheEntity::class,
        SyncOutboxEntity::class,
        ActiveSessionJournalEntity::class,
        ActivityEntity::class,
        ActivityTrackPointEntity::class,
        ActivitySplitEntity::class,
        ActivityPhotoEntity::class,
    ],
    version = 2,
    exportSchema = true,
)
abstract class PlainstrideDatabase : RoomDatabase() {
    abstract fun accountCacheDao(): AccountCacheDao
    abstract fun syncOutboxDao(): SyncOutboxDao
    abstract fun activeSessionJournalDao(): ActiveSessionJournalDao
    abstract fun activityDao(): ActivityDao
}

/** Single construction surface for DI. Database schema upgrades intentionally reset pre-release data. */
object PlainstrideDatabaseFactory {
    const val DATABASE_NAME = "plainstride.db"

    fun create(context: Context): PlainstrideDatabase =
        Room.databaseBuilder(
            context.applicationContext,
            PlainstrideDatabase::class.java,
            DATABASE_NAME,
        )
            .fallbackToDestructiveMigration(dropAllTables = true)
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
            database.activityDao().deleteAllTrack(accountId)
            database.activityDao().deleteAllSplits(accountId)
            database.activityDao().deleteAllPhotos(accountId)
            database.activityDao().deleteForAccount(accountId)
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
