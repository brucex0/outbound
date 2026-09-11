package com.plainstride.outbound.feature.livecoach.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.DataInputStream
import java.io.InputStream
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.network.PlainstrideJson
import com.plainstride.outbound.feature.livecoach.network.CueRequest
import com.plainstride.outbound.feature.livecoach.network.CueSource
import com.plainstride.outbound.feature.livecoach.network.CueStreamCompletion
import com.plainstride.outbound.feature.livecoach.network.CueStreamMetadata
import com.plainstride.outbound.feature.livecoach.network.LiveCoachMode
import com.plainstride.outbound.feature.livecoach.network.LiveCoachMoment
import com.plainstride.outbound.feature.livecoach.network.LiveCoachRepository

enum class PlaybackRoute { Speaker, Wired, Bluetooth, Usb, Unknown }
enum class PlaybackSource(val wireValue: String) {
    Streaming("cloud_stream"),
    PlannedCache("planned_cache"),
    FixedPack("recorded_audio"),
    None("none"),
}

data class PlaybackResult(val source: PlaybackSource, val played: Boolean)

class LiveCoachStreamReader(input: InputStream) {
    data class Frame(val type: Int, val payload: ByteArray)

    private val stream = DataInputStream(input)

    fun next(): Frame? {
        val type = stream.read()
        if (type < 0) return null
        val length = stream.readInt()
        require(length in 0..MAX_FRAME) { "Live-coach stream frame is too large" }
        return Frame(type, ByteArray(length).also(stream::readFully))
    }

    private companion object { const val MAX_FRAME = 512 * 1024 }
}

interface CoachAudioOutput {
    suspend fun playPcm(chunks: suspend ((ByteArray) -> Unit) -> Unit): Boolean
    suspend fun playWav(bytes: ByteArray): Boolean
    fun stop()
}

@Singleton
class AndroidCoachAudioOutput @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val analytics: ProductAnalytics,
) : CoachAudioOutput {
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
    private val playbackMutex = Mutex()
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) stop()
    }
    private val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        .setAudioAttributes(attributes)
        .setOnAudioFocusChangeListener(focusListener)
        .setWillPauseWhenDucked(false)
        .build()
    @Volatile private var track: AudioTrack? = null
    @Volatile private var stopGeneration = 0L
    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = reportRoute()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = reportRoute()
    }

    init { audioManager.registerAudioDeviceCallback(deviceCallback, null) }

    override suspend fun playPcm(chunks: suspend ((ByteArray) -> Unit) -> Unit): Boolean =
        playbackMutex.withLock {
            withContext(Dispatchers.IO) {
                if (!focus()) return@withContext false
                val generation = stopGeneration
                val minimum = AudioTrack.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
                if (minimum <= 0) {
                    abandon()
                    return@withContext false
                }
                val current = AudioTrack.Builder()
                    .setAudioAttributes(attributes)
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setSampleRate(SAMPLE_RATE)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .build(),
                    )
                    .setBufferSizeInBytes(minimum.coerceAtLeast(SAMPLE_RATE))
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .build()
                track = current
                var writtenBytes = 0
                val played = runCatching {
                    current.play()
                    chunks { bytes ->
                        check(generation == stopGeneration)
                        var offset = 0
                        while (offset < bytes.size) {
                            val count = current.write(bytes, offset, bytes.size - offset, AudioTrack.WRITE_BLOCKING)
                            check(count > 0) { "AudioTrack write failed ($count)" }
                            offset += count
                            writtenBytes += count
                        }
                    }
                    val expectedFrames = writtenBytes / BYTES_PER_FRAME
                    val drainMilliseconds = (writtenBytes.toLong() * 1_000 / BYTES_PER_SECOND + 750).coerceAtLeast(750)
                    withTimeoutOrNull(drainMilliseconds) {
                        while (generation == stopGeneration && current.playbackHeadPosition < expectedFrames) delay(10)
                    } != null && generation == stopGeneration
                }.getOrDefault(false)
                runCatching { current.stop() }
                current.release()
                if (track === current) track = null
                abandon()
                played
            }
        }

    override suspend fun playWav(bytes: ByteArray): Boolean {
        val pcm = WavPcm.decode(bytes) ?: return false
        return playPcm { write -> write(pcm) }
    }

    override fun stop() {
        stopGeneration += 1
        track?.let { current ->
            runCatching { current.pause() }
            runCatching { current.flush() }
        }
        abandon()
    }

    private fun focus() = audioManager.requestAudioFocus(focusRequest) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    private fun abandon() { audioManager.abandonAudioFocusRequest(focusRequest) }
    private fun reportRoute() {
        analytics.record(AnalyticsEvent("live_coach_audio_route", mapOf(AnalyticsProperty.Result to route().name.lowercase())))
    }
    private fun route(): PlaybackRoute {
        val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).filter(AudioDeviceInfo::isSink)
        return when {
            outputs.any { it.type in setOf(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_BLUETOOTH_SCO) } -> PlaybackRoute.Bluetooth
            outputs.any { it.type in setOf(AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET) } -> PlaybackRoute.Wired
            outputs.any { it.type in setOf(AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET) } -> PlaybackRoute.Usb
            outputs.any { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER } -> PlaybackRoute.Speaker
            else -> PlaybackRoute.Unknown
        }
    }

    private companion object {
        const val SAMPLE_RATE = 24_000
        const val BYTES_PER_FRAME = 2
        const val BYTES_PER_SECOND = SAMPLE_RATE * BYTES_PER_FRAME
    }
}

