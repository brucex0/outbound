package run.plainstride.feature.progress

import java.time.Instant
import java.util.UUID

enum class GearPurpose(
    val suggestedDistanceLimitMeters: Double,
    val suggestedRangeMeters: ClosedFloatingPointRange<Double>,
) {
    DAILY_TRAINER(640_000.0, 480_000.0..800_000.0),
    RACE(320_000.0, 240_000.0..400_000.0),
    TRAIL(800_000.0, 640_000.0..965_606.4),
    RECOVERY(640_000.0, 480_000.0..800_000.0),
}

data class GearItem(
    val id: UUID,
    val purpose: GearPurpose,
    val name: String,
    val brand: String,
    val model: String,
    val startedAt: Instant,
    val retiredAt: Instant? = null,
    val distanceLimitMeters: Double = purpose.suggestedDistanceLimitMeters,
    val notes: String = "",
) {
    val displayName: String
        get() = listOf(brand.trim(), model.trim()).filter { it.isNotEmpty() }.joinToString(" ").ifEmpty { name }
    val isRetired: Boolean get() = retiredAt != null
}

data class ActivityGearDistance(
    val gearId: UUID?,
    val distanceMeters: Double,
    val startedAt: Instant,
)

data class GearMileageSummary(
    val item: GearItem,
    val distanceMeters: Double,
    val lastUsedAt: Instant?,
) {
    val remainingMeters: Double get() = (item.distanceLimitMeters - distanceMeters).coerceAtLeast(0.0)
    val usageFraction: Double
        get() = if (item.distanceLimitMeters > 0) (distanceMeters / item.distanceLimitMeters).coerceIn(0.0, 1.0) else 0.0
    val retirementDue: Boolean get() = item.distanceLimitMeters > 0 && distanceMeters >= item.distanceLimitMeters
}

data class GearCollection(
    val shoes: List<GearItem> = emptyList(),
    val defaultShoeId: UUID? = null,
) {
    val activeShoes: List<GearItem> get() = shoes.filterNot(GearItem::isRetired)
    val defaultShoe: GearItem?
        get() = defaultShoeId?.let { id -> shoes.firstOrNull { it.id == id && !it.isRetired } } ?: activeShoes.firstOrNull()

    fun adding(
        name: String,
        brand: String,
        model: String,
        purpose: GearPurpose,
        distanceLimitMeters: Double = purpose.suggestedDistanceLimitMeters,
        notes: String = "",
        id: UUID = UUID.randomUUID(),
        now: Instant = Instant.now(),
    ): GearCollection {
        val shoe = GearItem(
            id = id,
            purpose = purpose,
            name = name.trim().ifEmpty { "Running Shoes" },
            brand = brand.trim(),
            model = model.trim(),
            startedAt = now,
            distanceLimitMeters = distanceLimitMeters.coerceAtLeast(0.0),
            notes = notes,
        )
        return copy(shoes = listOf(shoe) + shoes, defaultShoeId = defaultShoeId ?: shoe.id)
    }

    fun retiring(id: UUID, now: Instant = Instant.now()): GearCollection {
        if (shoes.none { it.id == id }) return this
        val updated = shoes.map { if (it.id == id && !it.isRetired) it.copy(retiredAt = now) else it }
        val nextDefault = if (defaultShoeId == id) updated.firstOrNull { !it.isRetired }?.id else defaultShoeId
        return copy(shoes = updated, defaultShoeId = nextDefault)
    }

    fun settingDefault(id: UUID): GearCollection =
        if (shoes.any { it.id == id && !it.isRetired }) copy(defaultShoeId = id) else this

    fun mileage(activities: List<ActivityGearDistance>): List<GearMileageSummary> = shoes.map { item ->
        val matching = activities.filter { it.gearId == item.id }
        GearMileageSummary(
            item = item,
            distanceMeters = matching.sumOf { it.distanceMeters.coerceAtLeast(0.0) },
            lastUsedAt = matching.maxOfOrNull { it.startedAt },
        )
    }
}

interface GearRepository {
    suspend fun collection(): GearCollection
    suspend fun replace(collection: GearCollection)
    suspend fun activityDistances(): List<ActivityGearDistance>
}
