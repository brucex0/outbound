package com.plainstride.outbound.feature.social

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request

private object AvatarCache {
    val bitmaps = LruCache<String, Bitmap>(8 * 1024 * 1024)
    val requests = ConcurrentHashMap<String, Deferred<Bitmap?>>()
}

@EntryPoint
@InstallIn(SingletonComponent::class)
internal interface SocialAvatarDependencies {
    fun httpClient(): OkHttpClient
}

@Composable
fun SocialAvatar(person: SocialPerson, size: Dp = 42.dp, modifier: Modifier = Modifier) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val source = normalizedAvatarUrl(person.avatarUrl)
    val cachedBitmap = source?.let(AvatarCache.bitmaps::get)
    val bitmap by produceState<Bitmap?>(cachedBitmap, source) {
        source ?: return@produceState
        if (value == null) value = coroutineScope {
            AvatarCache.requests[source] ?: async(Dispatchers.IO) {
                val client = EntryPointAccessors.fromApplication(
                    context.applicationContext,
                    SocialAvatarDependencies::class.java,
                ).httpClient()
                runCatching {
                    client.newCall(Request.Builder().url(source).build()).execute().use { response ->
                        if (!response.isSuccessful) return@use null
                        response.body?.bytes()?.let {
                            bytes -> BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                        }
                    }
                }.getOrNull()?.also { AvatarCache.bitmaps.put(source, it) }
            }.also { AvatarCache.requests[source] = it }
        }.await().also {
            AvatarCache.requests.remove(source)
        }
    }
    Box(modifier.size(size).clip(CircleShape).background(MaterialTheme.colorScheme.secondaryContainer), contentAlignment = Alignment.Center) {
        if (bitmap != null) Image(bitmap!!.asImageBitmap(), person.displayName, Modifier.matchParentSize(), contentScale = ContentScale.Crop)
        else Text(
            person.displayName.trim().split(Regex("\\s+")).take(2).mapNotNull { it.firstOrNull() }.joinToString("").uppercase(),
            color = MaterialTheme.colorScheme.onSecondaryContainer,
        )
    }
}

private fun normalizedAvatarUrl(value: String?): String? {
    val url = value?.trim()?.toHttpUrlOrNull() ?: return null
    if (url.isHttps || url.host in LocalDevelopmentHosts) return url.toString()
    return url.newBuilder().scheme("https").build().toString()
}

private val LocalDevelopmentHosts = setOf("localhost", "127.0.0.1", "10.0.2.2")
