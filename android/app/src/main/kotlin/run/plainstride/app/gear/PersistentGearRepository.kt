package run.plainstride.app.gear

import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.first
import androidx.room.withTransaction
import run.plainstride.core.data.ActivityRepository
import run.plainstride.core.database.GearEntity
import run.plainstride.core.database.PlainstrideDatabase
import run.plainstride.feature.progress.*

class PersistentGearRepository @Inject constructor(
    private val database: PlainstrideDatabase,
    private val activities: ActivityRepository,
) : GearRepository {
    private var accountId: String? = null
    override suspend fun configure(accountId: String) { this.accountId = accountId }
    override suspend fun collection(): GearCollection {
        val id = accountId ?: return GearCollection()
        val entities = database.gearDao().forAccount(id)
        return GearCollection(entities.map(GearEntity::toDomain), entities.firstOrNull { it.isDefault }?.gearId?.let(UUID::fromString))
    }
    override suspend fun replace(collection: GearCollection) {
        val id = accountId ?: return
        database.withTransaction {
            database.gearDao().deleteForAccount(id)
            if (collection.shoes.isNotEmpty()) database.gearDao().upsert(collection.shoes.map { it.toEntity(id, collection.defaultShoeId) })
        }
    }
    override suspend fun activityDistances(): List<ActivityGearDistance> {
        val id = accountId ?: return emptyList()
        return activities.observePage(id, 0, 500).first().activities.mapNotNull { activity ->
            val gearId = activity.gearJson?.let { raw -> UUID_REGEX.find(raw)?.value?.let { runCatching { UUID.fromString(it) }.getOrNull() } } ?: return@mapNotNull null
            ActivityGearDistance(gearId, activity.distanceM, Instant.parse(activity.startedAt))
        }
    }
    private companion object { val UUID_REGEX = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}") }
}

private fun GearItem.toEntity(accountId:String,defaultId:UUID?)=GearEntity(accountId,id.toString(),purpose.name,name,brand,model,startedAt.toEpochMilli(),retiredAt?.toEpochMilli(),distanceLimitMeters,notes,id==defaultId)
private fun GearEntity.toDomain()=GearItem(UUID.fromString(gearId),GearPurpose.valueOf(purpose),name,brand,model,Instant.ofEpochMilli(startedAtEpochMs),retiredAtEpochMs?.let(Instant::ofEpochMilli),distanceLimitMeters,notes)
