package com.plainstride.outbound.feature.recording

/** The recording feature does not depend on live-coach catalog or network implementation. */
interface RecordingCountdownAudio {
    fun setLocale(locale: String)
    suspend fun prepare(): Boolean
    fun isReady(): Boolean
    /** Returns after playback drains and the minimum visible beat has elapsed from playback start. */
    suspend fun play(value: Int, minimumBeatMilliseconds: Long)
    fun stop()
}
