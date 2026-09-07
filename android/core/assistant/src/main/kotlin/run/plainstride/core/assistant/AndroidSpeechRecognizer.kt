package run.plainstride.core.assistant

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.io.Closeable
import java.util.Locale
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

sealed interface SpeechRecognitionState {
    data object Idle : SpeechRecognitionState
    data object PermissionRequired : SpeechRecognitionState
    data class Listening(val partialTranscript: String = "") : SpeechRecognitionState
    data class Result(val transcript: String) : SpeechRecognitionState
    data class Failure(val code: Int) : SpeechRecognitionState
}

class AndroidSpeechRecognizer(context: Context) : Closeable, RecognitionListener {
    private val recognizer = SpeechRecognizer.createSpeechRecognizer(context.applicationContext).also { it.setRecognitionListener(this) }
    private val mutableState = MutableStateFlow<SpeechRecognitionState>(SpeechRecognitionState.Idle)
    val state: StateFlow<SpeechRecognitionState> = mutableState.asStateFlow()

    fun start(permissionGranted: Boolean, locale: Locale = Locale.getDefault(), hints: List<String> = ActivityVoiceCommandParser.hints(locale)) {
        if (!permissionGranted) { mutableState.value = SpeechRecognitionState.PermissionRequired; return }
        recognizer.startListening(Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale.toLanguageTag())
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS, ArrayList(hints))
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        })
        mutableState.value = SpeechRecognitionState.Listening()
    }

    fun stop() = recognizer.stopListening()
    fun cancel() { recognizer.cancel(); mutableState.value = SpeechRecognitionState.Idle }
    override fun close() { recognizer.cancel(); recognizer.destroy(); mutableState.value = SpeechRecognitionState.Idle }
    override fun onPartialResults(results: Bundle) { best(results)?.let { mutableState.value = SpeechRecognitionState.Listening(it) } }
    override fun onResults(results: Bundle) { mutableState.value = best(results)?.let(SpeechRecognitionState::Result) ?: SpeechRecognitionState.Failure(SpeechRecognizer.ERROR_NO_MATCH) }
    override fun onError(error: Int) { mutableState.value = SpeechRecognitionState.Failure(error) }
    override fun onReadyForSpeech(params: Bundle?) = Unit
    override fun onBeginningOfSpeech() = Unit
    override fun onRmsChanged(rmsdB: Float) = Unit
    override fun onBufferReceived(buffer: ByteArray?) = Unit
    override fun onEndOfSpeech() = Unit
    override fun onEvent(eventType: Int, params: Bundle?) = Unit
    private fun best(bundle: Bundle) = bundle.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim()?.takeIf(String::isNotEmpty)
}
