package com.plainstride.outbound.core.data

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import com.plainstride.outbound.core.model.activity.SavedActivity

object ActivityExporter {
    private val prettyJson = Json { prettyPrint = true }

    fun gpx(activity: SavedActivity): String = buildString {
        append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        append("<gpx version=\"1.1\" creator=\"Plainstride\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><name>")
        append(activity.title.xmlEscaped()).append("</name><trkseg>")
        activity.track.forEachIndexed { index, point ->
            if (index > 0 && point.startsNewSegment) append("</trkseg><trkseg>")
            append("<trkpt lat=\"").append(point.latitude).append("\" lon=\"").append(point.longitude).append("\">")
            point.altitude?.let { append("<ele>").append(it).append("</ele>") }
            append("<time>").append(point.timestamp.xmlEscaped()).append("</time></trkpt>")
        }
        append("</trkseg></trk></gpx>")
    }

    fun geoJson(activity: SavedActivity): String = prettyJson.encodeToString(
        buildJsonObject {
            put("type", "Feature")
            put("properties", buildJsonObject {
                put("name", activity.title)
                put("activityType", activity.type.name)
                put("startedAt", activity.startedAt)
                put("distanceM", activity.distanceM)
                put("durationSecs", activity.durationSecs)
            })
            put("geometry", buildJsonObject {
                put("type", "LineString")
                put("coordinates", buildJsonArray {
                    activity.track.forEach { point ->
                        add(buildJsonArray {
                            add(kotlinx.serialization.json.JsonPrimitive(point.longitude))
                            add(kotlinx.serialization.json.JsonPrimitive(point.latitude))
                            point.altitude?.let { add(kotlinx.serialization.json.JsonPrimitive(it)) }
                        })
                    }
                })
            })
        },
    )

    private fun String.xmlEscaped() = replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&apos;")
}
