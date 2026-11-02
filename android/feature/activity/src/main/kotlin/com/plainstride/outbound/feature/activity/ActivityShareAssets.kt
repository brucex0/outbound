package com.plainstride.outbound.feature.activity

import android.graphics.Bitmap
import android.util.Log
import com.plainstride.outbound.core.data.ActivityMediaStore
import com.plainstride.outbound.core.data.ActivityPhotoRepository
import com.plainstride.outbound.core.model.activity.SavedActivity
import com.plainstride.outbound.core.network.AccessTokenProvider
import javax.inject.Inject
import javax.inject.Named
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.json.*
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

data class ActivityShareAssets(val referralUrl: String, val avatar: Bitmap?, val photos: Map<String, Bitmap>)

class ActivityShareAssetLoader @Inject constructor(
    private val client: OkHttpClient,
    private val tokens: AccessTokenProvider,
    private val media: ActivityMediaStore,
    private val photos: ActivityPhotoRepository,
    @param:Named("apiBaseUrl") private val baseUrl: String,
) {
    suspend fun load(activity: SavedActivity): ActivityShareAssets = coroutineScope {
        val identity = async(Dispatchers.IO) {
            val token = tokens.validAccessToken()
            if (token == null) {
                Log.w("ActivityShare", "Share identity unavailable: unauthenticated")
                return@async "https://plainstride.ai/invite" to null
            }
            val referral = jsonRequest("v1/social/referrals", token, post = true)?.get("url")?.jsonPrimitive?.contentOrNull
                ?: "https://plainstride.ai/invite"
            val avatarUrl = jsonRequest("v1/auth/me", token)?.get("avatarUrl")?.jsonPrimitive?.contentOrNull
            val avatar = avatarUrl?.let { source ->
                val url = source.toHttpUrlOrNull() ?: baseUrl.toHttpUrlOrNull()?.resolve(source)
                url?.let { requestBytes(Request.Builder().url(it).build(), "avatar") }?.let { decodeActivityPhoto(it, 192) }
            }
            referral to avatar
        }
        val thumbnails = activity.photos.map { photo -> async(Dispatchers.IO) {
            val localPath = photo.localRelativePath
            val bytes = if (localPath != null) try { media.read(localPath) } catch (error: Exception) {
                Log.w("ActivityShare", "Local share photo unavailable type=${error.javaClass.simpleName}")
                null
            } else null
            val source = bytes ?: photo.remotePhotoId?.let { photos.load(it, thumbnail = true).getOrNull() }
            photo.id to source?.let { decodeActivityPhoto(it, 288) }
        } }.mapNotNull { task -> task.await().let { (id, bitmap) -> bitmap?.let { id to it } } }.toMap()
        val (url, avatar) = identity.await()
        ActivityShareAssets(url, avatar, thumbnails)
    }

    private fun jsonRequest(path: String, token: String, post: Boolean = false): JsonObject? {
        val base = requireNotNull(baseUrl.toHttpUrlOrNull())
        val request = Request.Builder().url(requireNotNull(base.resolve("/$path"))).header("Authorization", "Bearer $token")
        if (post) request.post(ByteArray(0).toRequestBody())
        val bytes = requestBytes(request.build(), if (post) "referral" else "profile") ?: return null
        return try { Json.parseToJsonElement(bytes.decodeToString()).jsonObject } catch (error: IllegalArgumentException) {
            Log.w("ActivityShare", "Share identity decode failed type=${error.javaClass.simpleName}")
            null
        }
    }

    private fun requestBytes(request: Request, operation: String): ByteArray? = try {
        client.newBuilder().callTimeout(java.time.Duration.ofSeconds(8)).build().newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                Log.w("ActivityShare", "Share $operation failed status=${response.code}")
                null
            } else response.body?.bytes()
        }
    } catch (error: java.io.IOException) {
        Log.w("ActivityShare", "Share $operation failed type=${error.javaClass.simpleName}")
        null
    }
}
