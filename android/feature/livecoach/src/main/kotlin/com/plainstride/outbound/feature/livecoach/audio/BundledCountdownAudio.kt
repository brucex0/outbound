package com.plainstride.outbound.feature.livecoach.audio

import android.content.Context
import android.util.Log
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.network.PlainstrideJson
import com.plainstride.outbound.feature.livecoach.LiveCoachPreferencesRepository
import com.plainstride.outbound.feature.recording.RecordingCountdownAudio
import dagger.hilt.android.qualifiers.ApplicationContext
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.collectLatest
import com.plainstride.outbound.feature.livecoach.LiveCoachPreferences
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Reviewed source WAVs are bundled unchanged; first-install countdown never needs TTS or internet. */
@Singleton
class BundledCountdownAudio @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val preferences: LiveCoachPreferencesRepository,
    private val output: CoachAudioOutput,
    private val analytics: ProductAnalytics,
) : RecordingCountdownAudio {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val preparationLock = Mutex()
    @Volatile private var clips: Map<Int, ByteArray> = emptyMap()
    @Volatile private var selection: String? = null
    @Volatile private var latestPreferences: LiveCoachPreferences? = null
    private var playback: Job? = null
    private var playbackGeneration = 0

    init {
        scope.launch {
            preferences.preferences.collectLatest {
                latestPreferences = it
                prepare()
            }
        }
    }

    private fun identity(prefs: LiveCoachPreferences): String {
        val locale = when (context.resources.configuration.locales[0].language) {
            "zh" -> "zh-Hans"
            "es" -> "es"
            else -> "en"
        }
        return "$locale:${prefs.voiceProfileId}:${prefs.personaId}:${prefs.scriptStyleId}"
    }

    override fun isReady(): Boolean = latestPreferences?.let { selection == identity(it) && clips.size == KEYS.size } == true

    override suspend fun prepare(): Boolean = preparationLock.withLock {
        val prefs = preferences.preferences.first()
        val locale = when (context.resources.configuration.locales[0].language) {
            "zh" -> "zh-Hans"
            "es" -> "es"
            else -> "en"
        }
        latestPreferences = prefs
        val identity = identity(prefs)
        if (identity == selection && clips.size == KEYS.size) return@withLock true
        val loaded = withContext(Dispatchers.IO) {
            try {
                val manifest = context.assets.open("LiveCoachAudio/manifest.json").bufferedReader().use {
                    PlainstrideJson.decodeFromString<AudioPackManifest>(it.readText())
                }
                KEYS.mapValues { (_, cueKey) ->
                    val entry = manifest.entries.first { it.cueKey == cueKey && it.locale == locale &&
                        it.voiceProfileId == prefs.voiceProfileId && prefs.personaId in it.compatibleCoachPersonaIds &&
                        it.approved && it.scriptStyleId in setOf(prefs.scriptStyleId, "standard") }
                    val name = requireNotNull(entry.bundledResourceName)
                    context.assets.open("LiveCoachAudio/$name.wav").use { it.readBytes() }.also { bytes ->
                        check(bytes.size == entry.byteCount && WavPcm.isValid(bytes))
                        check(MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) } == entry.sha256)
                    }
                }
            } catch (error: Exception) {
                Log.w(TAG, "operation=prepare_countdown type=${error.javaClass.simpleName}")
                emptyMap()
            }
        }
        clips = loaded
        selection = identity
        loaded.size == KEYS.size
    }

    override fun play(value: Int) {
        val bytes = clips[value]?.takeIf { isReady() } ?: run {
            stop()
            Log.w(TAG, "operation=countdown_play result=unavailable")
            return
        }
        val previous = playback
        val generation = playbackGeneration
        playback = scope.launch {
            previous?.join() // Complete the prior word instead of clipping its audio tail.
            if (generation != playbackGeneration) return@launch
            val played = output.playWav(bytes)
            analytics.record(AnalyticsEvent("activity_voice_enqueue", mapOf(
                AnalyticsProperty.Source to if (value == 0) "countdown_go" else "countdown_$value",
                AnalyticsProperty.SourceType to "bundled_audio",
                AnalyticsProperty.Result to if (played) "success" else "failed",
            )))
            if (!played) Log.w(TAG, "operation=countdown_play result=failed")
        }
    }

    override fun durationMilliseconds(value: Int): Long =
        clips[value]?.let { WavPcm.decode(it)?.size?.toLong()?.times(1_000)?.div(48_000) } ?: 0

    override fun stop() {
        playbackGeneration += 1
        if (playback?.isActive == true) { output.stop(); playback?.cancel() }
        playback = null
    }

    private companion object {
        const val TAG = "PlainstrideCountdown"
        val KEYS = mapOf(5 to "countdown.five", 4 to "countdown.four", 3 to "countdown.three", 2 to "countdown.two", 1 to "countdown.one", 0 to "countdown.go")
    }
}