internal object WavPcm {
    fun isValid(bytes: ByteArray) = decode(bytes) != null

    fun decode(bytes: ByteArray): ByteArray? {
        if (bytes.size !in 44..MAX_WAV_BYTES || ascii(bytes, 0, 4) != "RIFF" || ascii(bytes, 8, 4) != "WAVE") return null
        var offset = 12
        var formatValid = false
        var pcm: ByteArray? = null
        while (offset + 8 <= bytes.size) {
            val size = littleEndian32(bytes, offset + 4) ?: return null
            val payload = offset + 8
            if (size < 0 || payload + size > bytes.size) return null
            when (ascii(bytes, offset, 4)) {
                "fmt " -> if (size >= 16) {
                    formatValid = littleEndian16(bytes, payload) == 1
                        && littleEndian16(bytes, payload + 2) == 1
                        && littleEndian32(bytes, payload + 4) == 24_000
                        && littleEndian16(bytes, payload + 14) == 16
                }
                "data" -> pcm = bytes.copyOfRange(payload, payload + size)
            }
            offset = payload + size + (size and 1)
        }
        val data = pcm ?: return null
        return data.takeIf { formatValid && it.isNotEmpty() && it.size <= MAX_PCM_BYTES }
    }

    private fun ascii(bytes: ByteArray, offset: Int, length: Int) =
        bytes.copyOfRange(offset, offset + length).decodeToString()
    private fun littleEndian16(bytes: ByteArray, offset: Int): Int? =
        if (offset + 2 > bytes.size) null else (bytes[offset].toInt() and 0xff) or ((bytes[offset + 1].toInt() and 0xff) shl 8)
    private fun littleEndian32(bytes: ByteArray, offset: Int): Int? =
        if (offset + 4 > bytes.size) null else (0..3).sumOf { (bytes[offset + it].toInt() and 0xff) shl (8 * it) }

    private const val MAX_WAV_BYTES = 512 * 1024
    private const val MAX_PCM_BYTES = 24_000 * 2 * 8
}

