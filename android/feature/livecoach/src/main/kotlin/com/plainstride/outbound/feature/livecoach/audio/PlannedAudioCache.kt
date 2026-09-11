package com.plainstride.outbound.feature.livecoach.audio

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.security.MessageDigest
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Singleton
class PlannedAudioCache @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val root = File(context.cacheDir, "Plainstride/PlannedCoachAudio")

    suspend fun audio(planHash: String, voiceProfileId: String, phraseId: String): ByteArray? =
        withContext(Dispatchers.IO) {
            val file = file(planHash, voiceProfileId, phraseId)
            runCatching { file.takeIf(File::isFile)?.readBytes()?.takeIf(WavPcm::isValid) }.getOrNull()
        }

    suspend fun store(bytes: ByteArray, planHash: String, voiceProfileId: String, phraseId: String) =
        withContext(Dispatchers.IO) {
            if (!WavPcm.isValid(bytes)) return@withContext
            runCatching {
                root.mkdirs()
                val destination = file(planHash, voiceProfileId, phraseId)
                val temporary = File(root, "${destination.name}.tmp")
                temporary.writeBytes(bytes)
                check(temporary.renameTo(destination) || run {
                    temporary.copyTo(destination, overwrite = true)
                    temporary.delete()
                    true
                })
                purgeExpired()
            }
        }

    private fun file(planHash: String, voiceProfileId: String, phraseId: String): File {
        val key = "$planHash:$voiceProfileId:$phraseId".encodeToByteArray()
        val digest = MessageDigest.getInstance("SHA-256").digest(key).joinToString("") { "%02x".format(it) }
        return File(root, "$digest.wav")
    }

    private fun purgeExpired() {
        val cutoff = System.currentTimeMillis() - MAX_AGE_MILLISECONDS
        root.listFiles()?.filter { it.isFile && it.lastModified() < cutoff }?.forEach { it.delete() }
    }

    private companion object { const val MAX_AGE_MILLISECONDS = 24 * 60 * 60 * 1_000L }
}
