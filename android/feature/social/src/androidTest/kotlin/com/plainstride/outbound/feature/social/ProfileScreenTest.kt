package com.plainstride.outbound.feature.social

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertHasNoClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.plainstride.outbound.core.designsystem.PlainstrideTheme
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import dagger.hilt.android.testing.UninstallModules
import com.plainstride.outbound.feature.activity.ActivityViewModel_HiltModules
import org.junit.Before
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

// Screen fixtures do not create app ViewModels or their repository graphs.
@UninstallModules(SocialViewModel_HiltModules.BindsModule::class, ActivityViewModel_HiltModules.BindsModule::class)
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class ProfileScreenTest {
    @get:Rule(order = 0) val hilt = HiltAndroidRule(this)
    @get:Rule(order = 1) val compose = createComposeRule()

    @Before fun inject() = hilt.inject()

    private val runner = SocialPerson(id = "fixture-runner", displayName = "Test Runner")
    private fun label(id: Int) = InstrumentationRegistry.getInstrumentation().targetContext.getString(id)

    @Test fun connectBecomesPersistentSentOnNavigationProfile() = checkConnectToSent(useDialog = false)

    @Test fun connectBecomesPersistentSentOnQrDialogProfile() = checkConnectToSent(useDialog = true)

    // Exercise the production screen as its owner publishes the successful request state.
    // Both the navigation destination and QR destination use this same screen.
    private fun checkConnectToSent(useDialog: Boolean) {
        val person = mutableStateOf(runner)
        val visible = mutableStateOf(true)
        var requests = 0
        compose.setContent {
            PlainstrideTheme {
                if (visible.value) ProfileScreen(
                    person = person.value, posts = emptyList(), report = {}, close = {},
                    connect = {
                        requests++
                        person.value = runner.copy(relationship = "pending", connectionDirection = "outgoing", connectionId = "fixture-request")
                    },
                    accept = {}, remove = {}, useDialog = useDialog, openActivity = {},
                )
            }
        }
        compose.onNodeWithText(label(R.string.social_connect)).performClick()
        compose.onNodeWithText(label(R.string.social_profile_request_sent)).assertIsDisplayed().assertHasNoClickAction()
        compose.onNodeWithText(label(R.string.social_connect)).assertDoesNotExist()
        compose.onNodeWithText(label(R.string.social_accept)).assertDoesNotExist()
        compose.runOnIdle { assertEquals(1, requests); visible.value = false }
        compose.waitForIdle()
        compose.runOnIdle { visible.value = true }
        compose.onNodeWithText(label(R.string.social_profile_request_sent)).assertIsDisplayed().assertHasNoClickAction()
        compose.runOnIdle { assertEquals(1, requests) }
    }

    @Test fun incomingRequestOffersAcceptAndDeclineInsteadOfSent() {
        var accepted = 0
        var declined = 0
        show(runner.copy(relationship = "pending", connectionDirection = "incoming"), accept = { accepted++ }, remove = { declined++ })
        compose.onNodeWithText(label(R.string.social_profile_request_sent)).assertDoesNotExist()
        compose.onNodeWithText(label(R.string.social_connect)).assertDoesNotExist()
        compose.onNodeWithText(label(R.string.social_accept)).performClick()
        compose.onNodeWithText(label(R.string.social_decline)).performClick()
        compose.runOnIdle { assertEquals(1, accepted); assertEquals(1, declined) }
    }

    @Test fun connectedProfileRequiresConfirmationBeforeDisconnecting() {
        var removed = 0
        show(runner.copy(relationship = "accepted"), remove = { removed++ })
        compose.onNodeWithText(label(R.string.social_profile_request_sent)).assertDoesNotExist()
        compose.onNodeWithText(label(R.string.social_report_person)).assertIsDisplayed()
        compose.onNodeWithText(label(R.string.social_disconnect)).performClick()
        compose.runOnIdle { assertEquals(0, removed) }
        compose.onNodeWithText(label(R.string.social_remove_connection)).performClick()
        compose.runOnIdle { assertEquals(1, removed) }
    }

    @Test fun connectCannotBeTappedWhileProcessing() {
        show(runner, isProcessing = true)
        compose.onNodeWithText(label(R.string.social_connect)).assertIsDisplayed().assertIsNotEnabled()
        compose.onNodeWithText(label(R.string.social_profile_request_sent)).assertDoesNotExist()
    }

    private fun show(person: SocialPerson, isProcessing: Boolean = false, accept: () -> Unit = {}, remove: () -> Unit = {}) {
        compose.setContent {
            PlainstrideTheme {
                ProfileScreen(
                    person = person, posts = emptyList(), report = {}, close = {}, connect = {},
                    accept = accept, remove = remove, isProcessing = isProcessing,
                    useDialog = false, openActivity = {},
                )
            }
        }
    }
}
