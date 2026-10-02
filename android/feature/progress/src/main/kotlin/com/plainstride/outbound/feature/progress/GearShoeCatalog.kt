package com.plainstride.outbound.feature.progress

import java.text.Normalizer
import java.util.Locale

data class GearShoeCatalogEntry(
    val brand: String,
    val model: String,
    val purpose: GearPurpose,
    val distanceLimitMeters: Double?,
) {
    val displayName: String get() = "$brand $model"
}

object GearShoeCatalog {
    val entries = listOf(
        GearShoeCatalogEntry("ASICS", "Novablast 5", GearPurpose.DAILY_TRAINER, 640_000.0),
        GearShoeCatalogEntry("ASICS", "Gel-Nimbus 27", GearPurpose.RECOVERY, 640_000.0),
        GearShoeCatalogEntry("ASICS", "Metaspeed Sky Paris", GearPurpose.RACE, 320_000.0),
        GearShoeCatalogEntry("Brooks", "Ghost 16", GearPurpose.DAILY_TRAINER, 640_000.0),
        GearShoeCatalogEntry("Brooks", "Glycerin 22", GearPurpose.RECOVERY, 640_000.0),
        GearShoeCatalogEntry("Hoka", "Clifton 10", GearPurpose.DAILY_TRAINER, 640_000.0),
        GearShoeCatalogEntry("Hoka", "Bondi 9", GearPurpose.RECOVERY, 640_000.0),
        GearShoeCatalogEntry("Hoka", "Speedgoat 6", GearPurpose.TRAIL, 800_000.0),
        GearShoeCatalogEntry("New Balance", "Fresh Foam X 1080v14", GearPurpose.DAILY_TRAINER, 640_000.0),
        GearShoeCatalogEntry("New Balance", "FuelCell Rebel v4", GearPurpose.DAILY_TRAINER, 560_000.0),
        GearShoeCatalogEntry("Nike", "Pegasus 41", GearPurpose.DAILY_TRAINER, 640_000.0),
        GearShoeCatalogEntry("Nike", "Vaporfly 3", GearPurpose.RACE, 320_000.0),
        GearShoeCatalogEntry("Nike", "Zegama 2", GearPurpose.TRAIL, 800_000.0),
        GearShoeCatalogEntry("On", "Cloudmonster 2", GearPurpose.DAILY_TRAINER, 640_000.0),
        GearShoeCatalogEntry("On", "Cloudsurfer", GearPurpose.RECOVERY, 640_000.0),
        GearShoeCatalogEntry("Saucony", "Ride 18", GearPurpose.DAILY_TRAINER, 640_000.0),
        GearShoeCatalogEntry("Saucony", "Endorphin Speed 4", GearPurpose.RACE, 480_000.0),
        GearShoeCatalogEntry("Saucony", "Peregrine 15", GearPurpose.TRAIL, 800_000.0),
    )

    fun bestMatch(query: String, purpose: GearPurpose): GearShoeCatalogEntry? {
        val normalizedQuery = normalize(query)
        if (normalizedQuery.length < 2) return null
        return entries.asSequence()
            .map { entry -> entry to score(entry, normalizedQuery, purpose) }
            .filter { (_, score) -> score > 0 }
            .sortedWith(compareByDescending<Pair<GearShoeCatalogEntry, Int>> { it.second }.thenBy { it.first.displayName })
            .firstOrNull()?.first
    }

    private fun score(entry: GearShoeCatalogEntry, query: String, purpose: GearPurpose): Int {
        val brand = normalize(entry.brand)
        val model = normalize(entry.model)
        val combined = normalize(entry.displayName)
        val queryTokens = tokens(query)
        val entryTokens = tokens(combined)
        var score = if (entry.purpose == purpose) 3 else 0
        if (queryTokens.any { queryToken -> entryTokens.none { it.startsWith(queryToken) } }) return 0
        if (combined == query) score += 100
        if (combined.startsWith(query)) score += 40
        if (brand.startsWith(query) || model.startsWith(query)) score += 28
        queryTokens.forEach { token ->
            score += when {
                brand.startsWith(token) || model.startsWith(token) -> 10
                entryTokens.any { it.startsWith(token) } -> 4
                else -> 0
            }
        }
        return score
    }

    private fun normalize(value: String): String = Normalizer.normalize(value, Normalizer.Form.NFD)
        .replace(Regex("\\p{Mn}+"), "")
        .lowercase(Locale.getDefault())
        .replace('-', ' ')
        .trim()

    private fun tokens(value: String): List<String> = normalize(value).split(Regex("\\s+")).filter(String::isNotEmpty)
}
