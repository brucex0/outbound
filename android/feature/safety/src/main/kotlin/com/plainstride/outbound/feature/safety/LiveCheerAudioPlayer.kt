package com.plainstride.outbound.feature.safety

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

/** Plays original AAC voice Cheers with the same navigation-guidance audio routing as the live guide. */
@Singleton
class LiveCheerAudioPlayer @Inject constructor(@param:ApplicationContext private val context: Context) {
    suspend fun play(bytes: ByteArray): Boolean = withContext(Dispatchers.Main) {
        val file = withContext(Dispatchers.IO) {
            File.createTempFile("plainstride-live-cheer-", ".m4a", context.cacheDir).apply { writeBytes(bytes) }
        }
        try {
            suspendCancellableCoroutine { continuation ->
                val player = MediaPlayer()
                fun finish(result: Boolean) {
                    runCatching { player.release() }
                    file.delete()
                    if (continuation.isActive) continuation.resume(result)
                }
                player.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                player.setOnCompletionListener { finish(true) }
                player.setOnErrorListener { _, _, _ -> finish(false); true }
                continuation.invokeOnCancellation {
                    runCatching { player.stop() }
                    runCatching { player.release() }
                    file.delete()
                }
                runCatching {
                    player.setDataSource(file.absolutePath)
                    player.setOnPreparedListener { it.start() }
                    player.prepareAsync()
                }.onFailure { finish(false) }
            }
        } finally {
            file.delete()
        }
    }
}
