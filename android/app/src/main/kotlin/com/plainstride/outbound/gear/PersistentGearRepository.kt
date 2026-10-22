package com.plainstride.outbound.gear

import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.first
import androidx.room.withTransaction
import com.plainstride.outbound.core.database.GearEntity
import com.plainstride.outbound.core.database.PlainstrideDatabase
import com.plainstride.outbound.feature.progress.*

class PersistentGearRepository @Inject constructor(
    private val database: PlainstrideDatabase,
) : GearRepository {
    private var accountId: String? = null
    override suspend fun configure(accountId: String) { this.accountId = accountId }
    override suspend fun collection(): GearCollection {
        val id = accountId ?: return GearCollection()
        val entities = database.gearDao().forAccount(id)
        val shoes = entities.mapNotNull { runCatching { it.toDomain() }.getOrNull() }
        val defaultId = entities.firstOrNull { it.isDefault }?.gearId?.let { runCatching { UUID.fromString(it) }.getOrNull() }
        return GearCollection(shoes, defaultId?.takeIf { id -> shoes.any { it.id == id } })
    }
    override suspend fun replace(collection: GearCollection) {
        val id = accountId ?: return
        database.withTransaction {
            database.gearDao().deleteForAccount(id)
            if (collection.shoes.isNotEmpty()) database.gearDao().upsert(collection.shoes.map { it.toEntity(id, collection.defaultShoeId) })
        }
    }

}

private fun GearItem.toEntity(accountId:String,defaultId:UUID?)=GearEntity(accountId,id.toString(),purpose.name,name,brand,model,startedAt.toEpochMilli(),retiredAt?.toEpochMilli(),distanceLimitMeters,notes,id==defaultId)
private fun GearEntity.toDomain()=GearItem(UUID.fromString(gearId),GearPurpose.valueOf(purpose),name,brand,model,Instant.ofEpochMilli(startedAtEpochMs),retiredAtEpochMs?.let(Instant::ofEpochMilli),distanceLimitMeters,notes)
