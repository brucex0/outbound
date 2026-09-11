package com.plainstride.outbound.feature.livecoach.audio

import android.content.Context
import android.util.Base64
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import okhttp3.OkHttpClient
import okhttp3.Request
import com.plainstride.outbound.core.network.PlainstrideJson

@Serializable data class AudioPackManifest(val contractVersion: Int, val catalogVersion: String, val generatedAt: String? = null, val entries: List<AudioPackEntry>)
@Serializable data class AudioPackEntry(val cueKey: String, val locale: String, val voiceProfileId: String, val scriptStyleId: String, val compatibleCoachPersonaIds: List<String>, val transcript: String, val sha256: String, val byteCount: Int? = null, val durationMilliseconds: Int? = null, val contentType: String, val url: String? = null, val reviewFileName: String? = null, val bundledResourceName: String? = null, val approved: Boolean)
@Serializable private data class SignedEnvelope(val contractVersion: Int, val payload: String, val signature: ManifestSignature)
@Serializable private data class ManifestSignature(val algorithm: String, val keyId: String, val value: String)

data class AudioPackSelection(val locale: String, val voiceProfileId: String, val coachPersonaId: String, val scriptStyleId: String = "standard")

interface FixedAudioPackStore {
    suspend fun refresh(manifestUrl: String, expectedCatalogVersion: String, publicKeysPem: Map<String, String>): Boolean
    suspend fun audio(cueKey: String, selection: AudioPackSelection, transcript: String? = null): ByteArray?
    suspend fun preload(cueKeys: Collection<String>, selection: AudioPackSelection)
}

