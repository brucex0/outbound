package com.plainstride.outbound.feature.recording

import android.content.Context
import android.media.AudioAttributes
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
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
    private val pendingSpeech = ArrayDeque<Pair<String, Int>>()
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
                speak(message, TextToSpeech.QUEUE_FLUSH)
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
        if (textToSpeechReady) return true
        val initialization = ensureTextToSpeech()
        return withTimeoutOrNull(TEXT_TO_SPEECH_PREPARE_TIMEOUT_MS) { initialization.await() } == true
    }

    fun speakCountdown(value: Int) = speak(value.toString(), TextToSpeech.QUEUE_ADD)

    fun speakGo() = speak(context.getString(R.string.recording_go), TextToSpeech.QUEUE_ADD)

    fun stopSpeech() {
        pendingSpeech.clear()
        textToSpeech?.stop()
    }

    private fun speak(message: String, queueMode: Int) {
        val existing = textToSpeech
        if (existing != null && textToSpeechReady) {
            speakNow(existing, message, queueMode)
            return
        }
        if (queueMode == TextToSpeech.QUEUE_FLUSH) pendingSpeech.clear()
        pendingSpeech.addLast(message to queueMode)
        ensureTextToSpeech()
    }

    private fun ensureTextToSpeech(): CompletableDeferred<Boolean> {
        if (textToSpeechReady) return CompletableDeferred(true)
        textToSpeechInitialization?.let { return it }
        val initialization = CompletableDeferred<Boolean>()
        textToSpeechInitialization = initialization
        textToSpeech = TextToSpeech(context.applicationContext) { status ->
            // Always post so the constructor assignment above completes before the callback reads it.
            mainHandler.post { completeTextToSpeechInitialization(status, initialization) }
        }
        return initialization
    }

    private fun completeTextToSpeechInitialization(status: Int, initialization: CompletableDeferred<Boolean>) {
        val engine = textToSpeech?.takeIf { status == TextToSpeech.SUCCESS }
        val ready = engine != null
        textToSpeechReady = ready
        if (ready) {
            engine.language = Locale.getDefault()
            engine.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            while (pendingSpeech.isNotEmpty()) {
                val (pendingMessage, pendingQueueMode) = pendingSpeech.removeFirst()
                speakNow(engine, pendingMessage, pendingQueueMode)
            }
        } else {
            pendingSpeech.clear()
        }
        if (!initialization.isCompleted) initialization.complete(ready)
    }

    private fun speakNow(engine: TextToSpeech, message: String, queueMode: Int) =
        engine.speak(message, queueMode, null, "recording-speech-${System.nanoTime()}")

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
        const val TEXT_TO_SPEECH_PREPARE_TIMEOUT_MS = 5_000L
    }
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
