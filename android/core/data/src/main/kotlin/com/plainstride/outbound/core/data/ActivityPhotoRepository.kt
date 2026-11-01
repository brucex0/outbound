package com.plainstride.outbound.core.data

import android.content.Context
import android.util.Log
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.database.ActivityDao
import com.plainstride.outbound.core.network.AccessTokenProvider
import com.plainstride.outbound.core.network.ActivitiesApiService
import com.plainstride.outbound.core.network.ApiErrorCode
import com.plainstride.outbound.core.network.ApiFailure
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.security.MessageDigest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

class ActivityPhotoException(val failure: ApiFailure) : IOException(failure.code.name)

/** One byte cache for stored activities, Social detail, feed thumbnails, and Group moments. */
class ActivityPhotoRepository(
    context: Context,
    private val api: ActivitiesApiService,
    private val tokens: AccessTokenProvider,
    private val dao: ActivityDao,
    private val media: ActivityMediaStore,
    private val analytics: ProductAnalytics,
    private val currentAccountId: () -> String?,
) {
    private val root = File(context.cacheDir, "activity-photos")
    // Bounded locks coalesce concurrent requests without retaining photo IDs in memory.
    private val locks = Array(32) { Mutex() }

    suspend fun load(photoId: String, thumbnail: Boolean = false): Result<ByteArray> = withContext(Dispatchers.IO) {
        val account = currentAccountId() ?: return@withContext failure(ApiErrorCode.Unauthenticated)
        val key = digest("$account:$photoId:$thumbnail")
        locks[(key.hashCode() and Int.MAX_VALUE) % locks.size].withLock {
            try {
                checkAccount(account)
                // Originals already owned by the local activity need no second disk copy.
                if (!thumbnail) dao.photoByRemoteId(account, photoId)?.localRelativePath?.let { path ->
                    read { media.read(path) }?.let { bytes ->
                        checkAccount(account)
                        return@withLock Result.success(bytes)
                    }
                }
                val file = File(File(root, digest(account)), key)
                val cached = read { file.readBytes() }
                if (cached != null && System.currentTimeMillis() - file.lastModified() < CACHE_TTL_MS) {
                    checkAccount(account)
                    return@withLock Result.success(cached)
                }
                val token = tokens.validAccessToken()
                checkAccount(account)
                if (token == null) return@withLock failure(ApiErrorCode.Unauthenticated)
                val response = if (thumbnail) api.activityPhotoThumbnail("Bearer $token", photoId)
                    else api.activityPhotoContent("Bearer $token", photoId)
                try {
                    checkAccount(account)
                    if (!response.isSuccessful) {
                        response.errorBody()?.close()
                        val code = when (response.code()) {
                            401 -> ApiErrorCode.Unauthenticated
                            403 -> ApiErrorCode.Forbidden
                            404, 410 -> ApiErrorCode.NotFound
                            429 -> ApiErrorCode.RateLimited
                            in 500..599 -> ApiErrorCode.ServerUnavailable
                            else -> ApiErrorCode.InvalidResponse
                        }
                        Log.w(TAG, "download_failed representation=${representation(thumbnail)} status=${response.code()}")
                        if (code in setOf(ApiErrorCode.Unauthenticated, ApiErrorCode.Forbidden, ApiErrorCode.NotFound)) {
                            if (file.exists() && !file.delete()) Log.w(TAG, "cache_invalidate_failed")
                        }
                        return@withLock failure(code, response.code())
                    }
                    val bytes = response.body()?.use { it.bytes() }
                    currentCoroutineContext().ensureActive()
                    checkAccount(account)
                    if (bytes == null || bytes.isEmpty()) {
                        Log.w(TAG, "download_failed representation=${representation(thumbnail)} empty_body=true")
                        return@withLock failure(ApiErrorCode.InvalidResponse)
                    }
                    // Keep original bytes and EXIF untouched. Cache failure must not hide a downloaded image.
                    var cachedToDisk = false
                    try {
                        file.parentFile?.mkdirs()
                        val temporary = File(file.parentFile, ".${file.name}.tmp")
                        try {
                            temporary.writeBytes(bytes)
                            check(temporary.renameTo(file)) { "Photo cache rename failed" }
                            cachedToDisk = true
                        } finally { if (temporary.exists() && !temporary.delete()) Log.w(TAG, "cache_temporary_cleanup_failed") }
                        trim(file)
                    } catch (error: Exception) {
                        Log.w(TAG, "cache_write_failed type=${error.javaClass.simpleName}")
                    }
                    if (cachedToDisk) analytics.record(AnalyticsEvent("feature_exposed", mapOf(AnalyticsProperty.Feature to "activity_photo_cached")))
                    Result.success(bytes)
                } finally {
                    response.body()?.close()
                    response.errorBody()?.close()
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: ActivityPhotoException) {
                Result.failure(error) // Account switch is expected control flow.
            } catch (error: Exception) {
                Log.w(TAG, "load_failed representation=${representation(thumbnail)} type=${error.javaClass.simpleName}")
                failure(if (error is IOException) ApiErrorCode.NetworkUnavailable else ApiErrorCode.InvalidResponse)
            }
        }
    }

    private fun checkAccount(account: String) {
        if (currentAccountId() != account) throw ActivityPhotoException(ApiFailure(ApiErrorCode.Unauthenticated, false))
    }

    private fun read(load: () -> ByteArray): ByteArray? = try {
        load().takeIf { it.isNotEmpty() }
    } catch (_: FileNotFoundException) {
        null // A missing/evicted file is a normal cache miss.
    } catch (error: IOException) {
        Log.w(TAG, "cache_read_failed type=${error.javaClass.simpleName}")
        null
    }

    private fun trim(keep: File) {
        val files = root.walkTopDown().filter { it.isFile && !it.name.startsWith('.') }.toList()
        var bytes = files.sumOf { it.length() }
        for (file in files.sortedBy { it.lastModified() }) {
            if (bytes <= MAX_CACHE_BYTES) break
            if (file == keep) continue
            val size = file.length()
            if (file.delete()) bytes -= size else Log.w(TAG, "cache_trim_failed")
        }
    }

    private fun failure(code: ApiErrorCode, status: Int? = null): Result<ByteArray> =
        Result.failure(ActivityPhotoException(ApiFailure(code, code == ApiErrorCode.NetworkUnavailable, status)))

    private fun representation(thumbnail: Boolean) = if (thumbnail) "thumbnail" else "content"
    private fun digest(value: String) = MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }

    private companion object {
        const val TAG = "PlainstridePhoto"
        const val CACHE_TTL_MS = 15 * 60_000L
        const val MAX_CACHE_BYTES = 64 * 1024 * 1024L
    }
}