@Singleton
class VerifiedAudioPackStore @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val client: OkHttpClient,
) : FixedAudioPackStore {
    private val root = File(context.cacheDir, "Plainstride/LiveCoachAudio")
    private val manifestFile = File(root, "last-known-good-manifest.json")
    @Volatile private var manifest: AudioPackManifest? = loadManifest(manifestFile) ?: loadBundledManifest()

    override suspend fun refresh(manifestUrl: String, expectedCatalogVersion: String, publicKeysPem: Map<String, String>): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            val response = client.newCall(Request.Builder().url(manifestUrl).build()).execute()
            response.use {
                check(it.isSuccessful)
                val envelopeBytes = it.body?.bytes() ?: error("Empty manifest")
                check(envelopeBytes.size <= MAX_MANIFEST_BYTES)
                val envelope = PlainstrideJson.decodeFromString<SignedEnvelope>(envelopeBytes.decodeToString())
                check(envelope.contractVersion == 1 && envelope.signature.algorithm == "ES256")
                val payload = decodeBase64Url(envelope.payload)
                val signature = decodeBase64Url(envelope.signature.value)
                val pem = publicKeysPem[envelope.signature.keyId] ?: error("Unknown manifest key")
                check(verifyEs256(payload, signature, pem))
                val candidate = PlainstrideJson.decodeFromString<AudioPackManifest>(payload.decodeToString())
                validate(candidate, expectedCatalogVersion, remote = true)
                root.mkdirs()
                val temporary = File(root, "manifest.tmp")
                temporary.writeBytes(payload)
                check(temporary.renameTo(manifestFile) || run { temporary.copyTo(manifestFile, overwrite = true); temporary.delete(); true })
                manifest = candidate
            }
            true
        }.getOrDefault(false)
    }

    override suspend fun audio(cueKey: String, selection: AudioPackSelection, transcript: String?): ByteArray? = withContext(Dispatchers.IO) {
        val entry = match(cueKey, selection, transcript) ?: return@withContext null
        local(entry)?.let { return@withContext it }
        val url = entry.url ?: return@withContext null
        runCatching {
            client.newCall(Request.Builder().url(url).build()).execute().use { response ->
                check(response.isSuccessful)
                check(response.body?.contentType()?.toString()?.startsWith("audio/wav") == true)
                val bytes = response.body?.bytes() ?: error("Empty audio")
                check(bytes.size in 44..MAX_AUDIO_BYTES && (entry.byteCount == null || bytes.size == entry.byteCount))
                check(sha256(bytes) == entry.sha256)
                check(WavPcm.isValid(bytes))
                root.mkdirs()
                val destination = File(root, "${entry.sha256}.wav")
                val temporary = File(root, "${entry.sha256}.tmp")
                temporary.writeBytes(bytes)
                check(temporary.renameTo(destination) || run {
                    temporary.copyTo(destination, overwrite = true)
                    temporary.delete()
                    true
                })
                bytes
            }
        }.getOrNull()
    }

    override suspend fun preload(cueKeys: Collection<String>, selection: AudioPackSelection) {
        cueKeys.forEach { audio(it, selection) }
    }

    private fun match(cueKey: String, selection: AudioPackSelection, transcript: String?): AudioPackEntry? {
        val candidates = manifest?.entries.orEmpty().filter { it.cueKey == cueKey && it.locale == selection.locale && it.voiceProfileId == selection.voiceProfileId && selection.coachPersonaId in it.compatibleCoachPersonaIds }
        return candidates.firstOrNull { it.scriptStyleId == selection.scriptStyleId }
            ?: candidates.firstOrNull { it.scriptStyleId == "standard" }
            ?: transcript?.let { wanted -> manifest?.entries?.firstOrNull { it.locale == selection.locale && it.voiceProfileId == selection.voiceProfileId && selection.coachPersonaId in it.compatibleCoachPersonaIds && normalize(it.transcript) == normalize(wanted) } }
    }

    private fun local(entry: AudioPackEntry): ByteArray? {
        val cached = File(root, "${entry.sha256}.wav")
        if (cached.isFile) cached.readBytes().takeIf { sha256(it) == entry.sha256 && WavPcm.isValid(it) }?.let { return it }
        val assetName = entry.bundledResourceName ?: return null
        return runCatching { context.assets.open("LiveCoachAudio/$assetName.wav").use { it.readBytes() } }
            .getOrNull()
            ?.takeIf { sha256(it) == entry.sha256 && WavPcm.isValid(it) }
    }

    private fun loadManifest(file: File): AudioPackManifest? = runCatching { PlainstrideJson.decodeFromString<AudioPackManifest>(file.readText()).also { validate(it, it.catalogVersion, false) } }.getOrNull()
    private fun loadBundledManifest(): AudioPackManifest? = runCatching { context.assets.open("LiveCoachAudio/manifest.json").bufferedReader().use { PlainstrideJson.decodeFromString<AudioPackManifest>(it.readText()) }.also { value -> validate(value, value.catalogVersion, false) } }.getOrNull()
    private fun validate(value: AudioPackManifest, version: String, remote: Boolean) {
        check(value.contractVersion == 1 && value.catalogVersion == version && value.entries.isNotEmpty())
        check(value.entries.all {
            it.approved
                && it.contentType == "audio/wav"
                && it.sha256.matches(Regex("[a-f0-9]{64}"))
                && (it.byteCount == null || it.byteCount in 44..MAX_AUDIO_BYTES)
                && (it.durationMilliseconds == null || it.durationMilliseconds in 1..8_000)
                && (!remote || it.url != null)
        })
    }
    private fun verifyEs256(payload: ByteArray, signatureBytes: ByteArray, pem: String): Boolean {
        val der = Base64.decode(pem.replace(Regex("-----[^-]+-----|\\s"), ""), Base64.DEFAULT)
        val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(der))
        return Signature.getInstance("SHA256withECDSA").run { initVerify(key); update(payload); verify(signatureBytes) }
    }
    private fun decodeBase64Url(value: String) = Base64.decode(value, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    private fun sha256(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun normalize(value: String) = value.lowercase().replace(Regex("[^\\p{L}\\p{N}]"), "")
    private companion object { const val MAX_AUDIO_BYTES = 512 * 1024; const val MAX_MANIFEST_BYTES = 2 * 1024 * 1024 }
}
