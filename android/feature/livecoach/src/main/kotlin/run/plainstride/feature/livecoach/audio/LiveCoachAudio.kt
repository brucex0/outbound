package run.plainstride.feature.livecoach.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.AudioTrack
import android.speech.tts.TextToSpeech
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.DataInputStream
import java.io.InputStream
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import run.plainstride.core.analytics.AnalyticsEvent
import run.plainstride.core.analytics.AnalyticsProperty
import run.plainstride.core.analytics.ProductAnalytics
import run.plainstride.feature.livecoach.network.CueEnvelope
import run.plainstride.feature.livecoach.network.CueRequest
import run.plainstride.feature.livecoach.network.LiveCoachMode
import run.plainstride.feature.livecoach.network.LiveCoachRepository
import run.plainstride.feature.livecoach.network.LiveCoachMoment

enum class PlaybackRoute { Speaker, Wired, Bluetooth, Usb, Unknown }
enum class PlaybackSource { Streaming, Inline, FixedPack, TextToSpeech, None }
data class PlaybackResult(val source: PlaybackSource, val played: Boolean)

class LiveCoachStreamReader(private val input: InputStream) {
    data class Frame(val type: Int, val payload: ByteArray)
    fun next(): Frame? = runCatching {
        val stream = DataInputStream(input)
        val type = stream.read()
        if (type < 0) return null
        val length = stream.readInt()
        require(length in 0..MAX_FRAME)
        Frame(type, ByteArray(length).also(stream::readFully))
    }.getOrNull()
    private companion object { const val MAX_FRAME = 1024 * 1024 }
}

interface CoachAudioOutput {
    suspend fun playPcm(chunks: suspend ((ByteArray) -> Unit) -> Unit): Boolean
    suspend fun playWav(bytes: ByteArray): Boolean
    suspend fun speak(text: String, locale: String): Boolean
    fun stop()
}

@Singleton
class AndroidCoachAudioOutput @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val analytics: ProductAnalytics,
) : CoachAudioOutput {
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) stop()
    }
    private val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK).setAudioAttributes(attributes).setOnAudioFocusChangeListener(focusListener).setWillPauseWhenDucked(false).build()
    private var track: AudioTrack? = null
    private var tts: TextToSpeech? = null
    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = reportRoute()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = reportRoute()
    }
    init { audioManager.registerAudioDeviceCallback(deviceCallback, null) }

    override suspend fun playPcm(chunks: suspend ((ByteArray) -> Unit) -> Unit): Boolean = withContext(Dispatchers.IO) {
        if (!focus()) return@withContext false
        val minimum = AudioTrack.getMinBufferSize(24_000, android.media.AudioFormat.CHANNEL_OUT_MONO, android.media.AudioFormat.ENCODING_PCM_16BIT)
        val current = AudioTrack.Builder().setAudioAttributes(attributes).setAudioFormat(android.media.AudioFormat.Builder().setSampleRate(24_000).setChannelMask(android.media.AudioFormat.CHANNEL_OUT_MONO).setEncoding(android.media.AudioFormat.ENCODING_PCM_16BIT).build()).setBufferSizeInBytes(minimum.coerceAtLeast(24_000)).setTransferMode(AudioTrack.MODE_STREAM).build()
        track = current
        current.play()
        runCatching { chunks { current.write(it, 0, it.size, AudioTrack.WRITE_BLOCKING) } }.isSuccess.also { current.stop(); current.release(); track = null; abandon() }
    }

    override suspend fun playWav(bytes: ByteArray): Boolean = withContext(Dispatchers.IO) {
        val pcm = WavPcm.decode(bytes) ?: return@withContext false
        playPcm { write -> write(pcm) }
    }

    override suspend fun speak(text: String, locale: String): Boolean = withContext(Dispatchers.Main) {
        if (!focus()) return@withContext false
        val engine = tts ?: TextToSpeech(context) {}.also { tts = it }
        engine.language = Locale.forLanguageTag(locale)
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "live-coach-${System.nanoTime()}") == TextToSpeech.SUCCESS
    }
    override fun stop() { track?.pause(); track?.flush(); tts?.stop(); abandon() }
    private fun focus() = audioManager.requestAudioFocus(focusRequest) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    private fun abandon() { audioManager.abandonAudioFocusRequest(focusRequest) }
    private fun reportRoute() { analytics.record(AnalyticsEvent("live_coach_audio_route", mapOf(AnalyticsProperty.Result to route().name.lowercase()))) }
    private fun route(): PlaybackRoute = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { it.isSink }?.let { when (it.type) { AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> PlaybackRoute.Bluetooth; AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> PlaybackRoute.Wired; AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET -> PlaybackRoute.Usb; AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> PlaybackRoute.Speaker; else -> PlaybackRoute.Unknown } } ?: PlaybackRoute.Unknown
}

