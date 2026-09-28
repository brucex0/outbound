package com.plainstride.outbound.feature.recording

import android.content.Context
import android.media.AudioManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.Locale
import javax.inject.Inject
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.assistant.AndroidSpeechRecognizer
import com.plainstride.outbound.core.assistant.LiveVoiceCommand
import com.plainstride.outbound.core.assistant.LiveVoiceCommandHandler
import com.plainstride.outbound.core.assistant.LiveVoiceCommandParser
import com.plainstride.outbound.core.assistant.LiveWorkoutVoiceActions
import com.plainstride.outbound.core.assistant.SpeechRecognitionState
import com.plainstride.outbound.core.music.MusicProvider

/** Owns recording voice and music commands so the recording ViewModel stays transport-agnostic. */
class RecordingVoiceCoordinator @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val music: MusicProvider,
    private val analytics: ProductAnalytics,
) : AutoCloseable {
    private val recognizer = AndroidSpeechRecognizer(context)
    private val mutableListening = MutableStateFlow(false)
    val listening: StateFlow<Boolean> = mutableListening.asStateFlow()
    private var textToSpeech: TextToSpeech? = null
    private var textToSpeechReady = false
    private var textToSpeechInitialization: CompletableDeferred<Boolean>? = null
    private val pendingSpeech = ArrayDeque<QueuedSpeech>()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun observe(
        scope: CoroutineScope,
        snapshot: () -> RecordingSnapshot,
        pause: () -> Unit,
        resume: () -> Unit,
        requestFinish: () -> Unit,
    ) {
        val handler = LiveVoiceCommandHandler(object : LiveWorkoutVoiceActions {
            override suspend fun pauseWorkout() = pause()
            override suspend fun resumeWorkout() = resume()
            override suspend fun requestFinishWorkout() = requestFinish()
            override suspend fun speakCurrentStats() {
                val current = snapshot()
                val message = context.getString(
                    R.string.recording_spoken_stats,
                    formatDuration(current.elapsedSeconds),
                    formatDistance(current.distanceMeters),
                    formatPace(current.currentPaceSecondsPerKilometer),
                )
                speak(message, TextToSpeech.QUEUE_FLUSH, "live_stats")
            }
            override suspend fun pauseMusic() { music.pause() }
            override suspend fun resumeMusic() { music.resume() }
            override suspend fun skipMusic() { music.skipNext() }
        })
        scope.launch {
            recognizer.state.collect { state ->
                mutableListening.value = state is SpeechRecognitionState.Listening
                val transcript = (state as? SpeechRecognitionState.Result)?.transcript ?: return@collect
                val command = LiveVoiceCommandParser.parse(transcript)
                if (command != null) handler.handle(command)
                analytics.record(
                    AnalyticsEvent(
                        "live_voice_command",
                        mapOf(
                            AnalyticsProperty.Result to (command?.analyticsName ?: "unrecognized"),
                            AnalyticsProperty.Source to "recording",
                        ),
                    ),
                )
            }
        }
    }

    fun listen(permissionGranted: Boolean) = recognizer.start(permissionGranted)

    suspend fun prepare(): Boolean {
        if (textToSpeechReady) {
            logDebug("tts_prepare_result=already_ready")
            return true
        }
        val initialization = ensureTextToSpeech()
        val initialized = withTimeoutOrNull(TEXT_TO_SPEECH_PREPARE_TIMEOUT_MS) { initialization.await() }
        val result = initialized == true
        logDebug("tts_prepare_result=${when { result -> "ready"; initialized == null -> "timeout"; else -> "unavailable" }}")
        return result
    }

    fun speakCountdown(value: Int) = speak(value.toString(), TextToSpeech.QUEUE_ADD, "countdown_$value")

    fun speakGo() = speak(context.getString(R.string.recording_go), TextToSpeech.QUEUE_ADD, "countdown_go")

    fun stopSpeech() {
        pendingSpeech.clear()
        textToSpeech?.stop()
    }

    private fun speak(message: String, queueMode: Int, cue: String) {
        val existing = textToSpeech
        if (existing != null && textToSpeechReady) {
            speakNow(existing, message, queueMode, cue)
            return
        }
        if (queueMode == TextToSpeech.QUEUE_FLUSH) pendingSpeech.clear()
        pendingSpeech.addLast(QueuedSpeech(message, queueMode, cue))
        logDebug("tts_queue cue=$cue engineReady=$textToSpeechReady pending=${pendingSpeech.size}")
        ensureTextToSpeech()
    }

    private fun ensureTextToSpeech(): CompletableDeferred<Boolean> {
        if (textToSpeechReady) return CompletableDeferred(true)
        textToSpeechInitialization?.let { return it }
        val initialization = CompletableDeferred<Boolean>()
        textToSpeechInitialization = initialization
        logDebug("tts_init_start")
        textToSpeech = TextToSpeech(context.applicationContext) { status ->
            // Always post so the constructor assignment above completes before the callback reads it.
            mainHandler.post { completeTextToSpeechInitialization(status, initialization) }
        }
        return initialization
    }

    private fun completeTextToSpeechInitialization(status: Int, initialization: CompletableDeferred<Boolean>) {
        val engine = textToSpeech?.takeIf { status == TextToSpeech.SUCCESS }
        val readyEngine = engine?.takeIf(::selectSpeechLanguage)
        val ready = readyEngine != null
        textToSpeechReady = ready
        logDebug("tts_init_result status=$status ready=$ready queued=${pendingSpeech.size}")
        if (readyEngine != null) {
            readyEngine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = logDebug("tts_playback_start utterance=$utteranceId")
                override fun onDone(utteranceId: String?) = logDebug("tts_playback_done utterance=$utteranceId")
                override fun onError(utteranceId: String?) = logError("tts_playback_error utterance=$utteranceId")
                override fun onError(utteranceId: String?, errorCode: Int) =
                    logError("tts_playback_error utterance=$utteranceId code=$errorCode")
            })
            while (pendingSpeech.isNotEmpty()) {
                val pending = pendingSpeech.removeFirst()
                speakNow(readyEngine, pending.message, pending.queueMode, pending.cue)
            }
        } else {
            pendingSpeech.clear()
        }
        if (!initialization.isCompleted) initialization.complete(ready)
    }

    private fun selectSpeechLanguage(engine: TextToSpeech): Boolean {
        val preferred = preferredSpeechLocale()
        val candidates = listOf(preferred, Locale.forLanguageTag(preferred.language), Locale.US).distinct()
        for (locale in candidates) {
            val availability = engine.isLanguageAvailable(locale)
            val selected = if (availability >= TextToSpeech.LANG_AVAILABLE) engine.setLanguage(locale) else TextToSpeech.LANG_NOT_SUPPORTED
            logDebug("tts_locale candidate=${locale.toLanguageTag()} available=$availability selected=$selected")
            if (selected >= TextToSpeech.LANG_AVAILABLE) {
                return true
            }
        }
        logError("tts_locale_unavailable")
        return false
    }

    private fun preferredSpeechLocale(): Locale =
        context.resources.configuration.locales[0] ?: Locale.getDefault()

    private fun speakNow(engine: TextToSpeech, message: String, queueMode: Int, cue: String) {
        val utteranceId = "recording-speech-${System.nanoTime()}-$cue"
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val outputTypes = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map { it.type }.distinct()
        logDebug("tts_audio_route cue=$cue stream=tts ttsVolume=${audioManager.getStreamVolume(TEXT_TO_SPEECH_STREAM)}/${audioManager.getStreamMaxVolume(TEXT_TO_SPEECH_STREAM)} ttsMuted=${audioManager.isStreamMute(TEXT_TO_SPEECH_STREAM)} mediaVolume=${audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)}/${audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)} outputTypes=$outputTypes")
        val speechParams = Bundle().apply {
            putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, TEXT_TO_SPEECH_STREAM)
        }
        val result = engine.speak(message, queueMode, speechParams, utteranceId)
        if (result == TextToSpeech.SUCCESS) logDebug("tts_enqueue cue=$cue result=$result")
        else logError("tts_enqueue_failed cue=$cue result=$result")
    }

    private fun logDebug(message: String) {
        if (BuildConfig.DEBUG) Log.d(TAG, message)
    }

    private fun logError(message: String) {
        if (BuildConfig.DEBUG) Log.e(TAG, message)
    }

    override fun close() {
        recognizer.close()
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        textToSpeechReady = false
        textToSpeechInitialization?.takeUnless { it.isCompleted }?.complete(false)
        textToSpeechInitialization = null
        pendingSpeech.clear()
    }

    private companion object {
        const val TAG = "RecordingVoice"
        const val TEXT_TO_SPEECH_PREPARE_TIMEOUT_MS = 5_000L
        // STREAM_TTS is framework-defined as 9 but hidden from the public SDK.
        const val TEXT_TO_SPEECH_STREAM = 9
    }

    private data class QueuedSpeech(val message: String, val queueMode: Int, val cue: String)
}

private val LiveVoiceCommand.analyticsName: String
    get() = when (this) {
        LiveVoiceCommand.PauseWorkout -> "pause_workout"
        LiveVoiceCommand.ResumeWorkout -> "resume_workout"
        LiveVoiceCommand.FinishWorkout -> "request_finish"
        LiveVoiceCommand.ReadStats -> "read_stats"
        LiveVoiceCommand.PauseMusic -> "pause_music"
        LiveVoiceCommand.ResumeMusic -> "resume_music"
        LiveVoiceCommand.NextTrack -> "next_track"
    }
