package com.plainstride.outbound.feature.social

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.plainstride.outbound.core.designsystem.PlainstrideTheme
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.UninstallModules
import com.plainstride.outbound.feature.activity.ActivityViewModel_HiltModules
import org.junit.Before
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.time.ZonedDateTime

@UninstallModules(SocialViewModel_HiltModules.BindsModule::class, ActivityViewModel_HiltModules.BindsModule::class)
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class GroupImprovementsScreenTest {
    @get:Rule(order = 0) val hilt = HiltAndroidRule(this)
    @get:Rule(order = 1) val compose = createComposeRule()
    @Before fun inject() = hilt.inject()
    private fun label(id: Int) = InstrumentationRegistry.getInstrumentation().targetContext.getString(id)
    private val inviter = SocialPerson("fixture-inviter", "Fixture Inviter")
    private val applicant = SocialPerson("fixture-applicant", "Fixture Applicant")
    private val request = GroupJoinRequest("fixture-request", applicant, inviter, "2026-11-06T12:00:00Z")

    @Test fun ownerChangesInvitationApprovalAndApprovesRequest() {
        val group = mutableStateOf(GroupSummary("fixture-group", "Fixture Group", "active", role = "owner", trustPolicy = "community", joinPolicy = "request", joinRequests = listOf(request), pendingRequestCount = 1))
        var saved: Pair<String, Boolean>? = null
        var approved = false
        compose.setContent {
            PlainstrideTheme {
                GroupMembershipDialog(group.value, {}, { policy, required, complete -> saved = policy to required; complete(true) }, { _, decision, complete ->
                    approved = decision
                    group.value = group.value.copy(joinRequests = emptyList(), pendingRequestCount = 0)
                    complete(true)
                })
            }
        }
        compose.onNodeWithTag("group.membership.approval_required").performScrollTo().performClick()
        compose.onNodeWithTag("group.membership.save").performClick()
        compose.onNodeWithTag("group.membership.list").performScrollToNode(hasTestTag("group.request.approve.fixture-request"))
        compose.onNodeWithTag("group.request.approve.fixture-request").performClick()
        compose.onNodeWithText(label(R.string.group_membership_empty)).assertIsDisplayed()
        compose.runOnIdle { assertEquals("request" to false, saved); assertTrue(approved) }
    }

    @Test fun adminCanDeclineRequestWithoutChangingOwnerPolicy() {
        var declined = false
        val group = GroupSummary("fixture-group", "Fixture Group", "active", role = "admin", joinRequests = listOf(request), pendingRequestCount = 1)
        compose.setContent {
            PlainstrideTheme { GroupMembershipDialog(group, {}, { _, _, _ -> fail("Admin cannot save owner policies") }, { _, approve, complete -> declined = !approve; complete(true) }) }
        }
        compose.onNodeWithTag("group.membership.approval_required").assertDoesNotExist()
        compose.onNodeWithTag("group.membership.save").assertDoesNotExist()
        compose.onNodeWithTag("group.request.deny.fixture-request").performClick()
        compose.runOnIdle { assertTrue(declined) }
    }

    @Test fun acceptedInvitationShowsPendingMembershipAndWithdrawal() {
        var accepted = false
        var withdrew = false
        val invitation = GroupInvitationDto("fixture-invite", inviter, GroupInvitationGroup("fixture-group", "Fixture Group"), status = "awaiting_approval", approvalRequired = true)
        val group = GroupSummary("fixture-group", "Fixture Group", "active", invitationPreview = true, pendingInvitation = invitation)
        compose.setContent {
            PlainstrideTheme { GroupInvitationPreviewScreen(group, false, {}) { decision -> accepted = decision; withdrew = !decision } }
        }
        compose.onNodeWithText(label(R.string.group_membership_pending)).assertIsDisplayed()
        compose.onNodeWithText(label(R.string.social_accept)).assertDoesNotExist()
        compose.onNodeWithText(label(R.string.group_membership_withdraw)).performClick()
        compose.runOnIdle { assertTrue(withdrew); assertFalse(accepted) }
    }

    private val editableSeriesStart: String = java.time.Instant.now()
        .plus(java.time.Duration.ofDays(10))
        .truncatedTo(java.time.temporal.ChronoUnit.SECONDS)
        .toString()

    private fun editableSeriesEvent() = SocialEvent(
        id = "fixture-series-event",
        seriesId = "fixture-series",
        recurrence = EventRecurrence("Europe/Madrid", 1, listOf(3), null),
        name = "Existing recurring long run",
        startsAt = editableSeriesStart,
        activityType = "cycling",
        group = SocialGroup("fixture-group", "Fixture Group"),
    )

    @Test fun editingFollowingScopeTurnsOffRepetitionForRemainingSeries() {
        val submissions = mutableListOf<CreateEventBody>()
        compose.setContent {
            PlainstrideTheme {
                GroupActivityComposer({}, {}, {}, editableSeriesEvent()) { body, complete ->
                    submissions.add(body)
                    complete(true)
                }
            }
        }
        compose.onNodeWithTag("group.activity.title").performTextReplacement("Edited recurring long run")
        compose.onNodeWithText(label(R.string.group_plan_cycling)).performScrollTo().performClick()
        compose.onNodeWithText(label(R.string.group_plan_hiking)).performClick()
        compose.onNodeWithText(label(R.string.group_repeat_scope)).performScrollTo().assertIsDisplayed()
        compose.onNodeWithText(label(R.string.group_repeat_this)).performClick()
        compose.onNodeWithText(label(R.string.group_repeat_following)).performClick()
        compose.onNodeWithTag("group.activity.repeat").performScrollTo().assertIsOn().performClick()
        compose.onNodeWithTag("group.activity.repeat").assertIsOff()
        compose.onNodeWithTag("group.activity.save").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(1, submissions.size)
            val body = submissions.single()
            assertEquals("Edited recurring long run", body.title)
            assertEquals(editableSeriesStart, body.startsAt)
            assertEquals("hiking", body.activityType)
            assertEquals("following", body.scope)
            assertTrue(body.stopRepeating)
            assertNull(body.recurrence)
        }
    }

    @Test fun failedSaveRetainsFollowingScopeAndStoppedRepeatForRetry() {
        val submissions = mutableListOf<CreateEventBody>()
        compose.setContent {
            PlainstrideTheme {
                GroupActivityComposer({}, {}, {}, editableSeriesEvent()) { body, complete ->
                    submissions.add(body)
                    complete(submissions.size > 1)
                }
            }
        }
        compose.onNodeWithText(label(R.string.group_repeat_this)).performScrollTo().performClick()
        compose.onNodeWithText(label(R.string.group_repeat_following)).performClick()
        compose.onNodeWithTag("group.activity.repeat").performScrollTo().assertIsOn().performClick()
        compose.onNodeWithTag("group.activity.save").performScrollTo().performClick()
        compose.waitForIdle()
        compose.onNodeWithText(label(R.string.group_repeat_following)).assertIsDisplayed()
        compose.onNodeWithTag("group.activity.repeat").performScrollTo().assertIsOff()
        compose.onNodeWithTag("group.activity.save").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(2, submissions.size)
            assertEquals(submissions[0].idempotencyKey, submissions[1].idempotencyKey)
            submissions.forEach { body ->
                assertEquals("following", body.scope)
                assertTrue(body.stopRepeating)
                assertNull(body.recurrence)
            }
            assertEquals("Existing recurring long run", submissions[1].title)
            assertEquals(editableSeriesStart, submissions[1].startsAt)
            assertEquals("cycling", submissions[1].activityType)
        }
    }

    @Test fun weeklyComposerRetainsDraftAndCreationKeyAfterFailure() {
        val submissions = mutableListOf<CreateEventBody>()
        val firstWeekday = ZonedDateTime.now().plusDays(1).dayOfWeek.value
        val additionalDay = if (firstWeekday == 1) 2 else 1
        compose.setContent {
            PlainstrideTheme {
                GroupActivityComposer({}, {}, {}) { body, complete -> submissions.add(body); complete(false) }
            }
        }
        compose.onNodeWithTag("group.activity.title").performTextInput("Weekly fixture activity")
        compose.onNodeWithTag("group.activity.repeat").performScrollTo().performClick()
        compose.onNodeWithTag("group.activity.weekday.$additionalDay").performScrollTo().performClick()
        compose.onNodeWithTag("group.activity.save").performScrollTo().performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("group.activity.save").assertIsEnabled().performClick()
        compose.runOnIdle {
            assertEquals(2, submissions.size)
            assertEquals(submissions[0].idempotencyKey, submissions[1].idempotencyKey)
            assertEquals("Weekly fixture activity", submissions[1].title)
            assertEquals(listOf(firstWeekday, additionalDay).sorted(), submissions[1].recurrence?.weekdays)
            assertEquals(1, submissions[1].recurrence?.intervalWeeks)
        }
    }
}
