package com.plainstride.outbound.core.model.activity

import android.content.Context

/** Device-local launch choices; live Voice overrides stay within the recording journal. */
class ActivityAudioPreferences(context: Context) {
    val storage = context.getSharedPreferences("activity_audio", Context.MODE_PRIVATE)
    var voiceEnabled: Boolean
        get() = storage.getBoolean("voice_enabled", true)
        set(value) { storage.edit().putBoolean("voice_enabled", value).apply() }
    var aiCoachEnabled: Boolean
        get() = storage.getBoolean("ai_coach_enabled", true)
        set(value) { storage.edit().putBoolean("ai_coach_enabled", value).apply() }
}
