package com.plainstride.outbound.feature.assistant

import android.content.Context

internal enum class AssistantDestination(val routeId: String, val resource: Int, val summaryResource: Int, val terms: List<String>) {
    Today("today", R.string.assistant_destination_today, R.string.assistant_destination_today_summary, listOf("today", "workout", "readiness", "quick run", "start run")),
    Social("social", R.string.assistant_destination_social, R.string.assistant_destination_social_summary, listOf("social", "friends", "connections", "groups", "invitations")),
    Me("me", R.string.assistant_destination_me, R.string.assistant_destination_me_summary, listOf("me", "profile", "progress", "personal")),
    Settings("settings", R.string.assistant_destination_settings, R.string.assistant_destination_settings_summary, listOf("settings", "preferences", "account")),
    Appearance("settings", R.string.assistant_destination_appearance, R.string.assistant_destination_appearance_summary, listOf("appearance", "app theme", "theme", "color theme", "light mode", "dark mode")),
    ActivityHistory("activity_history", R.string.assistant_destination_history, R.string.assistant_destination_history_summary, listOf("activity history", "my activities", "past activities", "saved runs", "recent runs")),
    LiveGuidance("settings", R.string.assistant_destination_live_guidance, R.string.assistant_destination_live_guidance_summary, listOf("guide settings", "companion settings", "voice", "coaching tone", "spoken updates")),
    Health("health", R.string.assistant_destination_health, R.string.assistant_destination_health_summary, listOf("health", "health connect", "health permission")),
    Music("music", R.string.assistant_destination_music, R.string.assistant_destination_music_summary, listOf("music", "spotify", "playlist", "music permission")),
}

internal object AssistantDestinationRegistry {
    private val navigationWords = listOf("open", "show me", "take me", "go to", "navigate", "where", "find", "change", "choose", "pick")

    fun infer(prompt: String): AssistantDestination? {
        val normalized = prompt.lowercase()
        if (navigationWords.none(normalized::contains)) return null
        return AssistantDestination.entries
            .map { destination -> destination to destination.terms.sumOf { term -> if (normalized.contains(term)) term.length else 0 } }
            .maxByOrNull { it.second }
            ?.takeIf { it.second > 0 }
            ?.first
    }

    fun titleResource(destination: AssistantDestination) = destination.resource
    fun productContext(context: Context) = AssistantDestination.entries.joinToString("\n") {
        "${context.getString(it.resource)}: ${context.getString(it.summaryResource)}"
    }
}
