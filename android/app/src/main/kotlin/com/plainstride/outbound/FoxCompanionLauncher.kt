package com.plainstride.outbound

import android.animation.ValueAnimator
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.MailOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.SemanticsPropertyKey
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import com.plainstride.outbound.core.designsystem.PlainstrideFloatingAction
import com.plainstride.outbound.core.designsystem.PlainstrideFloatingActionStyle
import com.plainstride.outbound.core.designsystem.R as DesignSystemR
import com.plainstride.outbound.feature.safety.InboxNotification
import com.plainstride.outbound.feature.safety.NotificationCenterItem
import com.plainstride.outbound.feature.safety.NotificationCenterSection
import com.plainstride.outbound.feature.safety.R as SafetyR
import com.plainstride.outbound.feature.social.R as SocialR
import kotlinx.coroutines.delay

internal val FoxCompanionState = SemanticsPropertyKey<String>("FoxCompanionState")

@Composable
internal fun FoxCompanionLauncher(
    eligible: Boolean,
    notifications: List<InboxNotification>,
    claimDelivery: () -> NotificationCenterItem?,
    onPresence: (String) -> Unit,
    onAction: (String) -> Unit,
    onOpenAssistant: () -> Unit,
    onOpenInbox: () -> Unit,
    onOpenNotification: (NotificationCenterItem) -> Unit,
) {
    val context = LocalContext.current
    val previewTimeout = remember(context) {
        if (Build.VERSION.SDK_INT >= 29) {
            context.getSystemService(AccessibilityManager::class.java)?.getRecommendedTimeoutMillis(
                7_000, AccessibilityManager.FLAG_CONTENT_TEXT or AccessibilityManager.FLAG_CONTENT_CONTROLS,
            )?.toLong() ?: 7_000L
        } else 7_000L
    }
    val reducedMotion = companionReducedMotion()
    val rotation = remember { Animatable(0f) }
    val hop = remember { Animatable(0f) }
    var preview by remember { mutableStateOf<NotificationCenterItem?>(null) }
    var idleTracked by remember { mutableStateOf(false) }
    var laidOut by remember { mutableStateOf(false) }
    val latestPresence by rememberUpdatedState(onPresence)
    val latestClaim by rememberUpdatedState(claimDelivery)
    val hasUnread = notifications.any { it.readAt == null }

    LaunchedEffect(eligible, laidOut, notifications) {
        if (!eligible || !laidOut) {
            preview = null
            return@LaunchedEffect
        }
        // Visible idle exposure is recorded as soon as the launcher is on screen,
        // including with Reduce Motion. The guard keeps it once per composition.
        if (!idleTracked) {
            latestPresence("idle")
            idleTracked = true
        }
        // Only claim when the launcher is visible and the window accepts interaction.
        if (preview == null && notifications.isNotEmpty()) latestClaim()?.let {
            preview = it
            latestPresence("delivery")
        }
        preview?.let { shown ->
            val unreadIds = notifications.filter { it.readAt == null }.map { it.id }.toSet()
            if (shown.notifications.none { it.id in unreadIds }) preview = null
        }
    }
    LaunchedEffect(preview?.id) {
        if (preview != null) {
            delay(previewTimeout)
            preview = null
        }
    }
    LaunchedEffect(eligible, laidOut, reducedMotion, preview?.id) {
        rotation.snapTo(0f)
        hop.snapTo(0f)
        if (!eligible || !laidOut || reducedMotion) return@LaunchedEffect
        if (preview != null) {
            if (preview?.presentation?.section == NotificationCenterSection.NEEDS_YOU) {
                hop.animateTo(-6f, tween(180))
                hop.animateTo(0f, tween(260))
            } else {
                rotation.animateTo(-5f, tween(300))
                rotation.animateTo(0f, tween(350))
            }
        }
        delay(20_000)
        while (true) {
            rotation.animateTo(-5f, tween(300))
            delay(250)
            rotation.animateTo(0f, tween(350))
            delay(30_000)
        }
    }

    Box(Modifier.size(56.dp).onGloballyPositioned { coordinates ->
        laidOut = coordinates.isAttached && coordinates.boundsInWindow().let { it.width > 0 && it.height > 0 }
    }.testTag("fox-companion-launcher").semantics {
        this[FoxCompanionState] = if (preview != null) "delivery" else "idle"
    }, contentAlignment = Alignment.Center) {
        PlainstrideFloatingAction(
            style = PlainstrideFloatingActionStyle.Accent,
            actionSize = 56.dp,
            onClick = onOpenAssistant,
        ) {
            Image(
                painterResource(DesignSystemR.drawable.plainstride_fox_assistant_head),
                stringResource(R.string.tab_assistant),
                Modifier.size(50.dp).graphicsLayer {
                    rotationZ = rotation.value
                    translationY = hop.value.dp.toPx()
                },
            )
        }
        if (eligible && hasUnread) {
            // A distinct target: the fox always opens the assistant.
            val envelopeOffset = with(LocalDensity.current) { IntOffset(4.dp.roundToPx(), (-28).dp.roundToPx()) }
            Popup(
                alignment = Alignment.TopEnd,
                offset = envelopeOffset,
                properties = PopupProperties(focusable = false),
            ) {
                IconButton(
                    onClick = { preview = null; onAction("envelope_opened"); onOpenInbox() },
                    modifier = Modifier.size(48.dp).testTag("fox-companion-envelope"),
                ) {
                    Surface(shape = CircleShape, color = MaterialTheme.colorScheme.secondaryContainer, shadowElevation = 2.dp) {
                        Icon(Icons.Outlined.MailOutline, stringResource(SocialR.string.social_notifications), Modifier.padding(4.dp).size(20.dp))
                    }
                }
            }
        }
        val item = preview
        if (eligible && item != null) {
            val offset = with(LocalDensity.current) { 88.dp.roundToPx() }
            Popup(
                alignment = Alignment.BottomStart,
                offset = IntOffset(0, -offset),
                onDismissRequest = { preview = null },
                properties = PopupProperties(focusable = false),
            ) {
                Surface(shape = RoundedCornerShape(18.dp), tonalElevation = 6.dp, shadowElevation = 4.dp) {
                    Row(Modifier.widthIn(max = 320.dp).testTag("fox-companion-preview").semantics { liveRegion = LiveRegionMode.Polite }, verticalAlignment = Alignment.CenterVertically) {
                        TextButton(
                            onClick = { preview = null; onAction("notification_preview"); onOpenNotification(item) },
                            modifier = Modifier.weight(1f).testTag("fox-companion-preview-open"),
                            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                        ) {
                            // Reuse the localized, share-safe durable inbox message.
                            Column {
                                Text(item.primary.message, style = MaterialTheme.typography.bodyMedium)
                                if (item.additionalCount > 0) {
                                    Text(stringResource(SafetyR.string.inbox_additional_count, item.additionalCount), style = MaterialTheme.typography.bodySmall)
                                }
                            }
                        }
                        IconButton(onClick = { preview = null; onAction("notification_dismissed") }, modifier = Modifier.testTag("fox-companion-preview-dismiss")) {
                            Icon(Icons.Default.Close, stringResource(R.string.fox_companion_dismiss_preview))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun companionReducedMotion(): Boolean {
    val context = LocalContext.current
    var reducedMotion by remember { mutableStateOf(!ValueAnimator.areAnimatorsEnabled()) }
    DisposableEffect(context) {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) { reducedMotion = !ValueAnimator.areAnimatorsEnabled() }
        }
        context.contentResolver.registerContentObserver(Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE), false, observer)
        onDispose { context.contentResolver.unregisterContentObserver(observer) }
    }
    return reducedMotion
}
