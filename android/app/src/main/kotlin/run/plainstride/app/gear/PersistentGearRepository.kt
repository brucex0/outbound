package run.plainstride.app.gear

import android.content.Context
import android.util.Base64
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.first
import run.plainstride.core.data.ActivityRepository
import run.plainstride.feature.progress.*

class PersistentGearRepository @Inject constructor(
    @param:ApplicationContext context: Context,
    private val activities: ActivityRepository,
) : GearRepository {
    private val preferences = context.getSharedPreferences("gear_repository_v1", Context.MODE_PRIVATE)
    private var accountId: String? = null
    override suspend fun configure(accountId: String) { this.accountId = accountId }
    override suspend fun collection(): GearCollection {
        val shoes = preferences.getStringSet("shoes", emptySet()).orEmpty().mapNotNull(::decode).sortedByDescending { it.startedAt }
        return GearCollection(shoes, preferences.getString("default", null)?.let { runCatching { UUID.fromString(it) }.getOrNull() })
    }
    override suspend fun replace(collection: GearCollection) {
        preferences.edit().putStringSet("shoes", collection.shoes.map(::encode).toSet()).putString("default", collection.defaultShoeId?.toString()).apply()
    }
    override suspend fun activityDistances(): List<ActivityGearDistance> {
        val id = accountId ?: return emptyList()
        return activities.observePage(id, 0, 500).first().activities.mapNotNull { activity ->
            val gearId = activity.gearJson?.let { raw -> UUID_REGEX.find(raw)?.value?.let { runCatching { UUID.fromString(it) }.getOrNull() } } ?: return@mapNotNull null
            ActivityGearDistance(gearId, activity.distanceM, Instant.parse(activity.startedAt))
        }
    }
    private fun encode(item: GearItem) = listOf(item.id, item.purpose.name, safe(item.name), safe(item.brand), safe(item.model), item.startedAt, item.retiredAt ?: "", item.distanceLimitMeters, safe(item.notes)).joinToString("|")
    private fun decode(raw: String): GearItem? = runCatching { raw.split('|').let { GearItem(UUID.fromString(it[0]), GearPurpose.valueOf(it[1]), unsafe(it[2]), unsafe(it[3]), unsafe(it[4]), Instant.parse(it[5]), it[6].takeIf(String::isNotBlank)?.let(Instant::parse), it[7].toDouble(), unsafe(it[8])) } }.getOrNull()
    private fun safe(value: String) = Base64.encodeToString(value.toByteArray(), Base64.NO_WRAP or Base64.URL_SAFE)
    private fun unsafe(value: String) = String(Base64.decode(value, Base64.NO_WRAP or Base64.URL_SAFE))
    private companion object { val UUID_REGEX = Regex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}") }
}