private object WavPcm {
    fun decode(bytes: ByteArray): ByteArray? {
        if (bytes.size < 44 || bytes.copyOfRange(0, 4).decodeToString() != "RIFF") return null
        var offset = 12
        while (offset + 8 <= bytes.size) {
            val size = (0..3).sumOf { (bytes[offset + 4 + it].toInt() and 0xff) shl (8 * it) }
            if (bytes.copyOfRange(offset, offset + 4).decodeToString() == "data" && offset + 8 + size <= bytes.size) return bytes.copyOfRange(offset + 8, offset + 8 + size)
            offset += 8 + size + (size and 1)
        }
        return null
    }
}

class LiveCoachPlaybackCoordinator @Inject constructor(
    private val repository: LiveCoachRepository,
    private val packs: FixedAudioPackStore,
    private val output: CoachAudioOutput,
    private val analytics: ProductAnalytics,
) {
    suspend fun play(token: String, sessionId: String, request: CueRequest, mode: LiveCoachMode, selection: AudioPackSelection, fallbackText: String, fixedCueKey: String = FixedCueKeys.forMoment(request.moment)): PlaybackResult {
        if (mode == LiveCoachMode.Dynamic) {
            try {
                val streamed = withTimeout(1_500) { repository.streamCue(token, sessionId, request).getOrThrow() }
                val reader = LiveCoachStreamReader(streamed)
                val played = output.playPcm { write -> while (true) { val frame = reader.next() ?: break; if (frame.type == 2) write(frame.payload); if (frame.type == 4) error("stream interrupted") } }
                if (played) return result(PlaybackSource.Streaming, true, request.moment)
            } catch (_: TimeoutCancellationException) { /* fixed/TTS fallback */ } catch (_: Exception) { /* fixed/TTS fallback */ }
        }
        packs.audio(fixedCueKey, selection, fallbackText)?.let { if (output.playWav(it)) return result(PlaybackSource.FixedPack, true, request.moment) }
        return result(PlaybackSource.TextToSpeech, output.speak(fallbackText, selection.locale), request.moment)
    }
    private fun result(source: PlaybackSource, played: Boolean, moment: LiveCoachMoment) = PlaybackResult(source, played).also { analytics.record(AnalyticsEvent("live_coach_playback", mapOf(AnalyticsProperty.Source to source.name.lowercase(), AnalyticsProperty.Result to if (played) "success" else "unavailable", AnalyticsProperty.Trigger to moment.name.lowercase()))) }
}

object FixedCueKeys {
    fun forMoment(moment: LiveCoachMoment) = when (moment) {
        LiveCoachMoment.Progress, LiveCoachMoment.TargetLocked -> "progress.steady"
        LiveCoachMoment.EarlyOverpace -> "coach.early_settle"; LiveCoachMoment.PaceAboveTarget -> "coach.ease_to_target"
        LiveCoachMoment.PaceBelowTarget -> "coach.lift_to_target"; LiveCoachMoment.PaceInstability -> "coach.smooth_pace"
        LiveCoachMoment.PaceDrift -> "coach.rebuild_rhythm"; LiveCoachMoment.RhythmRecovery -> "coach.rhythm_recovered"
        LiveCoachMoment.RecoveryTooHard -> "coach.recovery_easy"; LiveCoachMoment.UnexpectedStop -> "workout.pause"
        LiveCoachMoment.ResumeAfterBreak -> "workout.resume"; LiveCoachMoment.ClimbStart -> "coach.climb_by_effort"
        LiveCoachMoment.CrestRecovery -> "coach.crest_reset"; LiveCoachMoment.SegmentTransition, LiveCoachMoment.WorkoutInstruction -> "workout.segment_start"
        LiveCoachMoment.FinishOpportunity -> "coach.strong_finish"; LiveCoachMoment.ChallengeStart -> "challenge.start"
        LiveCoachMoment.ChallengeComplete -> "challenge.complete"
    }
}
