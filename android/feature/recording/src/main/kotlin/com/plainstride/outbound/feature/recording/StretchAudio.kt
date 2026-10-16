package com.plainstride.outbound.feature.recording

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log
import java.io.File
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/** Cache-only playback keeps network latency out of hold and transition timing. */
internal class StretchAudio(context: Context) {
    private val directory = File(context.cacheDir, "stretch-audio-v1")
    private val locale = when (Locale.getDefault().language) { "zh" -> "zh-Hans"; "es" -> "es"; else -> "en" }
    private val files = mutableMapOf<String, File>()
    private var player: MediaPlayer? = null

    suspend fun preload(cues: List<String>, fetch: suspend (String, String) -> ByteArray?) {
        for (cue in cues + listOf("release", "five", "four", "three", "two", "one")) {
            val file = File(directory, "$locale-plainstride_warm_1-$cue.wav")
            val cached = withContext(Dispatchers.IO) { file.isFile && file.length() in 44..512 * 1024 }
            if (cached) { files[cue] = file; continue }
            val bytes = fetch(cue, locale) ?: continue
            try {
                withContext(Dispatchers.IO) {
                    directory.mkdirs()
                    val temporary = File(directory, "${file.name}.tmp")
                    temporary.writeBytes(bytes)
                    check(temporary.renameTo(file))
                }
                files[cue] = file
            } catch (error: CancellationException) { throw error }
            catch (error: Exception) { Log.w("StretchAudio", "Cache write failed type=${error.javaClass.simpleName}") }
        }
    }

    fun play(cue: String) {
        stop()
        val file = files[cue] ?: run { Log.w("StretchAudio", "Cached cue unavailable cue=$cue"); return }
        val next = MediaPlayer()
        try {
            next.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            next.setDataSource(file.absolutePath)
            next.setOnCompletionListener { if (player === it) { it.release(); player = null } }
            next.setOnErrorListener { value, what, extra ->
                Log.w("StretchAudio", "Playback failed code=$what extra=$extra")
                if (player === value) { value.release(); player = null }
                true
            }
            next.prepare()
            player = next
            next.start()
        } catch (error: Exception) {
            next.release()
            player = null
            Log.w("StretchAudio", "Playback setup failed type=${error.javaClass.simpleName}")
        }
    }

    suspend fun playAndWait(cue: String, release: Boolean) {
        try {
            for (key in (if (release) listOf("release", cue) else listOf(cue))) {
                play(key)
                while (player != null) delay(50)
            }
        } finally { stop() }
    }
    fun stop() { player?.release(); player = null }
    fun close() = stop()
}