class LiveCoachPlaybackCoordinator @Inject constructor(
    private val repository: LiveCoachRepository,
    private val packs: FixedAudioPackStore,
    private val plannedCache: PlannedAudioCache,
    private val output: CoachAudioOutput,
    private val analytics: ProductAnalytics,
) {
    private val reportingScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    suspend fun play(
        token: String?,
        sessionId: String?,
        planHash: String?,
        phraseId: String?,
        request: CueRequest,
        mode: LiveCoachMode,
        accessReason: String,
        selection: AudioPackSelection,
        fallbackText: String,
        fixedCueKey: String? = FixedCueKeys.forMoment(request.moment),
    ): PlaybackResult {
        if (mode == LiveCoachMode.Disabled) return result(PlaybackSource.None, false, request.moment)

        if (planHash != null && phraseId != null) {
            plannedCache.audio(planHash, selection.voiceProfileId, phraseId)?.let { audio ->
                if (output.playWav(audio)) {
                    if (token != null && sessionId != null) {
                        reportingScope.launch { repository.recordCachedUse(token, sessionId, request) }
                    }
                    analytics.record(AnalyticsEvent("live_guidance_provider_result", mapOf(
                        AnalyticsProperty.SourceType to CueSource.Planned.wireValue,
                        AnalyticsProperty.Result to "success",
                        AnalyticsProperty.AudioMode to mode.wireValue,
                        AnalyticsProperty.AccessReason to accessReason,
                        AnalyticsProperty.LatencyBucket to "under_1s",
                    )))
                    return result(PlaybackSource.PlannedCache, true, request.moment)
                }
            }
        }

        if (mode == LiveCoachMode.Dynamic && token != null && sessionId != null) {
            val startedAtNanos = System.nanoTime()
            val deadlineNanos = startedAtNanos + CLOUD_AUDIO_DEADLINE_MILLISECONDS * 1_000_000
            try {
                val body = withTimeout(CLOUD_AUDIO_DEADLINE_MILLISECONDS) {
                    repository.streamCue(token, sessionId, request).getOrThrow()
                }
                body.use {
                    check(it.contentType()?.toString()?.startsWith("application/vnd.plainstride.live-coach-stream") == true)
                    val source = it.source()
                    source.timeout().deadlineNanoTime(deadlineNanos)
                    val reader = LiveCoachStreamReader(source.inputStream())
                    val metadataFrame = reader.next()
                    check(metadataFrame?.type == FRAME_METADATA)
                    val metadata = PlainstrideJson.decodeFromString<CueStreamMetadata>(metadataFrame.payload.decodeToString())
                    check(metadata.cueRequestId == request.cueRequestId && metadata.moment == request.moment)
                    check(runCatching { Instant.parse(metadata.expiresAt).isAfter(Instant.now()) }.getOrDefault(false))
                    recordProvider(metadata, startedAtNanos, mode, accessReason)
                    val audio = metadata.audio
                    if (audio != null) {
                        check(audio.contentType == "audio/L16" && audio.codec == "pcm_s16le" && audio.sampleRateHz == 24_000.0 && audio.channels == 1)
                        val firstAudio = reader.next()
                        check(firstAudio?.type == FRAME_AUDIO && firstAudio.payload.isNotEmpty())
                        source.timeout().clearDeadline()
                        recordFirstAudio(startedAtNanos)
                        val played = output.playPcm { write ->
                            var audioByteCount = firstAudio.payload.size
                            check(audioByteCount <= MAX_STREAM_PCM_BYTES)
                            write(firstAudio.payload)
                            var completed = false
                            while (!completed) {
                                val frame = reader.next() ?: error("Live-coach stream ended before completion")
                                when (frame.type) {
                                    FRAME_AUDIO -> {
                                        audioByteCount += frame.payload.size
                                        check(audioByteCount <= MAX_STREAM_PCM_BYTES)
                                        write(frame.payload)
                                    }
                                    FRAME_COMPLETE -> {
                                        val completion = PlainstrideJson.decodeFromString<CueStreamCompletion>(frame.payload.decodeToString())
                                        check(completion.byteCount == audioByteCount && audioByteCount % 2 == 0)
                                        completed = true
                                    }
                                    FRAME_ERROR -> error("Live-coach stream interrupted")
                                    else -> error("Invalid live-coach stream frame")
                                }
                            }
                        }
                        if (played) return result(PlaybackSource.Streaming, true, request.moment)
                    }
                }
            } catch (_: TimeoutCancellationException) {
                recordProviderFallback(startedAtNanos, mode, accessReason)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                recordProviderFallback(startedAtNanos, mode, accessReason)
            }
        }

        packs.audio(fixedCueKey.orEmpty(), selection, fallbackText)?.let { audio ->
            if (output.playWav(audio)) return result(PlaybackSource.FixedPack, true, request.moment)
        }
        return result(PlaybackSource.None, false, request.moment)
    }

    private fun recordProvider(
        metadata: CueStreamMetadata,
        startedAtNanos: Long,
        mode: LiveCoachMode,
        accessReason: String,
    ) {
        analytics.record(AnalyticsEvent("live_guidance_provider_result", mapOf(
            AnalyticsProperty.SourceType to metadata.source.wireValue,
            AnalyticsProperty.Result to metadata.result.wireValue,
            AnalyticsProperty.AudioMode to mode.wireValue,
            AnalyticsProperty.AccessReason to accessReason,
            AnalyticsProperty.LatencyBucket to latencyBucket(startedAtNanos),
        )))
    }

    private fun recordProviderFallback(startedAtNanos: Long, mode: LiveCoachMode, accessReason: String) {
        analytics.record(AnalyticsEvent("live_guidance_provider_result", mapOf(
            AnalyticsProperty.SourceType to "cached_fallback",
            AnalyticsProperty.Result to if (elapsedMilliseconds(startedAtNanos) >= CLOUD_AUDIO_DEADLINE_MILLISECONDS) "timeout" else "unavailable",
            AnalyticsProperty.AudioMode to mode.wireValue,
            AnalyticsProperty.AccessReason to accessReason,
            AnalyticsProperty.LatencyBucket to latencyBucket(startedAtNanos),
        )))
    }

    private fun recordFirstAudio(startedAtNanos: Long) {
        analytics.record(AnalyticsEvent("live_guidance_audio_first_byte", mapOf(
            AnalyticsProperty.SourceType to CueSource.Dynamic.wireValue,
            AnalyticsProperty.LatencyBucket to latencyBucket(startedAtNanos),
        )))
    }

    private fun result(source: PlaybackSource, played: Boolean, moment: LiveCoachMoment) =
        PlaybackResult(source, played).also {
            analytics.record(AnalyticsEvent("live_coach_playback", mapOf(
                AnalyticsProperty.Source to source.wireValue,
                AnalyticsProperty.Result to if (played) "success" else "unavailable",
                AnalyticsProperty.Trigger to moment.wireValue,
            )))
            val playbackRoute = when (source) {
                PlaybackSource.Streaming -> "cloud_stream"
                PlaybackSource.PlannedCache, PlaybackSource.FixedPack -> "recorded_audio"
                PlaybackSource.None -> null
            }
            if (played && playbackRoute != null) analytics.record(
                AnalyticsEvent(
                    "live_guidance_audio_playback_route",
                    mapOf(AnalyticsProperty.SourceType to playbackRoute),
                ),
            )
        }

    private fun elapsedMilliseconds(startedAtNanos: Long) = (System.nanoTime() - startedAtNanos) / 1_000_000
    private fun latencyBucket(startedAtNanos: Long) = when (elapsedMilliseconds(startedAtNanos)) {
        in 0..<1_000 -> "under_1s"
        in 1_000..<2_000 -> "1s_2s"
        in 2_000..<4_000 -> "2s_4s"
        else -> "4s_plus"
    }

    private companion object {
        const val CLOUD_AUDIO_DEADLINE_MILLISECONDS = 1_500L
        const val FRAME_METADATA = 1
        const val FRAME_AUDIO = 2
        const val FRAME_COMPLETE = 3
        const val FRAME_ERROR = 4
        const val MAX_STREAM_PCM_BYTES = 24_000 * 2 * 8
    }
}

