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
import kotlinx.coroutines.ensureActive
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
    suspend fun cachedAudio(cueKey: String, selection: AudioPackSelection, transcript: String): ByteArray? = null
    suspend fun preload(cueKeys: Collection<String>, selection: AudioPackSelection)
    suspend fun prepare(selection: AudioPackSelection, progress: (Int, Int) -> Unit): Boolean = false
    suspend fun cachedReady(selection: AudioPackSelection): Boolean = false
}

@Singleton
class VerifiedAudioPackStore @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val client: OkHttpClient,
) : FixedAudioPackStore {
    // Private durable files are excluded from backup by the app's backup rules.
    // Unreleased Android deliberately starts fresh instead of migrating the old cache.
    private val root = File(context.filesDir, "Plainstride/LiveCoachAudio")
    private val manifestFile = File(root, "signed-manifest.json")
    private val diskLock = Any()
    private val downloadLocks = java.util.concurrent.ConcurrentHashMap<String, kotlinx.coroutines.sync.Mutex>()
    private val assetClient = client.newBuilder().callTimeout(12, java.util.concurrent.TimeUnit.SECONDS).build()
    private val bundledManifest = loadBundledManifest()
    @Volatile private var manifest: AudioPackManifest? = loadManifest()

    override suspend fun refresh(manifestUrl: String, expectedCatalogVersion: String, publicKeysPem: Map<String, String>): Boolean = withContext(Dispatchers.IO) {
        try {
            val bytes = fetch(manifestUrl, MAX_MANIFEST_BYTES)
            val candidate = decodeSignedManifest(bytes, publicKeysPem)
            validate(candidate, expectedCatalogVersion, remote = true)
            synchronized(diskLock) {
                writeAtomically(manifestFile, bytes)
                manifest = candidate
            }
            true
        } catch (error: kotlinx.coroutines.CancellationException) { throw error }
        catch (error: Exception) {
            diagnostic("manifest_refresh", error)
            false // Keep the last verified catalog and recordings available offline.
        }
    }

    override suspend fun cachedAudio(cueKey: String, selection: AudioPackSelection, transcript: String): ByteArray? = withContext(Dispatchers.IO) {
        match(cueKey, selection, transcript)?.let(::local)
    }

    override suspend fun audio(cueKey: String, selection: AudioPackSelection, transcript: String?): ByteArray? = withContext(Dispatchers.IO) {
        val entry = match(cueKey, selection, transcript) ?: return@withContext null
        load(entry)
    }

    private suspend fun load(entry: AudioPackEntry): ByteArray? {
        val lock = downloadLocks.getOrPut(entry.sha256) { kotlinx.coroutines.sync.Mutex() }
        lock.lock()
        try {
            kotlinx.coroutines.currentCoroutineContext().ensureActive()
            local(entry)?.let { return it }
            val url = entry.url ?: return null
            return try {
                val bytes = fetch(url, MAX_AUDIO_BYTES, "audio/wav")
                check(validAudio(bytes, entry)) { "invalid_audio" }
                kotlinx.coroutines.currentCoroutineContext().ensureActive()
                synchronized(diskLock) { writeAtomically(File(root, "${entry.sha256}.wav"), bytes) }
                bytes
            } catch (error: kotlinx.coroutines.CancellationException) { throw error }
            catch (error: Exception) { diagnostic("audio_fetch_or_store", error); null }
        } finally { lock.unlock() }
    }

    override suspend fun preload(cueKeys: Collection<String>, selection: AudioPackSelection) {
        cueKeys.forEach { audio(it, selection) }
    }

    override suspend fun cachedReady(selection: AudioPackSelection): Boolean = withContext(Dispatchers.IO) {
        val catalog = manifest ?: return@withContext false
        val entries = catalog.entries.filter { matchesSelection(it, selection) }
        entries.isNotEmpty() && entries.all { local(it) != null } && manifest === catalog
    }

    override suspend fun prepare(selection: AudioPackSelection, progress: (Int, Int) -> Unit): Boolean = withContext(Dispatchers.IO) {
        val catalog = manifest ?: return@withContext false
        val entries = catalog.entries.filter { matchesSelection(it, selection) }
            .groupBy(AudioPackEntry::cueKey).values.map { candidates ->
                candidates.firstOrNull { it.scriptStyleId == selection.scriptStyleId } ?: candidates.first()
            }.sortedBy { PRIORITY_KEYS.indexOf(it.cueKey).takeIf { index -> index >= 0 } ?: Int.MAX_VALUE }
        if (entries.isEmpty()) return@withContext false
        var ready = 0
        progress(ready, entries.size)
        for (entry in entries) {
            kotlinx.coroutines.currentCoroutineContext().ensureActive()
            // A catalog replacement invalidates this attempt, never mixing readiness across packs.
            if (manifest !== catalog || load(entry) == null) return@withContext false
            progress(++ready, entries.size)
        }
        if (manifest !== catalog) return@withContext false
        // Retain other language/voice downloads in the current catalog. Remove only obsolete files.
        val retained = catalog.entries.mapTo(mutableSetOf()) { "${it.sha256}.wav" }
        synchronized(diskLock) {
            if (manifest !== catalog) return@synchronized false
            root.listFiles()?.filter { it.extension == "wav" && it.name !in retained }?.forEach {
                if (!it.delete()) android.util.Log.w(TAG, "operation=prune_audio result=failed")
            }
            true
        }
    }

    private fun matchesSelection(entry: AudioPackEntry, selection: AudioPackSelection): Boolean =
        entry.locale == selection.locale && entry.voiceProfileId == selection.voiceProfileId &&
            selection.coachPersonaId in entry.compatibleCoachPersonaIds &&
            entry.scriptStyleId in setOf(selection.scriptStyleId, "standard")

    private fun match(cueKey: String, selection: AudioPackSelection, transcript: String?): AudioPackEntry? {
        val entries = manifest?.entries.orEmpty() + bundledManifest?.entries.orEmpty()
        val candidates = entries.filter { matchesSelection(it, selection) && it.cueKey == cueKey &&
            (transcript == null || normalize(it.transcript) == normalize(transcript)) }
        return candidates.firstOrNull { it.scriptStyleId == selection.scriptStyleId }
            ?: candidates.firstOrNull { it.scriptStyleId == "standard" }
            ?: transcript?.let { wanted -> entries.firstOrNull {
                it.locale == selection.locale && it.voiceProfileId == selection.voiceProfileId &&
                    selection.coachPersonaId in it.compatibleCoachPersonaIds && normalize(it.transcript) == normalize(wanted)
            } }
    }

    private fun local(entry: AudioPackEntry): ByteArray? {
        val file = File(root, "${entry.sha256}.wav")
        if (file.isFile) {
            try {
                check(file.length() in 44..MAX_AUDIO_BYTES.toLong()) { "invalid_size" }
                val bytes = file.readBytes()
                if (validAudio(bytes, entry)) return bytes
                android.util.Log.w(TAG, "operation=read_audio result=invalid_checksum_or_format")
            } catch (error: Exception) { diagnostic("read_audio", error) }
        }
        // Match bundled bytes by checksum, so a remote catalog cannot assign them different speech.
        val bundled = bundledManifest?.entries?.firstOrNull { it.sha256 == entry.sha256 } ?: return null
        val name = bundled.bundledResourceName ?: return null
        return try {
            context.assets.open("LiveCoachAudio/$name.wav").use { it.readBytes() }
                .takeIf { validAudio(it, entry) }
        } catch (error: Exception) { diagnostic("read_bundled_audio", error); null }
    }

    private fun validAudio(bytes: ByteArray, entry: AudioPackEntry) =
        bytes.size in 44..MAX_AUDIO_BYTES && (entry.byteCount == null || bytes.size == entry.byteCount) &&
            sha256(bytes) == entry.sha256 && WavPcm.isValid(bytes)

    private fun loadManifest(): AudioPackManifest? {
        if (!manifestFile.isFile) return null
        return try {
            check(manifestFile.length() <= MAX_MANIFEST_BYTES)
            decodeSignedManifest(android.util.AtomicFile(manifestFile).openRead().use { it.readBytes() }, VoicePackTrust.publicKeys)
        } catch (error: Exception) { diagnostic("read_manifest", error); null }
    }

    private fun loadBundledManifest(): AudioPackManifest? = try {
        context.assets.open("LiveCoachAudio/manifest.json").bufferedReader().use {
            PlainstrideJson.decodeFromString<AudioPackManifest>(it.readText())
        }.also { validate(it, it.catalogVersion, remote = false) }
    } catch (error: Exception) { diagnostic("read_bundled_manifest", error); null }

    private fun decodeSignedManifest(bytes: ByteArray, keys: Map<String, String>): AudioPackManifest {
        check(bytes.size <= MAX_MANIFEST_BYTES) { "manifest_too_large" }
        val envelope = PlainstrideJson.decodeFromString<SignedEnvelope>(bytes.decodeToString())
        check(envelope.contractVersion == 1 && envelope.signature.algorithm == "ES256") { "invalid_manifest_contract" }
        val payload = decodeBase64Url(envelope.payload)
        val pem = keys[envelope.signature.keyId] ?: error("unknown_manifest_key")
        check(verifyEs256(payload, decodeBase64Url(envelope.signature.value), pem)) { "invalid_signature" }
        return PlainstrideJson.decodeFromString<AudioPackManifest>(payload.decodeToString())
            .also { validate(it, it.catalogVersion, remote = true) }
    }

    private fun validate(value: AudioPackManifest, version: String, remote: Boolean) {
        check(value.contractVersion == 1 && value.catalogVersion == version && value.entries.isNotEmpty()) { "invalid_catalog" }
        check(value.entries.all {
            it.approved && it.contentType == "audio/wav" && it.sha256.matches(Regex("[a-f0-9]{64}")) &&
                (it.byteCount == null || it.byteCount in 44..MAX_AUDIO_BYTES) &&
                (it.durationMilliseconds == null || it.durationMilliseconds in 1..8_000) &&
                (!remote || it.url?.startsWith("https://") == true)
        }) { "invalid_catalog_entry" }
    }

    private suspend fun fetch(url: String, limit: Int, contentType: String? = null): ByteArray {
        require(url.startsWith("https://")) { "invalid_asset_scheme" }
        val call = assetClient.newCall(Request.Builder().url(url).build())
        // OkHttp's blocking read runs on IO; cancellation actively interrupts its socket.
        return kotlinx.coroutines.suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : okhttp3.Callback {
                override fun onFailure(call: okhttp3.Call, error: java.io.IOException) {
                    continuation.resumeWith(Result.failure(error))
                }
                override fun onResponse(call: okhttp3.Call, response: okhttp3.Response) {
                    val result = runCatching {
                        response.use {
                            check(it.isSuccessful) { "http_status_${it.code}" }
                            val body = it.body ?: error("empty_body")
                            check(body.contentLength() in -1..limit.toLong()) { "asset_too_large" }
                            if (contentType != null) check(body.contentType()?.toString()?.startsWith(contentType) == true) { "invalid_content_type" }
                            val output = java.io.ByteArrayOutputStream()
                            val buffer = ByteArray(8 * 1024)
                            val input = body.byteStream()
                            while (output.size() <= limit) {
                                val read = input.read(buffer, 0, minOf(buffer.size, limit + 1 - output.size()))
                                if (read < 0) break
                                output.write(buffer, 0, read)
                            }
                            output.toByteArray().also { bytes -> check(bytes.size <= limit) { "asset_too_large" } }
                        }
                    }
                    continuation.resumeWith(result)
                }
            })
        }
    }

    private fun writeAtomically(file: File, bytes: ByteArray) {
        check(root.isDirectory || root.mkdirs()) { "create_directory_failed" }
        val atomic = android.util.AtomicFile(file)
        var stream: java.io.FileOutputStream? = null
        try {
            stream = atomic.startWrite()
            stream.write(bytes)
            atomic.finishWrite(stream)
        } catch (error: Exception) {
            stream?.let(atomic::failWrite)
            throw error
        }
    }

    private fun diagnostic(operation: String, error: Exception) {
        // Error messages/URLs can contain signed URLs. Only bounded status/code context is logged.
        val status = error.message?.takeIf { it.matches(Regex("http_status_[0-9]{3}")) }
        android.util.Log.w(TAG, "operation=$operation type=${error.javaClass.simpleName} status=${status ?: "none"}")
    }

    private fun verifyEs256(payload: ByteArray, signatureBytes: ByteArray, pem: String): Boolean {
        val der = Base64.decode(pem.replace(Regex("-----[^-]+-----|\\s"), ""), Base64.DEFAULT)
        val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(der))
        return Signature.getInstance("SHA256withECDSA").run { initVerify(key); update(payload); verify(signatureBytes) }
    }
    private fun decodeBase64Url(value: String) = Base64.decode(value, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    private fun sha256(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun normalize(value: String) = value.lowercase().replace(Regex("[^\\p{L}\\p{N}]"), "")
    private companion object {
        const val TAG = "PlainstrideVoicePack"
        const val MAX_AUDIO_BYTES = 512 * 1024
        const val MAX_MANIFEST_BYTES = 2 * 1024 * 1024
        val PRIORITY_KEYS = listOf("coach.speed_increase", "coach.speed_decrease", "workout.pause", "workout.resume")
    }
}
