package com.plainstride.outbound

import android.content.Intent
import android.net.Uri
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.compose.ui.test.*
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import com.plainstride.outbound.core.auth.*
import com.plainstride.outbound.core.database.*
import com.plainstride.outbound.core.network.PlainstrideJson
import com.plainstride.outbound.feature.social.*
import com.plainstride.outbound.feature.community.*
import com.plainstride.outbound.feature.safety.*
import com.plainstride.outbound.core.data.ActivityRepository
import com.plainstride.outbound.core.model.activity.SavedActivity
import com.plainstride.outbound.core.model.activity.ActivityType
import dagger.hilt.android.EntryPointAccessors
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.first
import androidx.lifecycle.ViewModelProvider
import okhttp3.mockwebserver.*
import org.junit.*
import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Real app callbacks, navigation graph, Room and HTTP; synthetic account in an isolated APK. */
class NavigationInteractionTest {
    @get:Rule val ui = createEmptyComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private lateinit var server: MockWebServer
    private var scenario: ActivityScenario<MainActivity>? = null
    private var launchIntent: Intent? = null
    private val requests = ConcurrentHashMap.newKeySet<String>()
    private val statuses = ConcurrentHashMap<String, Int>()
    private val responses = ConcurrentHashMap<String, String>()
    private var gate: CountDownLatch? = null
    private var gatedPath: String? = null
    private val person = SocialPerson("fixture-person", "Fixture Contact", username = "fixture_contact")
    private val post = SocialPost("fixture-post", person, FeedActivity("fixture-activity", "Fixture Morning Run", startedAt = "2026-10-30T08:00:00Z", distanceM = 5000.0, durationSecs = 1800))
    private val home get() = SocialHome(posts = listOf(post))

    private val dependencies get() = EntryPointAccessors.fromApplication(context.applicationContext, NavigationFixtureDependencies::class.java)

