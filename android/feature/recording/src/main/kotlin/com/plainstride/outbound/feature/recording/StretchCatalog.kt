package com.plainstride.outbound.feature.recording

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

internal data class StretchDefinition(
    val id: String, val title: Int, val instruction: Int, val bilateral: Boolean,
    val floor: Boolean, val support: Boolean, val surface: Boolean, val area: String,
    val lying: Boolean, val paths: List<List<Pair<Float, Float>>>,
    val dynamic: Boolean = false, val artwork: Int? = null,
    val artworkSide: String = "left", val alternating: Boolean = false, val cushion: Boolean = false,
)
internal data class StretchEntry(val movementID: String, val seconds: Int)
internal data class StretchTemplate(val id: String, val title: Int, val wireSuffix: String, val entries: List<StretchEntry>)

enum class StretchEntryPoint(val wireName: String) { POST_SAVE("post_save"), TODAY("today"), STANDALONE("standalone") }
data class StretchLaunchContext(val entryPoint: StretchEntryPoint = StretchEntryPoint.STANDALONE, val kind: ActivityKind? = null, val isIndoor: Boolean = false)

data class StretchSessionEvent(val name: String, val routineID: String?, val result: String?, val seconds: Int?, val source: StretchEntryPoint, val customized: Boolean, val postureCount: Int, val totalSeconds: Int)

data class StretchMovement(val id: String, val title: Int, val instruction: Int, val side: Int?, val seconds: Int, val cue: String)
data class StretchRoutine internal constructor(
    val id: String, val preferenceId: String, val title: Int,
    internal val entries: List<StretchEntry>, val customized: Boolean,
) {
    val isWarmup: Boolean get() = entries.any { StretchCatalog.definition(it.movementID)?.dynamic == true }
    val isStanding: Boolean get() = entries.none { StretchCatalog.definition(it.movementID)?.floor == true }
    val movements: List<StretchMovement> get() = entries.flatMap { entry ->
        val d = StretchCatalog.definition(entry.movementID) ?: return@flatMap emptyList()
        (if (d.bilateral) listOf("left", "right") else listOf("both")).map { side ->
            val resource = if (d.alternating) R.string.stretch_catalog_ui_alternating else when (side) { "left" -> R.string.recording_stretch_side_left; "right" -> R.string.recording_stretch_side_right; else -> R.string.recording_stretch_side_both }
            StretchMovement("${d.id}_$side", d.title, d.instruction, resource, entry.seconds, "${d.id}_$side")
        }
    }
    val totalSeconds: Int get() = movements.sumOf { it.seconds } + 3 + maxOf(0, movements.size - 1) * 5
    internal fun requirements(context: Context): String {
        val definitions = entries.mapNotNull { StretchCatalog.definition(it.movementID) }
        val keys = buildList {
            if (definitions.any { it.floor }) add(R.string.stretch_catalog_ui_floor)
            if (definitions.any { it.support }) add(R.string.stretch_catalog_ui_wall)
            if (definitions.any { it.surface }) add(R.string.stretch_catalog_ui_surface)
            if (definitions.any { it.cushion }) add(R.string.stretch_catalog_ui_cushion)
        }
        return (keys.ifEmpty { listOf(R.string.stretch_catalog_ui_none) }).joinToString(" · ") { context.getString(it) }
    }
}
internal object StretchCatalog {
    val durations = listOf(15, 20, 25, 30)
    fun definition(id: String) = StretchCatalogData.definitions.firstOrNull { it.id == id }
    fun valid(entries: List<StretchEntry>) = entries.isNotEmpty() && entries.size <= 20 && entries.map { it.movementID }.distinct().size == entries.size && entries.all { definition(it.movementID) != null && it.seconds in durations } && entries.mapNotNull { definition(it.movementID)?.dynamic }.distinct().size == 1
    fun outdoorFallback(): StretchRoutine {
        val template = StretchCatalogData.templates.first()
        return StretchRoutine("stretch_outdoor_reset_v1", template.id, template.title, template.entries, false)
    }
    fun routines(context: Context, kind: ActivityKind?, entryPoint: StretchEntryPoint = StretchEntryPoint.STANDALONE): List<StretchRoutine> = StretchCatalogData.templates.filter { entryPoint != StretchEntryPoint.POST_SAVE || it.id != "pre_run" }.map { template ->
        val saved = StretchCustomizationStore(context).load(template.id)
        val suffix = template.wireSuffix
        val sport = when (kind) { ActivityKind.RUNNING -> "run"; ActivityKind.CYCLING -> "bike"; ActivityKind.HIKING -> "hike"; ActivityKind.SWIMMING -> "swim"; else -> null }
        StretchRoutine(if (sport == null) "stretch_$suffix" else "post_save_${sport}_$suffix", template.id, template.title, saved ?: template.entries, saved != null)
    }
}
internal class StretchCustomizationStore(context: Context) {
    private val preferences = context.getSharedPreferences("stretch_customizations_v1", Context.MODE_PRIVATE)
    fun load(id: String): List<StretchEntry>? {
        val json = preferences.getString(id, null) ?: return null
        return try {
            val array = JSONArray(json)
            val entries = (0 until array.length()).map { array.getJSONObject(it).let { row -> StretchEntry(row.getString("movementID"), row.getInt("seconds")) } }
            if (!StretchCatalog.valid(entries)) { Log.w("StretchCatalog", "Customization validation failed"); null } else entries
        } catch (error: Exception) { Log.w("StretchCatalog", "Customization decode failed type=${error.javaClass.simpleName}"); null }
    }
    fun save(id: String, entries: List<StretchEntry>?): Boolean {
        if (entries != null && !StretchCatalog.valid(entries)) { Log.w("StretchCatalog", "Customization save validation failed"); return false }
        val edit = preferences.edit()
        if (entries == null) edit.remove(id) else edit.putString(id, JSONArray().apply { entries.forEach { put(JSONObject().put("movementID", it.movementID).put("seconds", it.seconds)) } }.toString())
        // Commit on the editor's IO coroutine so failure can be surfaced before closing it.
        return edit.commit().also { if (!it) Log.w("StretchCatalog", "Customization persistence failed") }
    }
}