object FixedCueKeys {
    fun forMoment(moment: LiveCoachMoment) = when (moment) {
        LiveCoachMoment.Progress, LiveCoachMoment.TargetLocked, LiveCoachMoment.RacePaceLocked -> "progress.steady"
        LiveCoachMoment.EarlyOverpace, LiveCoachMoment.RaceStartRestraint -> "coach.early_settle"
        LiveCoachMoment.PaceAboveTarget -> "coach.ease_to_target"
        LiveCoachMoment.PaceBelowTarget -> "coach.lift_to_target"
        LiveCoachMoment.PaceInstability -> "coach.smooth_pace"
        LiveCoachMoment.PaceDrift, LiveCoachMoment.RaceLateFade -> "coach.rebuild_rhythm"
        LiveCoachMoment.RhythmRecovery -> "coach.rhythm_recovered"
        LiveCoachMoment.RecoveryTooHard -> "coach.recovery_easy"
        LiveCoachMoment.UnexpectedStop -> "workout.pause"
        LiveCoachMoment.ResumeAfterBreak -> "workout.resume"
        LiveCoachMoment.ClimbStart -> "coach.climb_by_effort"
        LiveCoachMoment.CrestRecovery -> "coach.crest_reset"
        LiveCoachMoment.SegmentTransition, LiveCoachMoment.WorkoutInstruction -> "workout.segment_start"
        LiveCoachMoment.FinishOpportunity, LiveCoachMoment.RaceLateStrength, LiveCoachMoment.RaceFinalKilometer -> "coach.strong_finish"
        LiveCoachMoment.RaceHalfwayAssessment -> "progress.halfway"
        LiveCoachMoment.ChallengeStart -> "challenge.start"
        LiveCoachMoment.ChallengeComplete -> "challenge.complete"
    }
}
