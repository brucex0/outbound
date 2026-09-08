package com.plainstride.outbound.core.music

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import java.io.Closeable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** Owns media-button routing and audio focus for workout music without owning audio content. */
class WorkoutMediaSession(
    context: Context,
    private val provider: MusicProvider,
    private val scope: CoroutineScope,
) : Closeable {
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
    private val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
        .setAudioAttributes(attributes)
        .setOnAudioFocusChangeListener(::onFocusChanged, Handler(Looper.getMainLooper()))
        .setWillPauseWhenDucked(false)
        .build()
    private val session = MediaSession(context, "PlainstrideWorkoutMusic").apply {
        setCallback(object : MediaSession.Callback() {
            override fun onPlay() { scope.launch { playOrResume() } }
            override fun onPause() { scope.launch { provider.pause(); publish() } }
            override fun onSkipToNext() { scope.launch { provider.skipNext(); publish() } }
            override fun onStop() { scope.launch { provider.pause(); abandonFocus(); publish() } }
        })
        isActive = true
    }

    suspend fun playOrResume(): Result<Unit> {
        if (audioManager.requestAudioFocus(focusRequest) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) return Result.failure(IllegalStateException("audio_focus_denied"))
        val result = if (provider.state.value.playback.current == null) provider.play() else provider.resume()
        publish(); return result
    }

    /** Temporarily ducks for spoken guidance and restores only playback owned by this session. */
    suspend fun withGuideSpeech(block: suspend () -> Unit) {
        val wasPlaying = provider.state.value.playback.isPlaying
        if (wasPlaying) provider.pause()
        try { block() } finally { if (wasPlaying) provider.resume() }
        publish()
    }

    fun publish() {
        val playback = provider.state.value.playback
        val state = if (playback.isPlaying) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
        session.setPlaybackState(PlaybackState.Builder()
            .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_STOP)
            .setState(state, playback.positionMs, if (playback.isPlaying) 1f else 0f)
            .build())
    }

    private fun onFocusChanged(change: Int) {
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> scope.launch { provider.pause(); publish() }
            AudioManager.AUDIOFOCUS_GAIN -> Unit // Never auto-resume after an external interruption.
        }
    }
    private fun abandonFocus() { audioManager.abandonAudioFocusRequest(focusRequest) }
    override fun close() { abandonFocus(); session.isActive = false; session.release() }
}
