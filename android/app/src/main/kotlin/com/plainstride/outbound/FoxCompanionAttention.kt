package com.plainstride.outbound

import android.content.SharedPreferences
import android.util.Log
import com.plainstride.outbound.feature.safety.InboxNotification
import com.plainstride.outbound.feature.safety.NotificationCenterItem
import com.plainstride.outbound.feature.safety.NotificationCenterSection
import com.plainstride.outbound.feature.safety.NotificationPresentationPolicy
import java.security.MessageDigest
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeParseException

/** Presentation receipts only. The durable inbox still owns read and resolution state. */
internal class FoxCompanionAttention(private val preferences: SharedPreferences) {
    companion object {
        const val PREFERENCES = "fox_companion_attention"
    }

    private var loggedInvalidTimestamp = false
    @Synchronized
    fun claim(accountId: String, notifications: List<InboxNotification>, now: Instant = Instant.now()): NotificationCenterItem? {
        val accountKey = digest(accountId)
        val day = LocalDate.ofInstant(now, ZoneId.systemDefault()).toString()
        if (preferences.getString("$accountKey.day", null) == day) return null
        // Receipts outlive the freshness window, so pruning cannot replay an eligible event.
        val receipts = preferences.getStringSet("$accountKey.seen", emptySet()).orEmpty().mapNotNull { entry ->
            val parts = entry.split(':', limit = 2)
            val timestamp = parts.getOrNull(1)?.toLongOrNull() ?: return@mapNotNull null
            parts[0].takeIf { timestamp >= now.minus(Duration.ofDays(2)).epochSecond }?.let { it to timestamp }
        }.toMap().toMutableMap()
        val eligible = notifications.filter { notification ->
            if (notification.readAt != null || digest(notification.id) in receipts ||
                NotificationPresentationPolicy.presentationFor(notification.type, notification.objectId).section == NotificationCenterSection.UPDATES
            ) return@filter false
            // The inbox model permits a missing date. It stays visible without claiming freshness.
            val created = if (notification.createdAt.isBlank()) null else try {
                Instant.parse(notification.createdAt)
            } catch (_: DateTimeParseException) {
                if (!loggedInvalidTimestamp) {
                    Log.w("PlainstrideCompanion", "companion_delivery_freshness failed error=invalid_timestamp")
                    loggedInvalidTimestamp = true
                }
                null
            }
            created != null &&
                !created.isBefore(now.minus(Duration.ofDays(1))) && !created.isAfter(now.plusSeconds(300)) &&
                (notification.type != "liveCheerInvitation" || created.isAfter(now.minus(Duration.ofHours(8))))
        }
        val item = NotificationPresentationPolicy.items(eligible).firstOrNull() ?: return null
        item.notifications.forEach { receipts[digest(it.id)] = now.epochSecond }
        val saved = preferences.edit()
            .putString("$accountKey.day", day)
            .putStringSet("$accountKey.seen", receipts.map { (id, timestamp) -> "$id:$timestamp" }.toSet())
            .commit()
        if (!saved) {
            Log.w("PlainstrideCompanion", "delivery_receipt_write failed operation=claim")
            return null
        }
        return item
    }

    /** Account deletion clears only that account's presentation receipts. */
    @Synchronized
    fun clearAccount(accountId: String) {
        val accountKey = digest(accountId)
        val cleared = preferences.edit()
            .remove("$accountKey.day")
            .remove("$accountKey.seen")
            .commit()
        if (!cleared) {
            Log.w("PlainstrideCompanion", "companion_receipt_clear failed operation=account_deletion")
        }
    }

    private fun digest(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
}
