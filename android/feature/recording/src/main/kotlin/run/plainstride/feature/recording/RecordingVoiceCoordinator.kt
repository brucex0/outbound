package run.plainstride.feature.recording

import android.content.Context
import android.speech.tts.TextToSpeech
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.Locale
import javax.inject.Inject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import run.plainstride.core.analytics.AnalyticsEvent
import run.plainstride.core.analytics.AnalyticsProperty
import run.plainstride.core.analytics.ProductAnalytics
import run.plainstride.core.assistant.AndroidSpeechRecognizer
import run.plainstride.core.assistant.LiveVoiceCommand
import run.plainstride.core.assistant.LiveVoiceCommandHandler
import run.plainstride.core.assistant.LiveVoiceCommandParser
import run.plainstride.core.assistant.LiveWorkoutVoiceActions
import run.plainstride.core.assistant.SpeechRecognitionState
import run.plainstride.core.music.MusicProvider

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
    private var pendingSpeech: String? = null

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
                speak(message)
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

    private fun speak(message: String) {
        pendingSpeech = message
        val existing = textToSpeech
        if (existing != null) {
            speakPending(existing)
            return
        }
        textToSpeech = TextToSpeech(context.applicationContext) { status ->
            textToSpeech?.takeIf { status == TextToSpeech.SUCCESS }?.let(::speakPending)
        }
    }

    private fun speakPending(engine: TextToSpeech) {
        val message = pendingSpeech ?: return
        pendingSpeech = null
        engine.language = Locale.getDefault()
        engine.speak(message, TextToSpeech.QUEUE_FLUSH, null, "recording-stats-${System.nanoTime()}")
    }

    override fun close() {
        recognizer.close()
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        pendingSpeech = null
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
