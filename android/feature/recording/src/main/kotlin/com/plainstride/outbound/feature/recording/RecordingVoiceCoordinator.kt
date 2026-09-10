package com.plainstride.outbound.feature.recording

import android.content.Context
import android.speech.tts.TextToSpeech
import android.media.AudioAttributes
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.Locale
import javax.inject.Inject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
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
    private val pendingSpeech = ArrayDeque<Pair<String, Int>>()

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

    fun speakCountdown(value: Int) = speak(value.toString(), TextToSpeech.QUEUE_ADD)

    fun speakStart() = speak(context.getString(R.string.recording_start), TextToSpeech.QUEUE_ADD)

    private fun speak(message: String, queueMode: Int) {
        val existing = textToSpeech
        if (existing != null && textToSpeechReady) {
            speakNow(existing, message, queueMode)
            return
        }
        if (queueMode == TextToSpeech.QUEUE_FLUSH) pendingSpeech.clear()
        pendingSpeech.addLast(message to queueMode)
        if (existing != null) return
        textToSpeech = TextToSpeech(context.applicationContext) { status ->
            val engine = textToSpeech ?: return@TextToSpeech
            if (status == TextToSpeech.SUCCESS) {
                textToSpeechReady = true
                engine.language = Locale.getDefault()
                engine.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                while (pendingSpeech.isNotEmpty()) {
                    val (pendingMessage, pendingQueueMode) = pendingSpeech.removeFirst()
                    speakNow(engine, pendingMessage, pendingQueueMode)
                }
            } else {
                pendingSpeech.clear()
            }
        }
    }

    private fun speakNow(engine: TextToSpeech, message: String, queueMode: Int) =
        engine.speak(message, queueMode, null, "recording-speech-${System.nanoTime()}")

    override fun close() {
        recognizer.close()
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        textToSpeechReady = false
        pendingSpeech.clear()
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
