package com.plainstride.outbound.feature.recording

/** The recording feature does not depend on live-coach catalog or network implementation. */
interface RecordingCountdownAudio {
    fun setLocale(locale: String)
    suspend fun prepare(): Boolean
    fun isReady(): Boolean
    fun play(value: Int)
    fun durationMilliseconds(value: Int): Long
    fun stop()
}
