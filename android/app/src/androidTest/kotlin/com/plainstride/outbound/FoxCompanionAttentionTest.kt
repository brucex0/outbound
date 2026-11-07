package com.plainstride.outbound

import androidx.test.platform.app.InstrumentationRegistry
import com.plainstride.outbound.feature.safety.InboxNotification
import com.plainstride.outbound.feature.safety.NotificationCenterSection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Focused policy coverage for the transient companion delivery ledger.
 * Receipts decide whether an interruption is allowed; the durable inbox is untouched.
 */
class FoxCompanionAttentionTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val preferencesName = "fox_companion_attention_tests"

    /** Noon today, so calendar-day math is stable in every device time zone. */
    private val now: Instant = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).plusHours(12).toInstant()

    /** 00:10 the next local day: a new day for the budget, still inside the 24-hour window. */
    private val nextMorning: Instant = LocalDate.now().plusDays(1).atStartOfDay(ZoneId.systemDefault()).plusMinutes(10).toInstant()
    private lateinit var attention: FoxCompanionAttention

    @Before fun setUp() {
        context.getSharedPreferences(preferencesName, 0).edit().clear().commit()
        attention = FoxCompanionAttention(context.getSharedPreferences(preferencesName, 0))
    }

    private fun notification(
        id: String,
        type: String,
        objectId: String? = null,
        readAt: String? = null,
        createdAt: Instant = now.minusSeconds(600),
    ) = InboxNotification(
        id = id,
        type = type,
        objectId = objectId,
        message = "Synthetic $id",
        readAt = readAt,
        createdAt = createdAt.toString(),
    )

    @Test fun claimPrefersActionableNeedsYouOverNewerCheers() {
        val item = requireNotNull(
            attention.claim(
                "account-a",
                listOf(
                    notification("cheer", "cheer", objectId = "post-1", createdAt = now.minusSeconds(60)),
                    notification("request", "connectionRequest", objectId = "connection-1", createdAt = now.minusSeconds(3_600)),
                ),
                now,
            ),
        ) { "Expected an actionable delivery" }

        assertEquals("request", item.primary.id)
        assertEquals(NotificationCenterSection.NEEDS_YOU, item.presentation.section)
    }

    @Test fun claimUsesCheersAndMilestonesWhenNothingIsActionable() {
        val item = requireNotNull(
            attention.claim(
                "account-a",
                listOf(
                    notification("accepted", "connectionAccepted", objectId = "connection-1", createdAt = now.minusSeconds(30)),
                    notification("cheer", "cheer", objectId = "post-1", createdAt = now.minusSeconds(90)),
                ),
                now,
            ),
        ) { "Expected a support delivery" }

        assertEquals("cheer", item.primary.id)
        assertEquals(NotificationCenterSection.CHEERS_AND_MILESTONES, item.presentation.section)
    }

    @Test fun claimIgnoresReadStaleFutureAndUpdatesOnlyItems() {
        val item = attention.claim(
            "account-a",
            listOf(
                notification("read", "connectionRequest", readAt = now.minusSeconds(30).toString()),
                notification("stale", "connectionRequest", createdAt = now.minusSeconds(25 * 60 * 60)),
                notification("future", "connectionRequest", createdAt = now.plusSeconds(600)),
                notification("update", "connectionAccepted", objectId = "connection-1", createdAt = now.minusSeconds(60)),
                notification("malformed", "connectionRequest").copy(createdAt = "not-a-date"),
            ),
            now,
        )

        assertNull(item)
    }

    @Test fun claimSkipsExpiredLiveInvitationButKeepsOtherTypesWithinADay() {
        // Cached live invitations stop being deliverable after eight hours;
        // every other type keeps the 24-hour freshness window.
        assertNull(
            attention.claim(
                "account-a",
                listOf(notification("live-old", "liveCheerInvitation", objectId = "session-1", createdAt = now.minusSeconds(9 * 60 * 60))),
                now,
            ),
        )

        val freshLive = requireNotNull(
            attention.claim(
                "account-a",
                listOf(notification("live-new", "liveCheerInvitation", objectId = "session-2", createdAt = now.minusSeconds(60 * 60))),
                now,
            ),
        ) { "Expected a fresh live invitation to still deliver" }
        assertEquals("live-new", freshLive.primary.id)

        val staleCheer = requireNotNull(
            attention.claim(
                "account-b",
                listOf(notification("cheer-old", "cheer", objectId = "post-1", createdAt = now.minusSeconds(9 * 60 * 60))),
                now,
            ),
        ) { "Expected a nine-hour-old Cheer to remain within the 24-hour window" }
        assertEquals("cheer-old", staleCheer.primary.id)
    }

    @Test fun claimIsLimitedToOnePerCalendarDayPerAccount() {
        val first = attention.claim(
            "account-a",
            listOf(notification("first", "connectionRequest", objectId = "connection-1")),
            now,
        )
        assertNotNull(first)

        val second = attention.claim(
            "account-a",
            listOf(notification("second", "runInvitation", objectId = "event-1", createdAt = now.minusSeconds(60))),
            now.plusSeconds(600),
        )
        assertNull(second)
    }

    @Test fun claimIsolatesAccountsAndKeepsTheirOwnDailyReceipt() {
        assertNotNull(
            attention.claim(
                "account-a",
                listOf(notification("a-item", "connectionRequest", objectId = "connection-1")),
                now,
            )
        )

        val forAccountB = attention.claim(
            "account-b",
            listOf(notification("b-item", "connectionRequest", objectId = "connection-2")),
            now,
        )
        assertNotNull(forAccountB)
        assertEquals("b-item", forAccountB!!.primary.id)

        assertNull(
            attention.claim(
                "account-a",
                listOf(notification("a-other", "runInvitation", objectId = "event-1", createdAt = now.minusSeconds(60))),
                now.plusSeconds(120),
            )
        )
    }

    @Test fun claimDoesNotReplayTheSameItemOnALaterDay() {
        val item = notification("request", "connectionRequest", objectId = "connection-1")
        assertNotNull(attention.claim("account-a", listOf(item), now))

        val tomorrow = nextMorning
        assertNull(attention.claim("account-a", listOf(item), tomorrow))

        // A genuinely new item is still eligible on the later day.
        val fresh = notification("fresh", "connectionRequest", objectId = "connection-2", createdAt = tomorrow.minusSeconds(60))
        val delivered = attention.claim("account-a", listOf(item, fresh), tomorrow)
        assertNotNull(delivered)
        assertEquals("fresh", delivered!!.primary.id)
    }

    @Test fun claimRecordsReceiptsForEveryGroupedNotification() {
        val grouped = listOf(
            notification("cheer-1", "cheer", objectId = "post-1", createdAt = now.minusSeconds(120)),
            notification("cheer-2", "cheer", objectId = "post-1", createdAt = now.minusSeconds(60)),
        )
        val item = requireNotNull(attention.claim("account-a", grouped, now)) { "Expected a grouped delivery" }
        assertEquals(2, item.notifications.size)

        val tomorrow = nextMorning
        // The group members are still fresh, so only their receipts can suppress them.
        assertNull(attention.claim("account-a", grouped, tomorrow))
    }

    @Test fun claimFiltersReadMembersBeforeAggregatingGroup() {
        val item = requireNotNull(
            attention.claim(
                "account-a",
                listOf(
                    notification("cheer-new-read", "cheer", objectId = "post-1", readAt = now.minusSeconds(30).toString(), createdAt = now.minusSeconds(60)),
                    notification("cheer-old-unread", "cheer", objectId = "post-1", createdAt = now.minusSeconds(300)),
                ),
                now,
            ),
        ) { "Expected the older unread Cheer to still deliver" }

        assertEquals("cheer-old-unread", item.primary.id)
        assertEquals(1, item.notifications.size)
        assertEquals(0, item.additionalCount)
    }

    @Test fun clearAccountRemovesOnlyTheDeletedAccountsReceipts() {
        val forA = notification("a-item", "connectionRequest", objectId = "connection-1")
        val forB = notification("b-item", "connectionRequest", objectId = "connection-2")
        assertNotNull(attention.claim("account-a", listOf(forA), now))
        assertNotNull(attention.claim("account-b", listOf(forB), now))

        attention.clearAccount("account-a")

        // A fresh calendar day for A: with its receipts cleared the item is eligible again.
        val redelivered = attention.claim("account-a", listOf(forA), nextMorning)
        assertNotNull("Account deletion must remove that account's receipts", redelivered)
        assertEquals("a-item", redelivered!!.primary.id)

        // Account B keeps its receipts, so the same item still cannot replay.
        assertNull(attention.claim("account-b", listOf(forB), nextMorning))
    }
}
