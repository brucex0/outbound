package com.plainstride.outbound.feature.social

import android.graphics.ImageDecoder
import android.text.format.DateUtils
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Photo
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.nio.ByteBuffer
import java.time.OffsetDateTime
import java.util.Locale

@Composable internal fun groupMomentText(moment: GroupMoment): String = when (moment.type) {
    "completed_activity" -> moment.title ?: stringResource(R.string.moment_activity)
    "weekly_completion" -> stringResource(R.string.moment_weekly)
    else -> stringResource(R.string.moment_cheer)
}

@Composable internal fun groupMomentRelativeTime(value: String): String {
    val timestamp = runCatching { OffsetDateTime.parse(value).toInstant().toEpochMilli() }.getOrNull() ?: return ""
    return DateUtils.getRelativeTimeSpanString(timestamp, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS, DateUtils.FORMAT_ABBREV_RELATIVE).toString()
}

@Composable internal fun GroupMomentDetailScreen(
    group: GroupSummary, moment: GroupMoment, unitSystem: MeasurementUnitSystem,
    close: () -> Unit, trackOpened: (String) -> Unit,
    loadResults: suspend (String) -> Result<ActivityEventResult>, loadPhoto: suspend (String) -> ByteArray?,
) {
    BackHandler(onBack = close)
    LaunchedEffect(moment.id) { trackOpened(moment.type) }
    val context = LocalContext.current
    val date = remember(moment.createdAt, context.resources.configuration.locales[0]) {
        runCatching { java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.FULL, java.text.DateFormat.SHORT,
            context.resources.configuration.locales[0]).format(java.util.Date.from(OffsetDateTime.parse(moment.createdAt).toInstant())) }.getOrDefault("")
    }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column {
            Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(close) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.social_done)) }
                Text(stringResource(R.string.moment_details), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            }
            Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp)) {
                ElevatedCard {
                    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text(groupMomentText(moment), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                        Text(group.name, style = MaterialTheme.typography.titleMedium)
                        Text(date, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        if (moment.type == "completed_activity" && moment.id.startsWith("event:")) {
                            MomentResults(moment.id.removePrefix("event:"), unitSystem, loadResults, loadPhoto)
                        }
                        if (moment.type == "cheer") {
                            Text(stringResource(when (moment.title) { "celebration" -> R.string.moment_celebration; "support" -> R.string.moment_support; else -> R.string.moment_encouragement }), style = MaterialTheme.typography.titleMedium)
                            group.cheers.firstOrNull { "cheer:${it.id}" == moment.id }?.let { cheer ->
                                val sender = group.members.firstOrNull { it.person.id == cheer.senderUserId }
                                val recipient = group.members.firstOrNull { it.person.id == cheer.recipientUserId }
                                if (sender != null && recipient != null) Text("${sender.person.displayName} → ${recipient.person.displayName}", style = MaterialTheme.typography.bodyMedium)
                            }
                        } else if (moment.type == "weekly_completion" && moment.id == "completion:${group.week.id}") {
                            momentThemeTitle(group.week)?.let { title ->
                                Text(title, style = MaterialTheme.typography.titleMedium)
                                group.week.themeNote?.takeIf { it.isNotEmpty() }?.let { Text(it) }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable private fun momentThemeTitle(week: GroupWeek): String? {
    if (week.themeKey == "custom") return week.themeTitle
    val resource = when (week.themeKey) {
        "build_consistency" -> R.string.moment_theme_build_consistency
        "one_small_step" -> R.string.moment_theme_one_small_step
        "keep_the_rhythm" -> R.string.moment_theme_keep_the_rhythm
        "move_for_your_mood" -> R.string.moment_theme_move_for_your_mood
        "recover_and_recharge" -> R.string.moment_theme_recover_and_recharge
        "do_something_together" -> R.string.moment_theme_do_something_together
        "explore_somewhere_new" -> R.string.moment_theme_explore_somewhere_new
        "try_something_different" -> R.string.moment_theme_try_something_different
        "celebrate_every_effort" -> R.string.moment_theme_celebrate_every_effort
        else -> return null
    }
    return stringResource(resource)
}

@Composable private fun MomentResults(eventId: String, units: MeasurementUnitSystem,
    load: suspend (String) -> Result<ActivityEventResult>, loadPhoto: suspend (String) -> ByteArray?) {
    var results by remember(eventId) { mutableStateOf<ActivityEventResult?>(null) }
    var loading by remember(eventId) { mutableStateOf(true) }
    var failed by remember(eventId) { mutableStateOf(false) }
    var retry by remember(eventId) { mutableIntStateOf(0) }
    LaunchedEffect(eventId, retry) {
        loading = true; failed = false
        val response = load(eventId)
        results = response.getOrNull(); failed = response.isFailure; loading = false
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        HorizontalDivider()
        Text(stringResource(R.string.moment_results), style = MaterialTheme.typography.titleMedium)
        when {
            loading -> CircularProgressIndicator(Modifier.size(24.dp))
            failed -> {
                Text(stringResource(R.string.moment_results_failed), color = MaterialTheme.colorScheme.onSurfaceVariant)
                TextButton({ retry++ }) { Text(stringResource(R.string.moment_results_retry)) }
            }
            else -> results?.let { data ->
                if (data.status == "reconciling") Text(stringResource(R.string.moment_collecting), style = MaterialTheme.typography.bodySmall)
                if (data.participants.isEmpty()) Text(stringResource(R.string.moment_results_empty), color = MaterialTheme.colorScheme.onSurfaceVariant)
                data.participants.forEach { participant ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        SocialAvatar(participant.person)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(participant.person.displayName, fontWeight = FontWeight.SemiBold)
                            val result = participant.result
                            val label = if (result != null || participant.outcome == "completed") {
                                result?.distanceM?.let { meters ->
                                    val distance = meters / if (units == MeasurementUnitSystem.metric) 1000.0 else 1609.344
                                    val unit = if (units == MeasurementUnitSystem.metric) "km" else "mi"
                                    stringResource(R.string.moment_completed_distance, String.format(Locale.getDefault(), "%.1f %s", distance, unit))
                                } ?: stringResource(R.string.moment_finished)
                            } else stringResource(when (participant.outcome) { "no_recording" -> R.string.moment_no_recording; "did_not_participate" -> R.string.moment_not_participated; else -> R.string.moment_waiting })
                            Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            if (!result?.photos.isNullOrEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                result!!.photos.forEach { photo ->
                                    (photo.thumbnailUrl ?: photo.url)?.let { url -> MomentPhoto(url, loadPhoto) }
                                }
                            }
                            result?.durationSecs?.let { seconds ->
                                Text(String.format(Locale.getDefault(), "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable private fun MomentPhoto(url: String, load: suspend (String) -> ByteArray?) {
    // ImageDecoder preserves EXIF rotation/mirroring; decoding stays off the UI thread.
    val bitmap by produceState<android.graphics.Bitmap?>(null, url) {
        val cached = MomentPhotoCache.images.get(url)
        if (cached != null) { value = cached; return@produceState }
        val bytes = load(url)
        value = bytes?.let { withContext(Dispatchers.Default) {
            try { ImageDecoder.decodeBitmap(ImageDecoder.createSource(ByteBuffer.wrap(it))) { decoder, info, _ ->
                val largest = maxOf(info.size.width, info.size.height)
                if (largest > 720) decoder.setTargetSize((info.size.width * 720.0 / largest).toInt().coerceAtLeast(1), (info.size.height * 720.0 / largest).toInt().coerceAtLeast(1))
            } }
            catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { android.util.Log.w("PlainstrideSocial", "Decode moment photo failed (type ${error.javaClass.simpleName})"); null }
        } }
        value?.let { MomentPhotoCache.images.put(url, it) }
    }
    Box(Modifier.size(132.dp, 100.dp).clip(RoundedCornerShape(8.dp)), contentAlignment = Alignment.Center) {
        bitmap?.let { Image(it.asImageBitmap(), stringResource(R.string.moment_photo), Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
            ?: Icon(Icons.Outlined.Photo, stringResource(R.string.moment_photo), tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

// A bounded in-memory cache keeps back/forward navigation from downloading and decoding again.
private object MomentPhotoCache {
    val images = object : android.util.LruCache<String, android.graphics.Bitmap>(16 * 1024 * 1024) {
        override fun sizeOf(key: String, value: android.graphics.Bitmap): Int = value.allocationByteCount
    }
}
