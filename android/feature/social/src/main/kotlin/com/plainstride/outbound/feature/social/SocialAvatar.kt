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
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private object AvatarCache {
    val bitmaps = LruCache<String, Bitmap>(8 * 1024 * 1024)
}

@Composable
fun SocialAvatar(person: SocialPerson, size: Dp = 42.dp, modifier: Modifier = Modifier) {
    val source = person.avatarUrl
    val cachedBitmap = source?.let(AvatarCache.bitmaps::get)
    val bitmap by produceState<Bitmap?>(cachedBitmap, source) {
        source ?: return@produceState
        if (value == null) value = withContext(Dispatchers.IO) {
            runCatching {
                val connection = URL(source).openConnection() as HttpURLConnection
                connection.connectTimeout = 5_000
                connection.readTimeout = 5_000
                connection.instanceFollowRedirects = true
                connection.inputStream.use(BitmapFactory::decodeStream).also { connection.disconnect() }
            }.getOrNull()?.also { AvatarCache.bitmaps.put(source, it) }
        }
    }
    Box(modifier.size(size).clip(CircleShape).background(MaterialTheme.colorScheme.secondaryContainer), contentAlignment = Alignment.Center) {
        if (bitmap != null) Image(bitmap!!.asImageBitmap(), person.displayName, Modifier.matchParentSize(), contentScale = ContentScale.Crop)
        else Text(person.displayName.trim().take(1).uppercase(), color = MaterialTheme.colorScheme.onSecondaryContainer)
    }
}