    @Before fun prepare() {
        ui.mainClock.autoAdvance = false
        check(context.packageName.endsWith(".navigationtest"))
        check(BuildConfig.API_BASE_URL == "http://127.0.0.1:18787/")
        responses["/v1/auth/me"] = """{"id":"fixture-self","displayName":"Fixture Self","onboardingCompleted":true,"onboardingStatus":"completed"}"""
        responses["/v1/social/home"] = PlainstrideJson.encodeToString(home)
        responses["/v1/social/connections"] = PlainstrideJson.encodeToString(ConnectionsResponse(listOf(ConnectionDto("fixture-connection", "accepted", "outgoing", SocialPerson("roster-person", "Roster Contact")))))
        responses["/v1/social/people/search"] = PlainstrideJson.encodeToString(PeopleResponse(listOf(person)))
        responses["/v1/social/users/fixture-person/profile"] = PlainstrideJson.encodeToString(ProfileResponse(person))
        responses["/v1/social/notifications"] = """{"notifications":[]}"""
        responses["/v1/social/groups"] = """{"groups":[]}"""
        responses["/v1/social/groups/invitations/inbox"] = """{"invitations":[]}"""
        responses["/v1/social/posts/fixture-post/photos"] = """{"photos":[]}"""
        responses["/v1/safety/live-shares/invited"] = """{"sessions":[]}"""
        server = MockWebServer().apply {
            dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val path = request.requestUrl!!.encodedPath
                    requests.add(path)
                    if (path == gatedPath) gate?.await(20, TimeUnit.SECONDS)
                    return (responses[request.path] ?: responses[path])?.let { MockResponse().setResponseCode(statuses[path] ?: 200).setHeader("Content-Type", "application/json").setBody(it) }
                        ?: MockResponse().setResponseCode(404).setHeader("Content-Type", "application/json").setBody("{}")
                }
            }
        }
        server.start(InetAddress.getByName("127.0.0.1"), 18787)
        context.getSharedPreferences("notification_permission", 0).edit().putBoolean("primer_shown", true).putBoolean("requested", true).commit()
        context.getSharedPreferences("motion_permission", 0).edit().putBoolean("requested", true).commit()
        runBlocking {
            dependencies.database().clearAllTables()
            dependencies.session().install(SessionCredentials("fixture-access", Long.MAX_VALUE, "fixture-refresh", Long.MAX_VALUE, SessionAccount("fixture-self", true, "completed")))
        }
    }
    @After fun finish() {
        gate?.countDown()
        try {
            // MainActivity.setIntent updates warm-link data; ActivityScenario filters lifecycle
            // callbacks by the original intent, so restore that filter before closing it.
            scenario?.onActivity { activity -> launchIntent?.let { activity.intent = Intent(it) } }
            scenario?.close()
        } finally {
            if (::server.isInitialized) server.shutdown()
        }
    }
    private fun launch(link: String? = null) {
        val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        if (link != null) intent.data = Uri.parse(link)
        launchIntent = Intent(intent)
        scenario = ActivityScenario.launch(intent)
    }
    private fun shown(text: String) {
        ui.waitUntil(20_000) { ui.mainClock.advanceTimeBy(500); ui.onAllNodesWithText(text, substring = false).fetchSemanticsNodes().isNotEmpty() }
    }
    private fun click(text: String) { shown(text); ui.onAllNodesWithText(text)[0].performClick() }
    private fun me() {
        ui.waitUntil(20_000) { ui.mainClock.advanceTimeBy(500); ui.onAllNodesWithContentDescription("Me").fetchSemanticsNodes().isNotEmpty() }
        ui.onNodeWithContentDescription("Me").performClick(); shown("Roster")
    }
    private fun back() { InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK); ui.mainClock.advanceTimeBy(1000); ui.waitForIdle() }

    @Test fun meConnectionsBackKeepsTabsResponsive() {
        launch(); me(); click("All"); shown("Connections")
        back(); shown("Roster")
        ui.onNodeWithContentDescription("Social").performClick(); shown("Feed")
        me(); click("All"); shown("Connections")
        click("Done"); shown("Roster")
    }

    @Test fun searchProfileUsesIdCacheThenNetworkAndReturnsToQuery() {
        launch(); me(); click("All"); shown("Connections")
        ui.onNode(hasSetTextAction()).performTextInput("fixture")
        shown("Fixture Contact")
        gatedPath = "/v1/social/users/fixture-person/profile"; gate = CountDownLatch(1)
        click("Fixture Contact")
        shown("Fixture Contact")
        ui.waitUntil(10_000) { requests.contains(gatedPath) }
        responses[gatedPath!!] = PlainstrideJson.encodeToString(ProfileResponse(person.copy(displayName = "Refreshed Contact")))
        gate!!.countDown(); shown("Refreshed Contact")
        ui.onNode(hasScrollAction() and SemanticsMatcher.keyIsDefined(SemanticsProperties.VerticalScrollAxisRange)).performScrollToNode(hasText("Fixture Morning Run"))
        click("Fixture Morning Run"); shown("Fixture Morning Run")
        scenario!!.recreate(); shown("Fixture Morning Run")
        back(); shown("Refreshed Contact")
        back(); shown("Connections"); ui.onNode(hasSetTextAction()).assertTextContains("fixture")
        back(); shown("Roster")
    }

    @Test fun notificationPostLoadsWithoutSocialAnchorAndRestoresAfterRecreation() {
        launch("plainstride://notification/post?id=fixture-post")
        shown("Fixture Morning Run")
        scenario!!.recreate(); shown("Fixture Morning Run")
        back()
        ui.onNodeWithContentDescription("Me").assertExists()
        me()
    }

    @Test fun unavailablePostHasRetryAndReturnsToRealCaller() {
        launch("plainstride://notification/post?id=missing-post")
        shown("Try again")
        click("Try again"); shown("Try again")
        back(); ui.onNodeWithContentDescription("Me").assertExists()
        me()
    }

    @Test fun connectionCodeLoadsIndependentlyThenBackReturnsToRoot() {
        responses["/v1/social/connection-links/abcd1234"] = PlainstrideJson.encodeToString(ConnectionLinkPreview(person, false))
        launch("https://plainstride.ai/connect/abcd1234")
        shown("Fixture Contact")
        Assert.assertTrue(requests.contains("/v1/social/connection-links/abcd1234"))
        scenario!!.recreate(); shown("Fixture Contact")
        back(); ui.onNodeWithContentDescription("Me").assertExists()
    }
    @Test fun eventShowsCacheBeforeHttpThenFreshDataAndBack() {
        val cached = SocialEvent("fixture-event", "Cached Event", "2026-11-10T08:00:00Z")
        runBlocking { dependencies.details().saveEvent("fixture-self", cached) }
        gatedPath = "/v1/social/activity-events/fixture-event"; gate = CountDownLatch(1)
        responses[gatedPath!!] = PlainstrideJson.encodeToString(cached.copy(name = "Fresh Event"))
        launch("plainstride://notification/event?id=fixture-event")
        shown("Cached Event")
        gate!!.countDown(); shown("Fresh Event")
        scenario!!.recreate(); shown("Fresh Event")
        back(); ui.onNodeWithContentDescription("Me").assertExists()
    }

    @Test fun uncachedGroupLinkResolvesOnceAndNestedEventBackRestoresGroup() {
        val event = SocialEvent("fixture-event", "Nested Event", "2026-11-10T08:00:00Z")
        val group = GroupSummary("fixture-group", "Fixture Group", "active", upcomingActivities = listOf(GroupActivitySummary(event.id, event.name, event.startsAt)))
        responses["/invite/group/fixture-token/consume"] = PlainstrideJson.encodeToString(group)
        responses["/v1/social/groups/fixture-group"] = PlainstrideJson.encodeToString(group)
        responses["/v1/social/activity-events/fixture-event"] = PlainstrideJson.encodeToString(event)
        launch("https://plainstride.ai/invite/group/fixture-token")
        shown("Fixture Group")
        ui.onNode(hasScrollAction() and SemanticsMatcher.keyIsDefined(SemanticsProperties.VerticalScrollAxisRange)).performScrollToNode(hasText("Nested Event"))
        click("Nested Event"); shown("Nested Event")
        scenario!!.recreate(); shown("Nested Event")
        back(); shown("Fixture Group")
        back(); ui.onNodeWithContentDescription("Me").assertExists()
    }

    @Test fun cachedGroupRefreshesByIdWithoutInvokingInviteResolver() {
        val group = GroupSummary("fixture-group", "Cached Group", "active")
        runBlocking { dependencies.details().saveGroup("fixture-self", group, null) }
        gatedPath = "/v1/social/groups/fixture-group"; gate = CountDownLatch(1)
        responses[gatedPath!!] = PlainstrideJson.encodeToString(group.copy(name = "Fresh Group"))
        launch("plainstride://notification/group?id=fixture-group")
        shown("Cached Group"); gate!!.countDown(); shown("Fresh Group")
        Assert.assertFalse(requests.any { it.startsWith("/invite/group/") })
        back(); ui.onNodeWithContentDescription("Me").assertExists()
    }

    @Test fun cachedLocalActivityByServerIdReturnsDirectlyToRoot() {
        val time = "2026-10-30T08:00:00Z"
        runBlocking {
            dependencies.activities().save(SavedActivity("fixture-local", "fixture-self", serverActivityId="fixture-server", type=ActivityType.running,
                title="Local Fixture Run", createdAt=time, startedAt=time, endedAt="2026-10-30T08:30:00Z", durationSecs=1800, distanceM=5000.0, localUpdatedAt=time))
        }
        gatedPath="/v1/activities"; gate=CountDownLatch(1)
        val remote=com.plainstride.outbound.core.network.RemoteActivityDto("fixture-server",clientData=kotlinx.serialization.json.JsonObject(emptyMap()),activityType="running",title="Updated Local Fixture Run",startedAt=time,endedAt="2026-10-30T08:30:00Z",durationSecs=1800,distanceM=5000.0,createdAt=time,updatedAt="2026-10-30T09:00:00Z")
        responses[gatedPath!!]=PlainstrideJson.encodeToString(com.plainstride.outbound.core.network.ActivityListResponse(listOf(remote),false))
        launch("plainstride://notification/activity?id=fixture-server")
        shown("Local Fixture Run"); gate!!.countDown(); shown("Updated Local Fixture Run")
        runBlocking {
            Assert.assertEquals("fixture-local", dependencies.activities().activity("fixture-self","fixture-server")?.id)
            Assert.assertEquals(1, dependencies.database().activityDao().activeCount("fixture-self"))
        }
        scenario!!.recreate(); shown("Updated Local Fixture Run")
        back(); ui.onNodeWithContentDescription("Me").assertExists()
    }

    @Test fun routeLibraryDetailUsesIdCacheThenNetworkAndReturnsToLibrary() {
        val route = CommunityRoute("fixture-route", "Cached Fixture Route", activityType="running", distanceM=5000.0, routeShape="loop", owner=RouteOwner("fixture-self", "Fixture Self"))
        runBlocking { dependencies.routes().cacheDetail("fixture-self", route) }
        responses["/v1/routes/mine"] = PlainstrideJson.encodeToString(RoutesResponse(listOf(route)))
        responses["/v1/routes/search"] = PlainstrideJson.encodeToString(RoutesResponse(listOf(route)))
        gatedPath = "/v1/routes/fixture-route"; gate=CountDownLatch(1)
        responses[gatedPath!!] = PlainstrideJson.encodeToString(route.copy(name="Fresh Fixture Route"))
        launch(); me()
        ui.onNode(hasScrollAction() and SemanticsMatcher.keyIsDefined(SemanticsProperties.VerticalScrollAxisRange)).performScrollToNode(hasText("My Routes")); click("My Routes")
        click("Cached Fixture Route"); shown("Cached Fixture Route")
        ui.waitUntil(10_000) { requests.contains(gatedPath) }
        gate!!.countDown(); shown("Fresh Fixture Route")
        scenario!!.recreate(); shown("Fresh Fixture Route")
        back(); shown("Routes")
        back(); shown("Roster")
    }

    @Test fun informationalNotificationLoadsFromIdAndReturnsToInbox() {
        responses["/v1/social/notifications"] = PlainstrideJson.encodeToString(InboxResponse(listOf(InboxNotification("fixture-notice", "announcement", message="Fixture announcement", createdAt="2026-10-30T08:00:00Z"))))
        launch("plainstride://notification/inbox")
        click("Fixture announcement"); shown("Fixture announcement")
        scenario!!.recreate(); shown("Fixture announcement")
        ui.onNodeWithContentDescription("Back").performClick(); shown("Notification Center")
        back(); ui.onNodeWithContentDescription("Me").assertExists()
    }

    @Test fun liveAndGroupRunDetailsResolveWithoutSafetySettingsAnchor() {
        responses["/v1/live/group-runs/fixture-live-group"] = PlainstrideJson.encodeToString(GroupRun("fixture-live-group", "ended", title="Fixture Live Group", creatorUserId="fixture-self", currentUserId="fixture-self", startedAt="2026-10-30T08:00:00Z", expiresAt="2026-10-31T08:00:00Z"))
        launch("plainstride://notification/group_run?id=fixture-live-group")
        shown("Fixture Live Group")
        ui.onNodeWithText("Trusted contacts").assertDoesNotExist()
        scenario!!.recreate(); shown("Fixture Live Group")
        back(); ui.onNodeWithContentDescription("Me").assertExists()
    }

    @Test fun socialSnapshotsRemainIsolatedByAccountAndGroupInvitation() {
        runBlocking {
            val event=SocialEvent("same-id", "Account Event", "2026-11-10T08:00:00Z")
            val group=GroupSummary("same-id", "Invitation Group", "active")
            dependencies.details().saveEvent("fixture-self", event)
            dependencies.details().saveGroup("fixture-self", group, "invitation-one")
            Assert.assertEquals(event, dependencies.details().event("fixture-self", "same-id"))
            Assert.assertNull(dependencies.details().event("other-account", "same-id"))
            Assert.assertNull(dependencies.details().group("fixture-self", "same-id", null))
            Assert.assertEquals(group, dependencies.details().group("fixture-self", "same-id", "invitation-one"))
        }
    }

    @Test fun invitationCanOpenByIdWithOnlyCachedData() {
        val invitation = SocialInvitation("fixture-invitation", "event", "Cached Invitation", person, "fixture-event")
        runBlocking { dependencies.details().saveInvitation("fixture-self", invitation) }
        responses.remove("/v1/social/home")
        launch("plainstride://notification/invitation?id=fixture-invitation")
        shown("Cached Invitation")
        scenario!!.recreate(); shown("Cached Invitation")
        back(); ui.onNodeWithContentDescription("Me").assertExists()
    }

    @Test fun uncachedActivityFetchesByServerIdWithoutOpeningHistory() {
        val time="2026-10-30T08:00:00Z"
        val remote=com.plainstride.outbound.core.network.RemoteActivityDto("remote-fixture", clientData=kotlinx.serialization.json.JsonObject(emptyMap()), activityType="running", title="Network Fixture Run", startedAt=time, endedAt="2026-10-30T08:30:00Z", durationSecs=1800, distanceM=5000.0, createdAt=time, updatedAt=time)
        responses["/v1/activities"] = PlainstrideJson.encodeToString(com.plainstride.outbound.core.network.ActivityListResponse(listOf(remote),false))
        launch("plainstride://notification/activity?id=remote-fixture")
        shown("Network Fixture Run")
        back(); ui.onNodeWithContentDescription("Me").assertExists()
        runBlocking { Assert.assertNotNull(dependencies.activities().activity("fixture-self","remote-fixture")) }
    }

    @Test fun liveFollowerLoadsByIdAndBackReturnsDirectlyToRoot() {
        responses["/v1/safety/live-shares/invited/fixture-live"] = """{"id":"fixture-live","status":"ended","runner":{"id":"fixture-runner","displayName":"Fixture Runner"},"startedAt":"2026-10-30T08:00:00Z","expiresAt":"2026-10-31T08:00:00Z"}"""
        launch("plainstride://notification/live?id=fixture-live")
        shown("Cheer Fixture Runner on")
        scenario!!.recreate(); shown("Cheer Fixture Runner on")
        back(); ui.onNodeWithContentDescription("Me").assertExists()
    }

    @Test fun cachedPostRemainsReadableWhenNetworkIsUnavailable() {
        runBlocking { dependencies.details().savePost("fixture-self", post) }
        responses.remove("/v1/social/home")
        launch("plainstride://notification/post?id=fixture-post")
        shown("Fixture Morning Run")
        scenario!!.recreate(); shown("Fixture Morning Run")
        back(); ui.onNodeWithContentDescription("Me").assertExists()
    }

    @Test fun deniedEventDiscardsCachedContentAndKeepsBackAndRetry() {
        val event=SocialEvent("fixture-event", "Revoked Event", "2026-11-10T08:00:00Z")
        runBlocking { dependencies.details().saveEvent("fixture-self",event) }
        gatedPath="/v1/social/activity-events/fixture-event"; gate=CountDownLatch(1)
        responses[gatedPath!!]="{}"; statuses[gatedPath!!]=403
        launch("plainstride://notification/event?id=fixture-event")
        shown("Revoked Event"); gate!!.countDown(); shown("Try again")
        ui.onNodeWithText("Revoked Event").assertDoesNotExist()
        back(); ui.onNodeWithContentDescription("Me").assertExists()
    }

    @Test fun importedRouteRestoresByIdAndDeletionReturnsToItsLibrary() {
        val route=CommunityRoute("import:fixture", "Imported Fixture Route", activityType="running",distanceM=5000.0,routeShape="loop",owner=RouteOwner("fixture-self","Fixture Self"))
        runBlocking { dependencies.routes().saveImport("fixture-self",route) }
        launch(); me()
        ui.onNode(hasScrollAction() and SemanticsMatcher.keyIsDefined(SemanticsProperties.VerticalScrollAxisRange)).performScrollToNode(hasText("My Routes"))
        click("My Routes"); click("Imported Fixture Route"); shown("Preview Route")
        scenario!!.recreate(); shown("Imported Fixture Route")
        click("Delete Imported Route"); shown("Delete imported route?")
        ui.onAllNodesWithText("Delete Imported Route")[1].performClick()
        shown("Routes")
        ui.waitUntil(10_000){ui.mainClock.advanceTimeBy(500);ui.onAllNodesWithText("Imported Fixture Route").fetchSemanticsNodes().isEmpty()}
        ui.onNodeWithText("Imported Fixture Route").assertDoesNotExist()
        runBlocking { Assert.assertNull(dependencies.routes().cachedDetail("fixture-self",route.id)) }
        back(); shown("Roster")
    }

    @Test fun warmEventNotificationPreservesMeAsItsActualCaller() {
        responses["/v1/social/activity-events/fixture-event"]=PlainstrideJson.encodeToString(SocialEvent("fixture-event","Warm Event","2026-11-10T08:00:00Z"))
        launch(); me()
        context.startActivity(Intent(context,MainActivity::class.java).setData(Uri.parse("plainstride://notification/event?id=fixture-event")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        shown("Warm Event"); back(); shown("Roster")
        ui.onNodeWithContentDescription("Settings").assertExists()
    }

    @Test fun groupRunLeaveUsesTheViewedIdAndReturnsToCaller() {
        val group=GroupRun("fixture-leave-group","active",title="Leave Fixture Group",creatorUserId="fixture-self",currentUserId="fixture-self",startedAt="2026-10-30T08:00:00Z",expiresAt="2026-10-31T08:00:00Z",participants=listOf(GroupRunParticipant("fixture-participant","fixture-self","Fixture Self","active")))
        val path="/v1/live/group-runs/fixture-leave-group"
        responses[path]=PlainstrideJson.encodeToString(group)
        responses["$path/participants/me/leave"]=PlainstrideJson.encodeToString(group.copy(status="ended"))
        launch("plainstride://notification/group_run?id=fixture-leave-group")
        shown("Leave Fixture Group")
        val label=context.getString(com.plainstride.outbound.feature.safety.R.string.safety_group_leave)
        click(label)
        ui.waitUntil(10_000){ui.mainClock.advanceTimeBy(500);ui.onAllNodesWithContentDescription("Me").fetchSemanticsNodes().isNotEmpty()}
        Assert.assertTrue(requests.contains("$path/participants/me/leave"))
    }

    @Test fun socialQuickRefreshPublishesConnectionsToMeFromTheSameCache() {
        launch(); me()
        val added=SocialPerson("new-person","New Connection")
        responses["/v1/social/connections"]=PlainstrideJson.encodeToString(ConnectionsResponse(listOf(
            ConnectionDto("fixture-connection","accepted","outgoing",SocialPerson("roster-person","Roster Contact")),
            ConnectionDto("new-connection","accepted","outgoing",added),
        )))
        lateinit var social: SocialViewModel
        scenario!!.onActivity { social=ViewModelProvider(it)["shared_social_fixture-self",SocialViewModel::class.java] }
        runBlocking { social.refreshActiveNow() }
        shown("New")
        runBlocking {
            val cached=dependencies.social().observeHome("fixture-self",context.resources.configuration.locales[0].toLanguageTag()).first() as CachedSocialHome.Available
            Assert.assertTrue(cached.value.connections.any{it.id==added.id && it.relationship=="accepted"})
            Assert.assertTrue(cached.value.posts.any{it.id==post.id})
        }
        ui.onNodeWithContentDescription("Social").performClick(); click("People"); shown("New Connection")
        me(); shown("New")
    }

    @Test fun foregroundPushRefreshesAcceptanceBadgeAndConnectionWhileStayingOnMe() {
        launch(); me()
        responses["/v1/social/notifications"]=PlainstrideJson.encodeToString(InboxResponse(listOf(
            InboxNotification("accepted-notice","connectionAccepted","new-connection","Connection accepted",createdAt="2026-10-31T08:00:00Z"),
        )))
        responses["/v1/social/connections"]=PlainstrideJson.encodeToString(ConnectionsResponse(listOf(
            ConnectionDto("new-connection","accepted","outgoing",SocialPerson("new-person","New Connection")),
        )))
        com.plainstride.outbound.notifications.InboxUpdates.changes.tryEmit(Unit)
        shown("New")
        ui.waitUntil(10_000){ui.mainClock.advanceTimeBy(500); ui.onAllNodes(hasContentDescription("Notification Center") and hasText("1")).fetchSemanticsNodes().isNotEmpty()}
        ui.onNode(hasContentDescription("Notification Center") and hasText("1")).assertExists()
        responses["/v1/social/notifications/read-all"]="{}"
        ui.onNodeWithContentDescription("Notification Center").performClick(); shown("Connection accepted")
        ui.waitUntil(10_000){requests.contains("/v1/social/notifications/read-all")}
        responses["/v1/social/notifications"]=PlainstrideJson.encodeToString(InboxResponse(listOf(
            InboxNotification("accepted-notice","connectionAccepted","new-connection","Connection accepted",readAt="2026-10-31T09:00:00Z",createdAt="2026-10-31T08:00:00Z"),
        )))
        back(); shown("New")
        ui.onNodeWithContentDescription("Notification Center").assert(hasText("1").not())
    }

    @Test fun foregroundPollRecoversAcceptanceBadgeWithoutPushCallback() {
        launch(); me()
        responses["/v1/social/notifications"]=PlainstrideJson.encodeToString(InboxResponse(listOf(
            InboxNotification("accepted-notice","connectionAccepted",message="Connection accepted",createdAt="2026-10-31T08:00:00Z"),
        )))
        ui.mainClock.advanceTimeBy(31_000)
        ui.waitUntil(10_000){ui.mainClock.advanceTimeBy(500);ui.onAllNodes(hasContentDescription("Notification Center") and hasText("1")).fetchSemanticsNodes().isNotEmpty()}
        // The acceptance counts because it is unread, even though it is informational.
        ui.onNode(hasContentDescription("Notification Center") and hasText("1")).assertExists()
    }

    @Test fun pagedConnectionsPublishToMeAndRemainWhenAnotherConsumerRefreshes() {
        val locale=context.resources.configuration.locales[0].toLanguageTag()
        responses["/v1/social/connections"]=PlainstrideJson.encodeToString(ConnectionsResponse(listOf(
            ConnectionDto("fixture-connection","accepted","outgoing",SocialPerson("roster-person","Roster Contact")),
        ),"next"))
        responses["/v1/social/connections?cursor=next"]=PlainstrideJson.encodeToString(ConnectionsResponse(listOf(
            ConnectionDto("new-connection","accepted","outgoing",SocialPerson("new-person","New Connection")),
        )))
        launch(); me()
        runBlocking { dependencies.social().loadConnections("fixture-self",locale,"next").getOrThrow() }
        shown("New")
        runBlocking {
            dependencies.social().refreshConnections("fixture-self",locale,0).getOrThrow()
            val cached=dependencies.social().observeHome("fixture-self",locale).first() as CachedSocialHome.Available
            Assert.assertEquals(setOf("roster-person","new-person"),cached.value.connections.map{it.id}.toSet())
            Assert.assertNull(cached.value.connectionNextCursor)
            Assert.assertTrue(cached.value.posts.any{it.id==post.id})
        }
    }

    @Test fun meConnectionAvatarOpensProfileAndBackReturnsDirectlyToMe() {
        val contact=SocialPerson("roster-person","Roster Contact",relationshipDetails=SocialRelationship("fixture-connection","accepted","outgoing"))
        responses["/v1/social/users/roster-person/profile"]=PlainstrideJson.encodeToString(ProfileResponse(contact))
        gatedPath="/v1/social/users/roster-person/profile"; gate=CountDownLatch(1)
        launch(); me(); click("Roster"); shown("Profile"); shown("Roster Contact")
        ui.waitUntil(10_000){requests.contains(gatedPath)}
        gate!!.countDown()
        scenario!!.recreate(); shown("Profile")
        back(); shown("Roster"); ui.onNodeWithContentDescription("Settings").assertExists()
        click("Roster"); shown("Profile")
        ui.onNodeWithContentDescription("Back").performClick(); shown("Roster")
        ui.onNodeWithContentDescription("Settings").assertExists()
    }

}
