package com.plainstride.outbound.feature.recording

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.test.platform.app.InstrumentationRegistry
import com.plainstride.outbound.core.designsystem.R
import com.plainstride.outbound.core.model.activity.GroupActivityParticipant
import com.plainstride.outbound.core.model.activity.GroupActivityPerson
import com.plainstride.outbound.core.model.activity.SharedLiveParticipant
import com.plainstride.outbound.core.model.activity.SharedLiveRun
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/**
 * Focused UI checks for the live group map participant pills: localized update
 * age, reported GPS accuracy, and the 15-second freshness window that also fades
 * stale map pins.
 */
class GroupParticipantStripTest {
    @get:Rule val ui = createComposeRule()

    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val base = Instant.parse("2026-11-03T12:00:00Z")

    @Test
    fun freshParticipantShowsUpdateAgeAndReportedAccuracy() {
        val alice = participant("person-2", "Alice Lee", base.minusSeconds(4), accuracy = 12.0)
        showStrip(listOf(alice to "Alice Lee"), displayedAt = base)

        val accuracy = context.getString(R.string.group_activity_location_accuracy, 12)
        assertEquals("GPS accuracy ±12 m", accuracy)
        ui.onNodeWithText(context.getString(R.string.group_activity_location_recent, formatDuration(4))).assertIsDisplayed()
        ui.onNodeWithText(accuracy).assertIsDisplayed()
    }

    @Test
    fun fixOlderThanFifteenSecondsReadsStaleAndItsPinIsFaded() {
        val alice = participant("person-2", "Alice Lee", base.minusSeconds(16), accuracy = 12.0)
        showStrip(listOf(alice to "Alice Lee"), displayedAt = base)

        ui.onNodeWithText(context.getString(R.string.group_activity_location_stale, formatDuration(16))).assertIsDisplayed()
        ui.onAllNodesWithText(context.getString(R.string.group_activity_location_recent, formatDuration(16))).assertCountEquals(0)
        // The same age drives map pin opacity, which Google Maps markers cannot
        // expose through Compose semantics.
        assertEquals(0.52f, groupMarkerAlpha("active", groupLocationAgeSeconds(alice.lastLocationAt, base)))
        assertEquals(1f, groupMarkerAlpha("active", groupLocationAgeSeconds(participant("p", "P", base.minusSeconds(14)).lastLocationAt, base)))
        assertEquals(0.52f, groupMarkerAlpha("stale", 0L))
    }

    @Test
    fun advancingDisplayClockExpiresAFreshFixWithoutIncomingUpdates() {
        val alice = participant("person-2", "Alice Lee", base.minusSeconds(4), accuracy = 12.0)
        val displayedAt = mutableStateOf(base)
        ui.setContent {
            MaterialTheme {
                GroupParticipantStrip(
                    attendees = attendees(listOf(alice to "Alice Lee")),
                    groupRun = runOf(alice),
                    displayedAt = displayedAt.value,
                    onSelect = {},
                    avatar = {},
                )
            }
        }
        ui.waitForIdle()
        ui.onNodeWithText(context.getString(R.string.group_activity_location_recent, formatDuration(4))).assertIsDisplayed()

        // Only the one-second display clock moves; the participant data is unchanged.
        // The fix is 4 seconds old, so the clock alone carries it past 15 seconds.
        ui.runOnUiThread { displayedAt.value = base.plusSeconds(10) }
        ui.waitForIdle()
        ui.onNodeWithText(context.getString(R.string.group_activity_location_recent, formatDuration(14))).assertIsDisplayed()
        ui.runOnUiThread { displayedAt.value = base.plusSeconds(12) }
        ui.waitForIdle()
        ui.onNodeWithText(context.getString(R.string.group_activity_location_stale, formatDuration(16))).assertIsDisplayed()
        ui.onAllNodesWithText(context.getString(R.string.group_activity_location_recent, formatDuration(16))).assertCountEquals(0)
        ui.onAllNodesWithText(context.getString(R.string.group_activity_location_accuracy, 0)).assertCountEquals(0)
        ui.onNodeWithText(context.getString(R.string.group_activity_location_accuracy, 12)).assertIsDisplayed()
    }

    @Test
    fun groupedStripUsesTheSharedDisplayClockAndNeverInventsAccuracy() {
        val alice = participant("person-2", "Alice Lee", base.minusSeconds(40), accuracy = null)
        val maya = participant("person-3", "Maya Rivera", null, status = "left")
        ui.setContent {
            val clock = rememberGroupLocationClock("live-fixture")
            MaterialTheme {
                GroupParticipantStrip(
                    attendees = attendees(listOf(alice to "Alice Lee", maya to "Maya Rivera")),
                    groupRun = runOf(alice, maya),
                    displayedAt = clock,
                    onSelect = {},
                    avatar = {},
                )
            }
        }

        ui.onAllNodesWithText(context.getString(R.string.group_activity_location_accuracy, 0)).assertCountEquals(0)
        ui.onNodeWithText(context.getString(R.string.group_activity_location_not_sharing)).assertIsDisplayed()
        ui.onAllNodesWithText(context.getString(R.string.group_activity_location_recent, formatDuration(40))).assertCountEquals(0)
    }

    private fun participant(
        userId: String,
        name: String,
        lastLocationAt: Instant?,
        accuracy: Double? = null,
        status: String = "active",
    ) = SharedLiveParticipant(
        id = "member-$userId",
        userId = userId,
        displayName = name,
        status = status,
        latitude = lastLocationAt?.let { 47.67 },
        longitude = lastLocationAt?.let { -122.12 },
        lastLocationAt = lastLocationAt?.toString(),
        accuracyMeters = accuracy,
    )

    private fun runOf(vararg participants: SharedLiveParticipant) =
        SharedLiveRun(id = "live-fixture", status = "active", currentUserId = "person-me", participants = participants.toList())

    private fun attendees(people: List<Pair<SharedLiveParticipant, String>>) = people.map {
        GroupActivityParticipant(GroupActivityPerson(it.first.userId, it.second))
    }

    private fun showStrip(people: List<Pair<SharedLiveParticipant, String>>, displayedAt: Instant) {
        val groupRun = runOf(*people.map { it.first }.toTypedArray())
        ui.setContent {
            MaterialTheme {
                GroupParticipantStrip(attendees = attendees(people), groupRun = groupRun, displayedAt = displayedAt, onSelect = {}, avatar = {})
            }
        }
    }
}
