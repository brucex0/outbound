package com.plainstride.outbound.feature.social

import android.graphics.BitmapFactory
import android.content.Intent
import android.text.format.DateUtils
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.border
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.DirectionsRun
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.serialization.json.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import com.plainstride.outbound.core.designsystem.*
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.core.model.activity.ActivityTrackPoint
import com.plainstride.outbound.core.model.activity.ActivityType
import com.plainstride.outbound.core.model.activity.SavedActivity
import com.plainstride.outbound.feature.activity.ActivityExport
import com.plainstride.outbound.feature.activity.ActivityViewModel
import com.plainstride.outbound.feature.activity.R as ActivityR

@Composable fun SocialRoute(accountId: String, localeTag: String, targetType:String?=null,targetId:String?=null,inboxCount:Int=0,unitSystem:MeasurementUnitSystem=MeasurementUnitSystem.metric,onConditions:()->Unit={},onCommunity:()->Unit={},onNotifications:()->Unit={},onActivity:(String)->Unit={},onMyInvite:()->Unit={},onConnectionLinkConsumed:()->Unit={},onGroupInviteConsumed:()->Unit={},onRoutesTabSelected:()->Unit={},communityRoutesContent: @Composable () -> Unit = {}, modifier: Modifier = Modifier, viewModel: SocialViewModel = hiltViewModel()) {
    var selectedTab by rememberSaveable { mutableStateOf(SocialFeatureTab.FEED) }
    var hasSelectedSocialTab by rememberSaveable { mutableStateOf(false) }
    var createGroup by rememberSaveable { mutableStateOf(false) };var inviteGroup by remember { mutableStateOf<GroupSummary?>(null) };var inviteEvent by remember { mutableStateOf<SocialEvent?>(null) };var groupActivity by remember { mutableStateOf<GroupSummary?>(null) };var connectionsOpen by rememberSaveable { mutableStateOf(false) }
    var scannerOpen by rememberSaveable { mutableStateOf(false) }
    var scannerFeedback by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    val resources = LocalResources.current
    val activityViewModel: ActivityViewModel = hiltViewModel()
    LaunchedEffect(accountId, localeTag) { viewModel.start(accountId, localeTag) }
    val state by viewModel.state.collectAsStateWithLifecycle()
    LaunchedEffect(state.loading, state.home.connections.size) {
        if (!state.loading && !hasSelectedSocialTab) {
            selectedTab = if (state.home.connections.none { it.relationship in setOf("accepted", "connected") }) SocialFeatureTab.PEOPLE else SocialFeatureTab.FEED
        }
    }
    LaunchedEffect(viewModel) {
        viewModel.connectionEffects.collect { effect ->
            when (effect) {
                is ConnectionEffect.ShareInvitation -> {
                    val invitation = resources.getString(R.string.social_invitation_share_message, effect.url)
                    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, invitation)
                    }, null))
                }
                is ConnectionEffect.Feedback -> {
                    val message = resources.getString(connectionFeedbackResource(effect.value))
                    if (scannerOpen && !effect.closeScanner) scannerFeedback = message
                    else Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
                    if (effect.closeScanner) scannerOpen = false
                }
            }
        }
    }
    LaunchedEffect(scannerFeedback) {
        if (scannerFeedback == null) return@LaunchedEffect
        kotlinx.coroutines.delay(2_000)
        scannerFeedback = null
    }
    LaunchedEffect(targetType,targetId,state.loading){
        if (!state.loading && targetType == "connections") connectionsOpen = true
        else if (!state.loading && targetType == "connection_link" && !targetId.isNullOrBlank()) {
            viewModel.openConnectionCodeProfile(targetId)
            onConnectionLinkConsumed()
        }
        else if(!state.loading&&targetType=="group_invite"&&targetId!=null){viewModel.consumeGroupInvite(targetId);onGroupInviteConsumed()}
        else if(!state.loading&&targetType!=null&&targetId!=null)viewModel.openTarget(targetType,targetId)
    }
    val selectedActivityPost = state.selectedActivityPost?.let { selected -> state.home.posts.firstOrNull { it.id == selected.id } ?: selected }
    if (selectedActivityPost == null) {
        SocialScreen(state, selectedTab, { tab ->
            hasSelectedSocialTab = true
            selectedTab = tab
            if (tab == SocialFeatureTab.ROUTES) onRoutesTabSelected()
            viewModel.trackSocialTabSelected(tab.analyticsValue)
        }, inboxCount, unitSystem, viewModel::refresh, viewModel::search, viewModel::openProfile, { connectionsOpen = true }, viewModel::openGroup, viewModel::openComments, viewModel::openActivityDetail, viewModel::openTarget, onConditions, onCommunity, onNotifications, viewModel::toggleCheer, { group ->
            if (group.trustPolicy == "trusted_private") viewModel.openGroup(group) else viewModel.joinGroup(group)
        }, viewModel::loadMore, viewModel::report, viewModel::block, viewModel::deletePost, { person -> person.connectionId?.let(viewModel::acceptConnection) }, { person -> person.connectionId?.let(viewModel::removeConnection) }, {createGroup=true}, communityRoutesContent, modifier, viewModel = viewModel)
    } else {
        BackHandler { viewModel.closeActivityDetail() }
        SocialActivityDetail(
            post = selectedActivityPost,
            unitSystem = unitSystem,
            photos = state.activityDetailPhotos,
            photosLoading = state.activityDetailPhotosLoading,
            photoBytes = state.activityDetailPhotoBytes,
            onBack = viewModel::closeActivityDetail,
            openProfile = viewModel::openProfile,
            cheer = { viewModel.toggleCheer(selectedActivityPost) },
            comments = { viewModel.openComments(selectedActivityPost) },
            trackSplitsViewed = viewModel::trackActivitySplitsViewed,
            createShareCard = { post -> post.activity?.toSavedActivity(post)?.let { activityViewModel.shareCard(it, unitSystem, "social_feed") } },
            trackShareAction = activityViewModel::trackSocialShareAction,
            loadPhotoContent = viewModel::loadActivityPhotoContent,
            trackPhotoPreview = viewModel::trackActivityPhotoPreviewed,
            modifier = modifier,
        )
    }
    if (connectionsOpen) ConnectionsDialog(
        state = state,
        search = viewModel::search,
        openProfile = viewModel::openProfile,
        reviewInvitation = { invitation -> viewModel.openTarget("invitation", invitation.id) },
        scanQr = { scannerFeedback = null; scannerOpen = true },
        showQr = { connectionsOpen = false; onMyInvite() },
        inviteByLink = viewModel::inviteByLink,
        acceptRequest = { person -> person.connectionId?.let(viewModel::acceptConnection) },
        declineRequest = { person -> person.connectionId?.let(viewModel::removeConnection) },
        close = { connectionsOpen = false },
    )
    if (scannerOpen) ConnectionQrScannerScreen(
        isProcessing = state.connectionProfileLoading,
        serverMessage = scannerFeedback,
        onOpened = viewModel::scannerOpened,
        onPayload = { payload ->
            connectionCodeFromPayload(payload)?.let { code ->
                scannerOpen = false
                viewModel.openConnectionCodeProfile(code)
            }
        },
        onClose = { scannerOpen = false },
    )
    if (state.connectionProfileLoading) ConnectionProfileLoadingScreen()
    state.selectedProfile?.let { person ->
        ProfileScreen(
            person = person,
            posts = state.home.posts.filter { it.author.id == person.id },
            close = viewModel::closeProfile,
            connect = { if (state.connectionProfileCode != null) viewModel.connectFromConnectionCode() else viewModel.connect(person) },
            accept = { person.connectionId?.let(viewModel::acceptConnection) },
            remove = { person.connectionId?.let(viewModel::removeConnection) },
            isCurrentUser = state.connectionProfileIsSelf,
            isProcessing = state.connectionRequestLoading,
            openActivity = { post ->
                viewModel.closeProfile()
                viewModel.openActivityDetail(post)
            },
        )
    }
    state.selectedGroupDetail?.let { group -> GroupDetailScreen(group, viewModel::closeGroup, { recipient, preset -> viewModel.cheerGroup(group, recipient, preset) }, { mode,target,next->viewModel.setGroupFocus(group,mode,target,next) }, { viewModel.setGroupArchived(group,group.lifecycle!="archived") }, {inviteGroup=group}, {name->viewModel.renameGroup(group,name)}, {target,skipped->viewModel.setGroupCommitment(group,target,skipped)}, {muted->viewModel.muteGroup(group,muted)}, {viewModel.leaveGroup(group)}, {userId->viewModel.removeGroupMember(group,userId)}, { groupActivity = group }) }
    state.selectedEvent?.let{event->SocialEventDialog(event,{viewModel.setEventRsvp(event,!event.joined);viewModel.closeTarget()},{inviteEvent=event},viewModel::closeTarget)}
    if(createGroup)GroupCreateScreen(state.home.connections.filter{it.relationship in setOf("accepted","connected")},{createGroup=false}){template,name,people->viewModel.createGroup(template,name,people,java.util.TimeZone.getDefault().id);createGroup=false}
    inviteGroup?.let{group->PersonPickerDialog(stringResource(R.string.social_invite),state.home.connections,{inviteGroup=null}){person->viewModel.inviteToGroup(group,listOf(person),java.util.UUID.randomUUID().toString());inviteGroup=null}}
    inviteEvent?.let{event->PersonPickerDialog(stringResource(R.string.social_invite),state.home.connections,{inviteEvent=null}){person->viewModel.inviteToEvent(event,person);inviteEvent=null}}
    groupActivity?.let { group -> GroupActivityComposer({ groupActivity = null }) { title, location -> viewModel.createGroupActivity(group, title, location); groupActivity = null } }
    state.selectedInvitation?.let{invitation->AlertDialog(onDismissRequest=viewModel::closeTarget,title={Text(invitation.title)},confirmButton={TextButton({viewModel.respondToInvitation(invitation,true)}){Text(stringResource(R.string.social_accept))}},dismissButton={TextButton({viewModel.respondToInvitation(invitation,false)}){Text(stringResource(R.string.social_decline))}})}
    state.selectedPost?.let { CommentsDialog(it, state.comments, viewModel::addComment, viewModel::deleteComment, viewModel::closeComments) }
}

private enum class SocialFeatureTab(val analyticsValue: String, val label: Int) {
    FEED("feed", R.string.social_tab_feed),
    PEOPLE("people", R.string.social_tab_people),
    GROUPS("groups", R.string.social_tab_groups),
    ROUTES("routes", R.string.social_tab_routes),
}

private fun connectionFeedbackResource(value: ConnectionFeedback) = when (value) {
    ConnectionFeedback.REQUESTED -> R.string.social_connection_request_sent
    ConnectionFeedback.ALREADY_PENDING -> R.string.social_connection_request_already_sent
    ConnectionFeedback.INCOMING_PENDING -> R.string.social_connection_request_incoming
    ConnectionFeedback.ALREADY_CONNECTED -> R.string.social_already_connected
    ConnectionFeedback.SELF -> R.string.social_self_qr_code
    ConnectionFeedback.UPDATED -> R.string.social_connection_request_updated
    ConnectionFeedback.REQUEST_FAILED -> R.string.social_connection_request_failed
    ConnectionFeedback.PROFILE_LOAD_FAILED -> R.string.social_qr_load_failure
    ConnectionFeedback.INVITE_LINK_FAILED -> R.string.social_invite_link_failed
}
@Composable private fun ActionDialog(title:String,action:String,onAction:()->Unit,onClose:()->Unit)=AlertDialog(onDismissRequest=onClose,title={Text(title)},confirmButton={TextButton(onAction){Text(action)}},dismissButton={TextButton(onClose){Text(stringResource(R.string.social_done))}})

@Composable private fun ConnectionProfileLoadingScreen() = Dialog(onDismissRequest = {}, properties = DialogProperties(usePlatformDefaultWidth = false)) {
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                CircularProgressIndicator()
                Text(stringResource(R.string.social_checking_qr_code), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable private fun SocialScreen(state: SocialUiState, selectedTab: SocialFeatureTab, selectTab: (SocialFeatureTab) -> Unit, inboxCount: Int, unitSystem: MeasurementUnitSystem, refresh: () -> Unit, search: (String) -> Unit, openProfile: (SocialPerson) -> Unit, openConnections: () -> Unit, openGroup: (GroupSummary) -> Unit, comments: (SocialPost) -> Unit, openActivity:(SocialPost)->Unit, openTarget:(String,String)->Unit, conditions:()->Unit, community:()->Unit, notifications:()->Unit, cheer: (SocialPost) -> Unit, group: (GroupSummary) -> Unit, loadMore: () -> Unit, report: (SocialPost, String) -> Unit, block: (SocialPost) -> Unit, deletePost: (SocialPost) -> Unit, acceptRequest: (SocialPerson) -> Unit, declineRequest: (SocialPerson) -> Unit, createGroup:()->Unit, communityRoutesContent: @Composable () -> Unit, modifier: Modifier, viewModel: SocialViewModel) {
    var safetyPost by remember { mutableStateOf<SocialPost?>(null) }
    var blockConfirmationPost by remember { mutableStateOf<SocialPost?>(null) }
    var deletionConfirmationPost by remember { mutableStateOf<SocialPost?>(null) }
    val context = LocalContext.current
    val deletionPreferences = remember { context.getSharedPreferences("social_preferences", android.content.Context.MODE_PRIVATE) }
    var skipDeletionConfirmation by rememberSaveable { mutableStateOf(deletionPreferences.getBoolean("skip_post_deletion_confirmation", false)) }
    var skipFutureDeletionConfirmations by rememberSaveable { mutableStateOf(false) }
    var trackedActiveNowExposure by rememberSaveable { mutableStateOf(false) }
    var trackedUpcomingExposure by rememberSaveable { mutableStateOf(false) }
    var trackedFirstFeedCard by rememberSaveable { mutableStateOf(false) }
    val acceptedConnections = state.home.connections.filter { it.relationship in setOf("accepted", "connected") }.sortedWith(compareByDescending<SocialPerson> { it.isActive }.thenBy { it.displayName.substringBefore(' ').lowercase() })
    val activeConnections = acceptedConnections.filter(SocialPerson::isActive)
    val incomingRequests = state.home.connections.filter { it.relationship == "pending" && it.connectionDirection == "incoming" }
    val groupInvitations = state.home.invitations.filter { it.kind == "group" }
    val groupAttention = groupInvitations.size + state.home.groups.sumOf { it.unreadNoticeCount }
    LaunchedEffect(selectedTab, activeConnections.size) {
        if (selectedTab == SocialFeatureTab.FEED && activeConnections.isNotEmpty() && !trackedActiveNowExposure) {
            trackedActiveNowExposure = true
            viewModel.trackActiveNowExposed(activeConnections.size)
        }
    }
    LaunchedEffect(selectedTab, state.home.upcomingRuns.size) {
        if (selectedTab == SocialFeatureTab.FEED && state.home.upcomingRuns.isNotEmpty() && !trackedUpcomingExposure) {
            trackedUpcomingExposure = true
            viewModel.trackUpcomingExposed(state.home.upcomingRuns)
        }
    }
    LaunchedEffect(selectedTab, state.home.posts.firstOrNull()?.id) {
        if (selectedTab == SocialFeatureTab.FEED && state.home.posts.isNotEmpty() && !trackedFirstFeedCard) {
            trackedFirstFeedCard = true
            viewModel.trackFirstFeedCardVisible(state.home.posts.first())
        }
    }
    Column(modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 2.dp), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
            SocialIconButton(conditions, stringResource(R.string.social_conditions)) { Icon(Icons.Outlined.WbSunny, null) }
            SocialIconButton(community, stringResource(R.string.social_community)) { Icon(Icons.Outlined.People, null) }
            SocialIconButton(notifications, stringResource(R.string.social_notifications)) { BadgedBox({ if (maxOf(inboxCount, groupAttention) > 0) Badge(containerColor = MaterialTheme.colorScheme.error, contentColor = MaterialTheme.colorScheme.onError) { Text(maxOf(inboxCount, groupAttention).coerceAtMost(99).toString()) } }) { Icon(Icons.Outlined.Notifications, null) } }
        }
        Row(
            Modifier.fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface)
                .padding(horizontal = 6.dp, vertical = 3.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            SocialFeatureTab.entries.forEach { tab ->
                val count = when (tab) {
                    SocialFeatureTab.PEOPLE -> incomingRequests.size
                    SocialFeatureTab.GROUPS -> groupAttention
                    else -> 0
                }
                TextButton(
                    onClick = { selectTab(tab) },
                    modifier = Modifier.weight(1f).heightIn(min = 44.dp),
                    contentPadding = PaddingValues(horizontal = 2.dp, vertical = 2.dp),
                ) {
                    BadgedBox({ if (count > 0) Badge { Text(if (count > 9) "9+" else count.toString()) } }) {
                        Text(
                            stringResource(tab.label),
                            style = if (selectedTab == tab) MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold) else MaterialTheme.typography.labelLarge,
                            color = if (selectedTab == tab) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                        )
                    }
                }
            }
        }
        if (state.offline) AssistChip({}, { Text(stringResource(R.string.social_offline)) }, Modifier.padding(horizontal = 16.dp), leadingIcon = { Icon(Icons.Outlined.CloudOff, null) })
        when (selectedTab) {
            SocialFeatureTab.FEED -> PullToRefreshBox(
                isRefreshing = state.refreshing,
                onRefresh = refresh,
                modifier = Modifier.weight(1f),
            ) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (activeConnections.isNotEmpty()) item {
                    Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        SectionHeader(stringResource(R.string.social_active_now_title))
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp), contentPadding = PaddingValues(horizontal = 1.dp)) {
                            items(activeConnections, key = SocialPerson::id) { person ->
                                val activePersonLabel = stringResource(R.string.social_active_now_person, person.displayName)
                                Column(
                                    Modifier.width(58.dp).clickable { viewModel.trackActiveNowSelected("profile"); openProfile(person) }
                                        .semantics { contentDescription = activePersonLabel },
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                    verticalArrangement = Arrangement.spacedBy(3.dp),
                                ) {
                                    Box {
                                        SocialAvatar(person, 40.dp)
                                        Icon(Icons.Outlined.RadioButtonChecked, null, Modifier.align(Alignment.BottomEnd).size(15.dp), tint = MaterialTheme.colorScheme.primary)
                                    }
                                    Text(person.displayName.substringBefore(' '), maxLines = 1, style = MaterialTheme.typography.labelSmall)
                                }
                            }
                        }
                    }
                }
                if (state.home.upcomingRuns.isNotEmpty()) {
                    item { Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) { SectionHeader(stringResource(R.string.social_upcoming), action = stringResource(R.string.social_discover), onAction = community) } }
                    item {
                        LazyRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), contentPadding = PaddingValues(horizontal = 1.dp)) {
                            items(prioritizeUpcomingEvents(state.home.upcomingRuns).take(3), key = SocialEvent::id) { event -> UpcomingEventCard(event) { viewModel.trackUpcomingSelected("card"); openTarget("event", event.id) } }
                        }
                    }
                }
                item { Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) { SectionHeader(stringResource(R.string.social_activity_feed)) } }
                items(state.home.posts, key = SocialPost::id) { post -> PostCard(post, unitSystem, viewModel::loadFeedPhotoThumbnail, { openProfile(post.author) }, { if (post.activity != null) openActivity(post) }, { cheer(post) }, { comments(post) }, { openProfile(it) }, { if (post.isCurrentUser) { if (skipDeletionConfirmation) deletePost(post) else deletionConfirmationPost = post } else safetyPost = post }) }
                if (!state.loading && state.home.posts.isEmpty()) item {
                    Box(Modifier.padding(horizontal = 16.dp)) { SocialCard {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.AutoMirrored.Outlined.DirectionsRun, null, Modifier.size(28.dp), tint = MaterialTheme.colorScheme.primary)
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text(stringResource(R.string.social_feed_empty_title), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)
                                Text(stringResource(R.string.social_feed_empty), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    } }
                }
                if (state.loading) item { Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
                if (state.home.nextCursor != null) item(key = "feed-page-${state.home.nextCursor}") {
                    when {
                        state.feedLoadFailed -> TextButton(loadMore, Modifier.fillMaxWidth().padding(horizontal = 16.dp)) { Text(stringResource(R.string.social_feed_load_more_failed)) }
                        state.feedLoading -> Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp) }
                        else -> LaunchedEffect(state.home.nextCursor) { loadMore() }
                    }
                }
            }
            }
            SocialFeatureTab.PEOPLE -> LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                item { OutlinedTextField(state.search, search, Modifier.fillMaxWidth(), singleLine = true, label = { Text(stringResource(R.string.social_search_people)) }, leadingIcon = { Icon(Icons.Outlined.Search, null) }) }
                if (state.searchResults.isNotEmpty()) { item { SectionHeader(stringResource(R.string.social_search_people)) }; items(state.searchResults, key = SocialPerson::id) { person -> PersonRow(person) { openProfile(person) } } }
                if (incomingRequests.isNotEmpty()) { item { SectionHeader(stringResource(R.string.social_requests)) }; items(incomingRequests, key = SocialPerson::id) { person -> RequesterCard(person, { openProfile(person) }, { acceptRequest(person) }, { declineRequest(person) }) } }
                item { SectionHeader(stringResource(R.string.social_connections), action = stringResource(R.string.social_all), onAction = openConnections) }
                if (acceptedConnections.isEmpty()) item { EmptyCard(stringResource(R.string.social_connections_empty), Icons.Outlined.PersonAdd) }
                items(acceptedConnections, key = SocialPerson::id) { person -> PersonRow(person) { openProfile(person) } }
                item { OutlinedButton(openConnections, Modifier.fillMaxWidth()) { Text(stringResource(R.string.social_all)) } }
            }
            SocialFeatureTab.GROUPS -> LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (groupInvitations.isNotEmpty()) { item { SectionHeader(stringResource(R.string.social_invite)) }; items(groupInvitations, key = SocialInvitation::id) { InvitationCard(it) { invitation -> openTarget("invitation", invitation.id) } } }
                item { SectionHeader(stringResource(R.string.social_groups), action = stringResource(R.string.social_group_create), onAction = createGroup) }
                if (state.home.groups.isEmpty() && !state.loading) item { CompanionCard(onClick = createGroup) { Text(stringResource(R.string.social_group_empty), fontWeight = FontWeight.SemiBold); Spacer(Modifier.height(10.dp)); Text(stringResource(R.string.social_group_create), fontWeight = FontWeight.Bold) } }
                items(state.home.groups, key = GroupSummary::id) { item -> GroupCard(item, groupDisplayName(item, state.home.groups)) { group(item) } }
                if (state.loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            }
            SocialFeatureTab.ROUTES -> Box(Modifier.weight(1f)) { communityRoutesContent() }
        }
    }
    safetyPost?.takeUnless(SocialPost::isCurrentUser)?.let { post -> var reason by remember { mutableStateOf(ReportReason.OTHER) }; AlertDialog(onDismissRequest = { safetyPost = null }, title = { Text(stringResource(R.string.social_safety_title)) }, text = { Column { Text(stringResource(R.string.social_safety_body)); ReportReason.entries.forEach { option -> Row(verticalAlignment=Alignment.CenterVertically){RadioButton(reason==option,{reason=option});Text(reportReasonLabel(option))} } } }, confirmButton = { TextButton({ report(post, reason.wireValue); safetyPost = null }) { Text(stringResource(R.string.social_report)) } }, dismissButton = { TextButton({ blockConfirmationPost = post; safetyPost = null }) { Text(stringResource(R.string.social_block)) } }) }
    blockConfirmationPost?.let { post -> AlertDialog(onDismissRequest = { blockConfirmationPost = null }, title = { Text(stringResource(R.string.social_block_confirmation_title)) }, text = { Text(stringResource(R.string.social_block_confirmation_message)) }, confirmButton = { TextButton({ block(post); blockConfirmationPost = null }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text(stringResource(R.string.social_block)) } }, dismissButton = { TextButton({ blockConfirmationPost = null }) { Text(stringResource(R.string.social_cancel)) } }) }
    deletionConfirmationPost?.let { post -> AlertDialog(onDismissRequest = { deletionConfirmationPost = null; skipFutureDeletionConfirmations = false }, title = { Text(stringResource(R.string.social_delete_post_confirmation_title)) }, text = { Column { Text(stringResource(R.string.social_delete_post_confirmation_message)); Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(skipFutureDeletionConfirmations, { skipFutureDeletionConfirmations = it }); Text(stringResource(R.string.social_dont_ask_again)) } } }, confirmButton = { TextButton({ if (skipFutureDeletionConfirmations) { skipDeletionConfirmation = true; deletionPreferences.edit().putBoolean("skip_post_deletion_confirmation", true).apply() }; deletePost(post); deletionConfirmationPost = null }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text(stringResource(R.string.social_delete_post)) } }, dismissButton = { TextButton({ deletionConfirmationPost = null; skipFutureDeletionConfirmations = false }) { Text(stringResource(R.string.social_cancel)) } }) }
}

@Composable private fun SectionHeader(text: String, action: String? = null, onAction: () -> Unit = {}) = Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) { Text(text.uppercase(), Modifier.weight(1f), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.onSurfaceVariant); action?.let { TextButton(onAction) { Text(it, fontWeight = FontWeight.SemiBold) } } }
@Composable private fun SocialCard(onClick: (() -> Unit)? = null, containerColor: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.surface, content: @Composable ColumnScope.() -> Unit) { val shape = RoundedCornerShape(18.dp); if (onClick == null) Card(Modifier.fillMaxWidth(), shape = shape, colors = CardDefaults.cardColors(containerColor = containerColor), elevation = CardDefaults.cardElevation(2.dp)) { Column(Modifier.padding(16.dp), content = content) } else Card(onClick, Modifier.fillMaxWidth(), shape = shape, colors = CardDefaults.cardColors(containerColor = containerColor), elevation = CardDefaults.cardElevation(2.dp)) { Column(Modifier.padding(16.dp), content = content) } }
@Composable private fun CompanionCard(onClick: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    val theme = LocalPlainstrideThemeColors.current
    Card(
        onClick,
        Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = androidx.compose.ui.graphics.Color.Transparent),
        elevation = CardDefaults.cardElevation(2.dp),
    ) {
        CompositionLocalProvider(LocalContentColor provides theme.heroForeground) {
            Column(
                Modifier.fillMaxWidth().background(Brush.linearGradient(theme.heroGradient)).padding(22.dp),
                content = content,
            )
        }
    }
}
@Composable private fun EmptyCard(text: String, icon: androidx.compose.ui.graphics.vector.ImageVector) = SocialCard { Row(verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, Modifier.size(28.dp), tint = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(12.dp)); Text(text, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
@Composable private fun ConnectionsPlaceholder() = SocialCard { Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) { repeat(4) { Column(horizontalAlignment = Alignment.CenterHorizontally) { Surface(Modifier.size(40.dp), shape = CircleShape, color = MaterialTheme.colorScheme.primaryContainer) {}; Spacer(Modifier.height(6.dp)); LinearProgressIndicator(Modifier.width(48.dp)) } } } }
@Composable private fun PersonPreview(person: SocialPerson, click: () -> Unit) = TextButton(click, contentPadding = PaddingValues(horizontal = 3.dp)) { Column(Modifier.width(64.dp),horizontalAlignment = Alignment.CenterHorizontally) { Box { SocialAvatar(person, 40.dp); if (person.isActive) Surface(Modifier.size(12.dp).align(Alignment.BottomEnd), shape = CircleShape, color = androidx.compose.ui.graphics.Color(0xFF34C759), border = androidx.compose.foundation.BorderStroke(2.dp, MaterialTheme.colorScheme.surface)) {} }; Spacer(Modifier.height(6.dp)); Text(person.displayName.substringBefore(' '), Modifier.fillMaxWidth(), maxLines = 1, textAlign=androidx.compose.ui.text.style.TextAlign.Center, style = MaterialTheme.typography.labelSmall) } }

/** Shared Connections element used by both Social and Me. */
@Composable
fun SocialConnectionsPreview(
    connections: List<SocialPerson>,
    loading: Boolean = false,
    onOpenAll: () -> Unit,
    onOpenProfile: (SocialPerson) -> Unit = { onOpenAll() },
) = when {
    loading -> ConnectionsPlaceholder()
    connections.isEmpty() -> EmptyCard(stringResource(R.string.social_connections_empty), Icons.Outlined.PersonAdd)
    else -> SocialCard(onClick = onOpenAll) {
        LazyRow(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            items(connections.take(8), key = SocialPerson::id) { person ->
                PersonPreview(person) { onOpenProfile(person) }
            }
        }
    }
}
@Composable private fun SocialIconButton(onClick: () -> Unit, label: String, content: @Composable () -> Unit) = IconButton(onClick, Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).semantics { contentDescription = label }) { Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primary.copy(alpha = .10f)) { Box(Modifier.size(36.dp), contentAlignment = Alignment.Center) { content() } } }
@Composable private fun PersonRow(person: SocialPerson, click: () -> Unit) = TextButton(click, Modifier.fillMaxWidth()) { SocialAvatar(person); Spacer(Modifier.width(12.dp)); Column(Modifier.weight(1f), horizontalAlignment = Alignment.Start) { Text(person.displayName); person.username?.let { Text("@$it", style = MaterialTheme.typography.bodySmall) } } }
@Composable private fun RequesterCard(person: SocialPerson, openProfile: () -> Unit, accept: () -> Unit, decline: () -> Unit) = SocialCard(onClick = openProfile) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        SocialAvatar(person)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(person.displayName, fontWeight = FontWeight.SemiBold)
            person.username?.let { Text("@$it", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        }
        SocialIconButton(accept, stringResource(R.string.social_accept)) {
            Icon(Icons.Outlined.Check, null)
        }
        SocialIconButton(decline, stringResource(R.string.social_decline)) {
            Icon(Icons.Outlined.Close, null, tint = MaterialTheme.colorScheme.error)
        }
    }
}
@Composable
private fun ConnectionsDialog(
    state: SocialUiState,
    search: (String) -> Unit,
    openProfile: (SocialPerson) -> Unit,
    reviewInvitation: (SocialInvitation) -> Unit,
    scanQr: () -> Unit,
    showQr: () -> Unit,
    inviteByLink: () -> Unit,
    acceptRequest: (SocialPerson) -> Unit,
    declineRequest: (SocialPerson) -> Unit,
    close: () -> Unit,
) = Dialog(onDismissRequest = close) {
    var addMenuExpanded by remember { mutableStateOf(false) }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.social_connections), Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Box {
                    IconButton({ addMenuExpanded = true }, Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp)) {
                        Icon(Icons.Outlined.Add, stringResource(R.string.social_add_connection))
                    }
                    DropdownMenu(addMenuExpanded, { addMenuExpanded = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.social_scan_qr_code)) },
                            leadingIcon = { Icon(Icons.Outlined.QrCodeScanner, null) },
                            onClick = { addMenuExpanded = false; scanQr() },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.social_show_my_qr_code)) },
                            leadingIcon = { Icon(Icons.Outlined.QrCode, null) },
                            onClick = { addMenuExpanded = false; showQr() },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.social_invite_by_link)) },
                            leadingIcon = { Icon(Icons.Outlined.Share, null) },
                            onClick = { addMenuExpanded = false; inviteByLink() },
                        )
                    }
                }
                TextButton(close) { Text(stringResource(R.string.social_done)) }
            }
            OutlinedTextField(state.search, search, Modifier.fillMaxWidth(), singleLine = true, label = { Text(stringResource(R.string.social_search_people)) }, leadingIcon = { Icon(Icons.Outlined.Search, null) })
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (state.searchResults.isNotEmpty()) { item { SectionHeader(stringResource(R.string.social_search_people)) }; items(state.searchResults, key = SocialPerson::id) { PersonRow(it) { openProfile(it) } } }
                val incoming = state.home.connections.filter { it.relationship == "pending" && it.connectionDirection == "incoming" }
                if (incoming.isNotEmpty()) { item { SectionHeader(stringResource(R.string.social_requests)) }; items(incoming, key = SocialPerson::id) { person -> RequesterCard(person, { openProfile(person) }, { acceptRequest(person) }, { declineRequest(person) }) } }
                if (state.home.invitations.isNotEmpty()) { item { SectionHeader(stringResource(R.string.social_invite)) }; items(state.home.invitations, key = SocialInvitation::id) { invitation -> InvitationCard(invitation, reviewInvitation) } }
                val accepted = state.home.connections.filter { it.relationship in setOf("accepted", "connected") }
                if (accepted.isNotEmpty()) { item { SectionHeader(stringResource(R.string.social_connections)) }; items(accepted, key = SocialPerson::id) { PersonRow(it) { openProfile(it) } } }
            }
        }
    }
}
@Composable private fun InvitationCard(invitation: SocialInvitation, review:(SocialInvitation)->Unit) = SocialCard { Text(invitation.title, fontWeight = FontWeight.SemiBold); Text(stringResource(R.string.social_invited_by, invitation.sender.displayName), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant); Button({review(invitation)}, Modifier.padding(top = 8.dp)) { Text(stringResource(R.string.social_review)) } }
private fun prioritizeUpcomingEvents(events: List<SocialEvent>): List<SocialEvent> = events.sortedWith(
    compareBy<SocialEvent> {
        when {
            it.source?.kind == "directInvitation" && !it.joined -> 0
            runCatching { java.time.OffsetDateTime.parse(it.startsAt).toInstant() }.getOrNull()
                ?.isBefore(java.time.Instant.now().plusSeconds(72 * 60 * 60)) == true -> 1
            else -> 2
        }
    }.thenBy { it.startsAt },
)

@Composable
private fun UpcomingEventCard(event: SocialEvent, open: () -> Unit) {
    val startsAt = runCatching { java.time.OffsetDateTime.parse(event.startsAt).toInstant().toEpochMilli() }.getOrNull()
    Card(
        onClick = open,
        modifier = Modifier.width(226.dp).heightIn(min = 112.dp),
        shape = RoundedCornerShape(15.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                startsAt?.let { DateUtils.formatDateTime(LocalContext.current, it, DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_ABBREV_MONTH or DateUtils.FORMAT_SHOW_WEEKDAY or DateUtils.FORMAT_SHOW_TIME) }.orEmpty(),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary,
                maxLines = 1,
            )
            Text(event.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, maxLines = 1)
            Text(
                event.locationName?.takeIf(String::isNotBlank) ?: stringResource(R.string.social_upcoming_meetup),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
            Text(stringResource(R.string.social_upcoming_attendees, event.attendeeCount), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
private fun groupDisplayName(group: GroupSummary, all: List<GroupSummary>): String {
    val normalized = group.name.trim().lowercase()
    val duplicates = all.count { it.name.trim().lowercase() == normalized }
    return if (duplicates > 1 && !group.city.isNullOrBlank()) "${group.name} · ${group.city}" else group.name
}
@Composable private fun GroupCard(group: GroupSummary, displayName: String, membership: () -> Unit) = SocialCard { Row(verticalAlignment = Alignment.CenterVertically) { Icon(Icons.Outlined.Flag, null, tint = MaterialTheme.colorScheme.primary); Spacer(Modifier.width(12.dp)); Column(Modifier.weight(1f)) { Text(displayName, fontWeight = FontWeight.SemiBold); Text(stringResource(R.string.social_members, group.memberCount), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }; TextButton(membership) { Text(if (group.trustPolicy == "trusted_private") stringResource(R.string.social_open) else stringResource(if (group.role != null) R.string.social_leave else R.string.social_join)) } } }
@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun PostCard(post: SocialPost, unitSystem: MeasurementUnitSystem, loadPhotoThumbnail: suspend (String) -> ByteArray?, profile: () -> Unit, openActivity:()->Unit, cheer: () -> Unit, comments:()->Unit, openProfile: (SocialPerson) -> Unit, safety: () -> Unit) {
    var cheerersOpen by rememberSaveable(post.id) { mutableStateOf(false) }
    Card(
        Modifier
            .fillMaxWidth()
            .clickable(
                enabled = post.activity != null,
                role = androidx.compose.ui.semantics.Role.Button,
                onClick = openActivity,
            ),
        shape = RoundedCornerShape(0.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        elevation = CardDefaults.cardElevation(0.dp),
    ) {
        val cheerLabel = stringResource(if (post.viewerHasCheered) R.string.social_remove_cheer else R.string.social_add_cheer)
        val commentsLabel = stringResource(R.string.social_comments)
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 8.dp, top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(profile, Modifier.weight(1f), contentPadding = PaddingValues(0.dp)) {
                    SocialAvatar(post.author, 36.dp)
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.Start) {
                        Text(post.author.displayName, fontWeight = FontWeight.SemiBold)
                        post.activityTimestamp?.let { RelativeActivityTime(it) }
                    }
                }
                IconButton(safety) { Icon(Icons.Outlined.MoreVert, stringResource(R.string.social_more)) }
            }
            post.activity?.let { activity ->
                Text(activity.title, Modifier.padding(horizontal = 16.dp), fontWeight = FontWeight.SemiBold)
                Box(Modifier.fillMaxWidth().aspectRatio(1f)) {
                    SocialRoutePreview(
                        activity = activity,
                        loadPhotoThumbnail = loadPhotoThumbnail,
                    )
                    Surface(
                        Modifier.align(Alignment.BottomCenter).fillMaxWidth(),
                        color = MaterialTheme.colorScheme.surface.copy(alpha = .88f),
                    ) {
                        Row(Modifier.padding(horizontal = 12.dp, vertical = 10.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                            ActivityStat(formatDistance(activity.distanceM, unitSystem), stringResource(R.string.social_distance))
                            ActivityStat(formatDuration(activity.durationSecs), stringResource(R.string.social_time))
                            ActivityStat(formatPace(activity.averagePaceSecsPerKm, unitSystem), stringResource(R.string.social_pace))
                        }
                    }
                    if (activity.recognitions.isNotEmpty()) {
                        Surface(Modifier.align(Alignment.TopStart).padding(10.dp), shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surface.copy(alpha = .92f)) {
                            Row(Modifier.padding(horizontal = 9.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Outlined.EmojiEvents, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(16.dp))
                                Text(badgeLabel(activity.recognitions.first().badgeId), style = MaterialTheme.typography.labelSmall, maxLines = 1)
                                if (activity.recognitions.size > 1) Text("+${activity.recognitions.size - 1}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                    if (activity.totalPhotoCount > 0) {
                        Surface(Modifier.align(Alignment.TopEnd).padding(10.dp), shape = CircleShape, color = MaterialTheme.colorScheme.scrim.copy(alpha = .60f)) {
                            Text(stringResource(R.string.social_feed_photo_count, activity.totalPhotoCount), Modifier.padding(horizontal = 10.dp, vertical = 7.dp), color = androidx.compose.ui.graphics.Color.White, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
            post.caption?.takeIf { it.isNotEmpty() }?.let { Text(it, Modifier.padding(horizontal = 16.dp), style = MaterialTheme.typography.bodyMedium) }
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Surface(
                    Modifier.heightIn(min = 40.dp).clip(CircleShape).clickable(onClick = cheer)
                        .semantics { contentDescription = "$cheerLabel, ${post.cheerCount}" },
                    shape = CircleShape,
                    color = (if (post.viewerHasCheered) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.tertiary).copy(alpha = .08f),
                ) {
                    Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(if (post.viewerHasCheered) Icons.Outlined.Favorite else Icons.Outlined.FavoriteBorder, null, tint = if (post.viewerHasCheered) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.tertiary)
                    }
                }
                if (post.cheerCount > 0) SocialCheerAvatarsButton(post) { cheerersOpen = true }
                Surface(
                    Modifier.heightIn(min = 40.dp).clip(CircleShape).clickable(onClick = comments)
                        .semantics { contentDescription = "$commentsLabel, ${post.commentCount}" },
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.tertiary.copy(alpha = .08f),
                ) {
                    Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.ChatBubbleOutline, null, tint = MaterialTheme.colorScheme.tertiary)
                        Spacer(Modifier.width(6.dp))
                        Text(post.commentCount.toString(), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.tertiary)
                    }
                }
            }
        }
    }
    if (cheerersOpen) {
        ModalBottomSheet(onDismissRequest = { cheerersOpen = false }) {
            Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = 16.dp)) {
                Text(stringResource(ActivityR.string.activity_social_cheer_count), Modifier.padding(horizontal = 24.dp, vertical = 8.dp), style = MaterialTheme.typography.titleLarge)
                if (post.cheers.isEmpty()) {
                    Text(stringResource(ActivityR.string.activity_social_cheers_empty), Modifier.fillMaxWidth().padding(24.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    LazyColumn(Modifier.heightIn(max = 520.dp)) {
                        items(post.cheers, key = SocialPerson::id) { person ->
                            Row(Modifier.fillMaxWidth().clickable { cheerersOpen = false; openProfile(person) }.heightIn(min = 56.dp).padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                SocialAvatar(person)
                                Column(Modifier.weight(1f)) {
                                    Text(person.displayName, fontWeight = FontWeight.SemiBold)
                                    person.username?.takeIf(String::isNotBlank)?.let { Text("@$it", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                                }
                                Icon(Icons.Outlined.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
    }
    }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SocialActivityDetail(
    post: SocialPost,
    unitSystem: MeasurementUnitSystem,
    photos: List<ActivityPhoto>,
    photosLoading: Boolean,
    photoBytes: Map<String, ByteArray>,
    onBack: () -> Unit,
    openProfile: (SocialPerson) -> Unit,
    cheer: () -> Unit,
    comments: () -> Unit,
    trackSplitsViewed: (Int) -> Unit,
    createShareCard: (SocialPost) -> ActivityExport?,
    trackShareAction: (String) -> Unit,
    loadPhotoContent: (String) -> Unit,
    trackPhotoPreview: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val activity = post.activity ?: return
    val route = remember(activity.route) { activity.route.routeCoordinates() }
    val splits = remember(route, activity.durationSecs, unitSystem) { computeSocialSplits(route, activity.durationSecs, unitSystem) }
    var showSplits by rememberSaveable(post.id) { mutableStateOf(false) }
    var selectedPhotoIndex by rememberSaveable(post.id) {
        mutableIntStateOf(photos.indexOfFirst { it.latitude != null && it.longitude != null })
    }
    var lightboxPhotoIndex by rememberSaveable(post.id) { mutableIntStateOf(-1) }
    var cheerersOpen by rememberSaveable(post.id) { mutableStateOf(false) }
    var shareExport by remember { mutableStateOf<ActivityExport?>(null) }
    val context = LocalContext.current
    val markers = remember(photos, selectedPhotoIndex) {
        photos.mapIndexedNotNull { index, photo ->
            val latitude = photo.latitude ?: return@mapIndexedNotNull null
            val longitude = photo.longitude ?: return@mapIndexedNotNull null
            MapRouteMarker(
                id = photo.id,
                coordinate = MapCoordinate(latitude, longitude),
                title = activity.title,
                selected = index == selectedPhotoIndex,
            )
        }
    }
    LaunchedEffect(photos) {
        if (selectedPhotoIndex < 0) selectedPhotoIndex = photos.indexOfFirst { it.latitude != null && it.longitude != null }
    }
    var sheetLevel by rememberSaveable(post.id) { mutableStateOf(SocialActivitySheetLevel.Split) }
    val density = androidx.compose.ui.platform.LocalDensity.current
    val sheetScope = rememberCoroutineScope()
    val cheerLabel = stringResource(if (post.viewerHasCheered) R.string.social_remove_cheer else R.string.social_add_cheer)
    val commentLabel = stringResource(R.string.social_comments)
    val sheetLabel = stringResource(if (sheetLevel == SocialActivitySheetLevel.Expanded) ActivityR.string.activity_sheet_collapse else ActivityR.string.activity_sheet_expand)
    BoxWithConstraints(modifier.fillMaxSize()) {
        val collapsedHeight = 132.dp
        val splitHeight = maxHeight * .48f
        val expandedHeight = (maxHeight - 56.dp).coerceAtLeast(splitHeight)
        val targetHeight = when (sheetLevel) {
            SocialActivitySheetLevel.Collapsed -> collapsedHeight
            SocialActivitySheetLevel.Split -> splitHeight
            SocialActivitySheetLevel.Expanded -> expandedHeight
        }
        val collapsedHeightPx = with(density) { collapsedHeight.toPx() }
        val expandedHeightPx = with(density) { expandedHeight.toPx() }
        val splitHeightPx = with(density) { splitHeight.toPx() }
        val heightForLevelPx = { level: SocialActivitySheetLevel ->
            when (level) {
                SocialActivitySheetLevel.Collapsed -> collapsedHeightPx
                SocialActivitySheetLevel.Split -> splitHeightPx
                SocialActivitySheetLevel.Expanded -> expandedHeightPx
            }
        }
        val sheetHeightAnimation = remember(maxHeight, density, post.id) { Animatable(splitHeightPx) }
        var dragHeightPx by remember(post.id) { mutableFloatStateOf(Float.NaN) }
        LaunchedEffect(targetHeight, maxHeight) {
            if (dragHeightPx.isNaN()) {
                sheetHeightAnimation.animateTo(
                    with(density) { targetHeight.toPx() },
                    animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMediumLow),
                )
            }
        }
        val currentSheetHeightPx = if (dragHeightPx.isNaN()) sheetHeightAnimation.value else dragHeightPx
        val sheetHeight = with(density) { currentSheetHeightPx.toDp().coerceIn(collapsedHeight, expandedHeight) }

        if (route.size > 1) {
            PlainstrideRouteMap(
                points = route,
                modifier = Modifier.fillMaxSize(),
                showEndpointMarkers = true,
                markers = markers,
                onMarkerClick = { markerId ->
                    val index = photos.indexOfFirst { it.id == markerId }
                    if (index >= 0) {
                        selectedPhotoIndex = index
                        lightboxPhotoIndex = index
                        trackPhotoPreview()
                        loadPhotoContent(photos[index].id)
                    }
                },
                bottomContentPadding = sheetHeight,
                fitRoutePadding = 64.dp,
            )
        } else {
            Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceVariant), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Outlined.Route, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(stringResource(ActivityR.string.activity_map_no_route), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        TopAppBar(
            title = { Text(activity.title, maxLines = 1) },
            navigationIcon = { IconButton(onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.social_back)) } },
            actions = {
                if (post.isCurrentUser) IconButton(onClick = {
                    shareExport = createShareCard(post)
                    if (shareExport == null) Toast.makeText(context, context.getString(ActivityR.string.activity_failed), Toast.LENGTH_SHORT).show()
                }) {
                    Icon(Icons.Outlined.Share, stringResource(ActivityR.string.activity_share))
                }
            },
            modifier = Modifier.align(Alignment.TopCenter),
        )
        Surface(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(sheetHeight),
            shape = RoundedCornerShape(topStart = if (sheetLevel == SocialActivitySheetLevel.Expanded) 0.dp else 22.dp, topEnd = if (sheetLevel == SocialActivitySheetLevel.Expanded) 0.dp else 22.dp),
            color = MaterialTheme.colorScheme.surface,
            shadowElevation = 16.dp,
        ) {
            LazyColumn(
                Modifier.fillMaxSize(),
                userScrollEnabled = sheetLevel == SocialActivitySheetLevel.Expanded,
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                stickyHeader {
                    Box(
                        Modifier.fillMaxWidth().height(32.dp)
                            .background(MaterialTheme.colorScheme.surface)
                            .pointerInput(collapsedHeightPx, expandedHeightPx) {
                                fun settle() {
                                    val actual = dragHeightPx.takeUnless(Float::isNaN) ?: sheetHeightAnimation.value
                                    val targetLevel = listOf(
                                        SocialActivitySheetLevel.Collapsed to collapsedHeightPx,
                                        SocialActivitySheetLevel.Split to splitHeightPx,
                                        SocialActivitySheetLevel.Expanded to expandedHeightPx,
                                    ).minBy { kotlin.math.abs(it.second - actual) }.first
                                    sheetScope.launch {
                                        sheetHeightAnimation.snapTo(actual)
                                        dragHeightPx = Float.NaN
                                        if (targetLevel != sheetLevel) sheetLevel = targetLevel
                                        else sheetHeightAnimation.animateTo(
                                            heightForLevelPx(targetLevel),
                                            animationSpec = spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMediumLow),
                                        )
                                    }
                                }
                                detectVerticalDragGestures(
                                    onDragStart = { dragHeightPx = sheetHeightAnimation.value },
                                    onVerticalDrag = { change, amount ->
                                        change.consume()
                                        val current = dragHeightPx.takeUnless(Float::isNaN) ?: sheetHeightAnimation.value
                                        dragHeightPx = (current - amount).coerceIn(collapsedHeightPx, expandedHeightPx)
                                    },
                                    onDragEnd = ::settle,
                                    onDragCancel = ::settle,
                                )
                            }
                            .clickable {
                                sheetLevel = if (sheetLevel == SocialActivitySheetLevel.Expanded) SocialActivitySheetLevel.Split else SocialActivitySheetLevel.Expanded
                            }
                            .semantics { contentDescription = sheetLabel },
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(Modifier.width(42.dp).height(5.dp).clip(CircleShape).background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .35f)))
                    }
                }
                if (sheetLevel == SocialActivitySheetLevel.Collapsed) {
                    item {
                        Row(Modifier.fillMaxWidth().clickable { sheetLevel = SocialActivitySheetLevel.Split }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Column(Modifier.weight(1f)) {
                                Text(formatDistance(activity.distanceM, unitSystem), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                                Text(activity.title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text(formatPace(activity.averagePaceSecsPerKm, unitSystem), fontWeight = FontWeight.Bold)
                                Text(stringResource(R.string.social_pace), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text(formatDuration(activity.durationSecs), fontWeight = FontWeight.Bold)
                                Text(stringResource(R.string.social_time), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                } else {
                if (activity.recognitions.isNotEmpty()) item {
                    SocialCard {
                        Text(stringResource(R.string.social_profile_milestones), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        activity.recognitions.take(3).forEach { recognition ->
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Outlined.EmojiEvents, null, tint = MaterialTheme.colorScheme.primary)
                                Spacer(Modifier.width(8.dp))
                                Text(badgeLabel(recognition.badgeId), style = MaterialTheme.typography.bodyMedium)
                            }
                        }
                        if (activity.recognitions.size > 3) Text("+${activity.recognitions.size - 3}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                item {
                    SocialCard(onClick = { openProfile(post.author) }) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            SocialAvatar(post.author)
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(post.author.displayName, fontWeight = FontWeight.SemiBold)
                                post.activityTimestamp?.let { RelativeActivityTime(it) }
                            }
                            Icon(Icons.Outlined.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                post.caption?.takeIf(String::isNotEmpty)?.let { caption -> item { Text(caption, style = MaterialTheme.typography.bodyMedium) } }
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Surface(
                            Modifier.heightIn(min = 40.dp).clip(CircleShape).clickable(onClick = cheer)
                                .semantics { contentDescription = cheerLabel },
                            shape = CircleShape,
                            color = (if (post.viewerHasCheered) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.tertiary).copy(alpha = .08f),
                        ) {
                            Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(
                                    if (post.viewerHasCheered) Icons.Outlined.Favorite else Icons.Outlined.FavoriteBorder,
                                    null,
                                    tint = if (post.viewerHasCheered) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.tertiary,
                                )
                            }
                        }
                        if (post.cheerCount > 0) SocialCheerAvatarsButton(post, { cheerersOpen = true })
                        Surface(
                            Modifier.heightIn(min = 40.dp).clip(CircleShape).clickable(onClick = comments)
                                .semantics { contentDescription = "$commentLabel, ${post.commentCount}" },
                            shape = CircleShape,
                            color = MaterialTheme.colorScheme.tertiary.copy(alpha = .08f),
                        ) {
                            Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                                Icon(Icons.Outlined.ChatBubbleOutline, null, tint = MaterialTheme.colorScheme.tertiary)
                                Spacer(Modifier.width(6.dp))
                                Text(post.commentCount.toString(), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.tertiary)
                            }
                        }
                    }
                }
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            Text(activity.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        }
                    }
                }
                if (photos.isNotEmpty() || photosLoading) item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(stringResource(R.string.social_activity_photos), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            itemsIndexed(photos, key = { _, photo -> photo.id }) { index, photo ->
                                SocialActivityPhotoTile(
                                    photo = photo,
                                    index = index,
                                    count = activity.totalPhotoCount,
                                    bytes = photoBytes[photo.id],
                                    selected = selectedPhotoIndex == index,
                                    unitSystem = unitSystem,
                                    onClick = {
                                        if (selectedPhotoIndex == index) lightboxPhotoIndex = index else selectedPhotoIndex = index
                                        trackPhotoPreview()
                                        loadPhotoContent(photo.id)
                                    },
                                )
                            }
                            if (photosLoading) items((activity.totalPhotoCount - photos.size).coerceAtLeast(0)) {
                                PhotoLoadingTile()
                            }
                        }
                    }
                }
                item {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        val stats = buildList {
                            add(stringResource(R.string.social_distance) to formatDistance(activity.distanceM, unitSystem))
                            add(stringResource(R.string.social_pace) to formatPace(activity.averagePaceSecsPerKm, unitSystem))
                            add(stringResource(ActivityR.string.activity_metric_moving_time) to formatDuration(activity.durationSecs))
                            activity.energyKilocalories?.let { add(stringResource(ActivityR.string.activity_metric_calories) to "$it") }
                            add(stringResource(ActivityR.string.activity_metric_elevation_gain) to activity.elevationM?.let { formatElevation(it, unitSystem) }.orEmpty().ifBlank { "—" })
                        }
                        Column(Modifier.fillMaxWidth().padding(horizontal = 12.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                            stats.chunked(2).forEach { row ->
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                                    row.forEach { (label, value) ->
                                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                            Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                            Text(value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 1)
                                        }
                                    }
                                    if (row.size == 1) Spacer(Modifier.weight(1f))
                                }
                            }
                        }
                    }
                }
                if (splits.isNotEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        TextButton(
                            onClick = {
                                showSplits = !showSplits
                                if (showSplits) trackSplitsViewed(splits.size)
                            },
                            modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                            contentPadding = PaddingValues(0.dp),
                        ) {
                            Text(stringResource(ActivityR.string.activity_splits_title), Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Start, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            Icon(if (showSplits) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, null)
                        }
                        if (showSplits) {
                            val fastestPace = splits.minOfOrNull(SocialSplit::paceSecondsPerKm) ?: 0.0
                            val slowestPace = splits.maxOfOrNull(SocialSplit::paceSecondsPerKm) ?: fastestPace
                            splits.forEachIndexed { index, split ->
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Text(stringResource(ActivityR.string.activity_split_number, index + 1), Modifier.width(54.dp), style = MaterialTheme.typography.labelMedium)
                                    Text(formatPace(split.paceSecondsPerKm, unitSystem), Modifier.width(68.dp), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
                                    Box(Modifier.weight(1f).height(8.dp).clip(CircleShape).background(MaterialTheme.colorScheme.surfaceVariant)) {
                                        val paceRange = (slowestPace - fastestPace).coerceAtLeast(1.0)
                                        val fraction = (1.0 - (split.paceSecondsPerKm - fastestPace) / paceRange).toFloat().coerceIn(.12f, 1f)
                                        Box(Modifier.fillMaxWidth(fraction).fillMaxHeight().background(MaterialTheme.colorScheme.primary))
                                    }
                                    Text(formatDistance(split.distanceMeters, unitSystem), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
                item {
                    Surface(shape = RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = .55f)) {
                        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                            Text(stringResource(ActivityR.string.activity_social_companion_title), fontWeight = FontWeight.SemiBold)
                            Text(stringResource(ActivityR.string.activity_social_companion_body, post.author.displayName), style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
                }
            }
        }
    }
    if (cheerersOpen) {
        ModalBottomSheet(onDismissRequest = { cheerersOpen = false }) {
            Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = 16.dp)) {
                Text(stringResource(ActivityR.string.activity_social_cheer_count), Modifier.padding(horizontal = 24.dp, vertical = 8.dp), style = MaterialTheme.typography.titleLarge)
                if (post.cheers.isEmpty()) {
                    Text(stringResource(ActivityR.string.activity_social_cheers_empty), Modifier.fillMaxWidth().padding(24.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                } else {
                    LazyColumn(Modifier.heightIn(max = 520.dp)) {
                        items(post.cheers, key = SocialPerson::id) { cheerer ->
                            Row(
                                Modifier.fillMaxWidth().clickable {
                                    cheerersOpen = false
                                    openProfile(cheerer)
                                }.heightIn(min = 56.dp).padding(horizontal = 20.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                SocialAvatar(cheerer)
                                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    Text(cheerer.displayName, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                                    cheerer.username?.takeIf(String::isNotBlank)?.let { Text("@$it", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                                }
                                Icon(Icons.Outlined.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
            }
        }
    }
    if (lightboxPhotoIndex >= 0 && photos.isNotEmpty()) {
        val pagerState = rememberPagerState(initialPage = lightboxPhotoIndex.coerceIn(photos.indices)) { photos.size }
        Dialog(onDismissRequest = { lightboxPhotoIndex = -1 }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            LaunchedEffect(pagerState.currentPage) {
                photos.getOrNull(pagerState.currentPage)?.let { loadPhotoContent(it.id) }
            }
            Surface(Modifier.fillMaxSize(), color = androidx.compose.ui.graphics.Color.Black) {
                Column(Modifier.fillMaxSize()) {
                    Row(Modifier.fillMaxWidth().statusBarsPadding(), verticalAlignment = Alignment.CenterVertically) {
                        IconButton({ lightboxPhotoIndex = -1 }) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.social_back), tint = androidx.compose.ui.graphics.Color.White) }
                        Text("${pagerState.currentPage + 1} / ${photos.size}", Modifier.weight(1f), color = androidx.compose.ui.graphics.Color.White, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                        Spacer(Modifier.width(48.dp))
                    }
                    HorizontalPager(state = pagerState, modifier = Modifier.weight(1f)) { page ->
                        val photo = photos[page]
                        val bytes = photoBytes["content:${photo.id}"] ?: photoBytes[photo.id]
                        val bitmap = remember(bytes) { bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } }
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            if (bitmap != null) Image(bitmap.asImageBitmap(), stringResource(R.string.social_activity_photo), Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                            else CircularProgressIndicator(color = androidx.compose.ui.graphics.Color.White)
                        }
                    }
                }
            }
        }
    }
    shareExport?.let { export ->
        val bitmap = remember(export.uri) {
            runCatching { context.contentResolver.openInputStream(export.uri)?.use(BitmapFactory::decodeStream) }.getOrNull()
        }
        Dialog(onDismissRequest = { shareExport = null; trackShareAction("cancelled") }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            Surface(Modifier.fillMaxWidth().padding(20.dp), shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surface) {
                Column(Modifier.padding(16.dp).heightIn(max = 720.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(stringResource(ActivityR.string.activity_share_preview), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    if (bitmap != null) Image(bitmap.asImageBitmap(), stringResource(ActivityR.string.activity_share_preview_description), Modifier.fillMaxWidth().weight(1f), contentScale = ContentScale.Fit)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        OutlinedButton(onClick = {
                            val saved = saveShareCardToGallery(context, export)
                            trackShareAction(if (saved) "saved" else "failure")
                            if (saved) Toast.makeText(context, context.getString(ActivityR.string.activity_share_image_saved), Toast.LENGTH_SHORT).show()
                            shareExport = null
                        }, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) { Text(stringResource(ActivityR.string.activity_save_image)) }
                        Button(onClick = {
                            val shared = runCatching {
                                val send = Intent(Intent.ACTION_SEND).apply {
                                    type = export.mimeType
                                    putExtra(Intent.EXTRA_STREAM, export.uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                context.startActivity(Intent.createChooser(send, null))
                            }.isSuccess
                            trackShareAction(if (shared) "shared" else "failure")
                            if (shared) shareExport = null
                        }, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) { Text(stringResource(ActivityR.string.activity_share)) }
                    }
                }
            }
        }
    }
}

private fun saveShareCardToGallery(context: android.content.Context, export: ActivityExport): Boolean = runCatching {
    val values = android.content.ContentValues().apply {
        put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, export.fileName)
        put(android.provider.MediaStore.Images.Media.MIME_TYPE, export.mimeType)
        put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Plainstride")
        put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
    }
    val resolver = context.contentResolver
    val target = resolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: error("Image destination unavailable")
    try {
        resolver.openOutputStream(target)?.use { output ->
            resolver.openInputStream(export.uri)?.use { input -> input.copyTo(output) } ?: error("Image unavailable")
        } ?: error("Image destination unavailable")
        resolver.update(target, android.content.ContentValues().apply { put(android.provider.MediaStore.Images.Media.IS_PENDING, 0) }, null, null)
    } catch (error: Throwable) {
        resolver.delete(target, null, null)
        throw error
    }
    true
}.getOrDefault(false)

private enum class SocialActivitySheetLevel { Collapsed, Split, Expanded }

@Composable
private fun SocialCheerAvatarsButton(post: SocialPost, onClick: () -> Unit) {
    val cheersLabel = stringResource(ActivityR.string.activity_social_cheer_count)
    Row(
        Modifier.heightIn(min = 40.dp).clip(CircleShape).clickable(onClick = onClick)
            .semantics {
                contentDescription = "$cheersLabel, ${post.cheerCount}"
            }
            .padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy((-6).dp), verticalAlignment = Alignment.CenterVertically) {
            post.cheers.take(3).forEach { person ->
                Box(Modifier.size(27.dp).border(1.5.dp, MaterialTheme.colorScheme.surface, CircleShape).padding(1.5.dp)) {
                    SocialAvatar(person, size = 24.dp)
                }
            }
            if (post.cheerCount > post.cheers.size.coerceAtMost(3)) {
                Surface(Modifier.size(24.dp), shape = CircleShape, color = MaterialTheme.colorScheme.surfaceVariant) {
                    Box(contentAlignment = Alignment.Center) {
                        Text("+${post.cheerCount - post.cheers.size.coerceAtMost(3)}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
        Text(post.cheerCount.toString(), Modifier.padding(start = 7.dp, end = 7.dp), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun SocialActivityPhotoTile(photo: ActivityPhoto, index: Int, count: Int, bytes: ByteArray?, selected: Boolean, unitSystem: MeasurementUnitSystem, onClick: () -> Unit) {
    val bitmap = remember(bytes) { bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } }
    Box(
        Modifier.size(width = 116.dp, height = 104.dp).clip(RoundedCornerShape(12.dp))
            .border(if (selected) 3.dp else 0.dp, if (selected) MaterialTheme.colorScheme.tertiary else androidx.compose.ui.graphics.Color.Transparent, RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (bitmap != null) Image(bitmap.asImageBitmap(), stringResource(R.string.social_activity_photo), Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        else Icon(Icons.Outlined.CameraAlt, stringResource(R.string.social_activity_photo), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(42.dp).background(Brush.verticalGradient(listOf(androidx.compose.ui.graphics.Color.Transparent, androidx.compose.ui.graphics.Color.Black.copy(alpha = .72f)))))
        Text(
            if (index == 0 || index == count - 1) photoTileLabel(index, count) else photo.distAtShot?.let { formatDistance(it, unitSystem) } ?: stringResource(R.string.social_activity_photo),
            Modifier.align(Alignment.BottomStart).padding(horizontal = 8.dp, vertical = 7.dp),
            color = androidx.compose.ui.graphics.Color.White,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

@Composable
private fun PhotoLoadingTile() {
    Box(
        Modifier.size(width = 116.dp, height = 104.dp).clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
    }
}

@Composable
private fun photoTileLabel(index: Int, count: Int): String = when (index) {
    0 -> stringResource(R.string.social_photo_start)
    count - 1 -> stringResource(R.string.social_photo_finish)
    else -> stringResource(R.string.social_activity_photo)
}

@Composable private fun ActivityStat(value:String,label:String)=Column(Modifier.widthIn(min=72.dp),horizontalAlignment=Alignment.CenterHorizontally){Text(value,fontWeight=FontWeight.Bold);Text(label,color=MaterialTheme.colorScheme.onSurfaceVariant,style=MaterialTheme.typography.labelSmall)}

private data class SocialSplit(val distanceMeters: Double, val durationSeconds: Double, val paceSecondsPerKm: Double)

private fun computeSocialSplits(
    route: List<MapCoordinate>,
    durationSeconds: Int?,
    unitSystem: MeasurementUnitSystem,
): List<SocialSplit> {
    if (route.size < 2 || (durationSeconds ?: 0) <= 0) return emptyList()
    val splitLength = if (unitSystem == MeasurementUnitSystem.metric) 1_000.0 else 1_609.344
    val edgeDuration = durationSeconds!!.toDouble() / (route.size - 1)
    val result = mutableListOf<SocialSplit>()
    var splitDistance = 0.0
    var splitDuration = 0.0

    fun finishSplit() {
        if (splitDistance <= 0.0) return
        result += SocialSplit(splitDistance, splitDuration, splitDuration / splitDistance * 1_000.0)
        splitDistance = 0.0
        splitDuration = 0.0
    }

    route.zipWithNext().forEach { (start, end) ->
        val edgeDistance = distanceBetween(start, end)
        if (edgeDistance <= 0.0) return@forEach
        var edgeRemaining = edgeDistance
        while (edgeRemaining > 0.0) {
            val consumed = minOf(edgeRemaining, splitLength - splitDistance)
            splitDistance += consumed
            splitDuration += edgeDuration * consumed / edgeDistance
            edgeRemaining -= consumed
            if (splitDistance >= splitLength - .01) finishSplit()
        }
    }
    finishSplit()
    return result
}

private fun distanceBetween(start: MapCoordinate, end: MapCoordinate): Double {
    val earthRadiusMeters = 6_371_000.0
    val startLatitude = Math.toRadians(start.latitude)
    val endLatitude = Math.toRadians(end.latitude)
    val latitudeDelta = endLatitude - startLatitude
    val longitudeDelta = Math.toRadians(end.longitude - start.longitude)
    val a = kotlin.math.sin(latitudeDelta / 2).let { it * it } +
        kotlin.math.cos(startLatitude) * kotlin.math.cos(endLatitude) * kotlin.math.sin(longitudeDelta / 2).let { it * it }
    return 2 * earthRadiusMeters * kotlin.math.atan2(kotlin.math.sqrt(a), kotlin.math.sqrt(1 - a))
}

private fun FeedActivity.toSavedActivity(post: SocialPost): SavedActivity {
    val duration = durationSecs?.coerceAtLeast(0) ?: 0
    val started = runCatching { java.time.OffsetDateTime.parse(startedAt).toInstant() }.getOrDefault(java.time.Instant.EPOCH)
    val ended = endedAt?.let { runCatching { java.time.OffsetDateTime.parse(it).toInstant() }.getOrNull() }
        ?: started.plusSeconds(duration.toLong())
    val activityType = when (this.type.lowercase()) {
        "cycling", "bike", "biking" -> ActivityType.cycling
        "hiking", "hike" -> ActivityType.hiking
        "walking", "walk" -> ActivityType.walking
        "swimming", "swim" -> ActivityType.swimming
        else -> ActivityType.running
    }
    val routePoints = route.routeCoordinates()
    val track = routePoints.mapIndexed { index, coordinate ->
        val fraction = if (routePoints.size <= 1) 0.0 else index.toDouble() / (routePoints.size - 1)
        ActivityTrackPoint(
            timestamp = started.plusMillis((duration * 1_000.0 * fraction).toLong()).toString(),
            latitude = coordinate.latitude,
            longitude = coordinate.longitude,
        )
    }
    return SavedActivity(
        id = id,
        accountId = post.author.id,
        serverActivityId = id,
        type = activityType,
        title = title,
        createdAt = post.createdAt ?: started.toString(),
        startedAt = started.toString(),
        endedAt = ended.toString(),
        durationSecs = duration,
        distanceM = distanceM ?: 0.0,
        averagePaceSecsPerKm = averagePaceSecsPerKm,
        elevationGainM = elevationM,
        energyKilocalories = energyKilocalories,
        track = track,
        localUpdatedAt = post.createdAt ?: ended.toString(),
    )
}

private fun formatDistance(value: Double?, unitSystem: MeasurementUnitSystem): String = value?.let {
    val distance = if (unitSystem == MeasurementUnitSystem.metric) it / 1000.0 else it / 1609.344
    val unit = if (unitSystem == MeasurementUnitSystem.metric) "km" else "mi"
    String.format(java.util.Locale.getDefault(), "%.1f %s", distance, unit)
} ?: "—"
private fun formatDuration(value: Int?): String = value?.let {
    if (it >= 3600) "%d:%02d:%02d".format(it / 3600, (it % 3600) / 60, it % 60) else "%d:%02d".format(it / 60, it % 60)
} ?: "—"
private fun formatPace(value: Double?, unitSystem: MeasurementUnitSystem): String = value?.let {
    val seconds = if (unitSystem == MeasurementUnitSystem.metric) it else it * 1.609344
    val unit = if (unitSystem == MeasurementUnitSystem.metric) "/km" else "/mi"
    "%d:%02d %s".format((seconds / 60).toInt(), seconds.toInt() % 60, unit)
} ?: "—"
private fun formatElevation(value: Double, unitSystem: MeasurementUnitSystem): String = if (unitSystem == MeasurementUnitSystem.metric) "%dm".format(value.toInt()) else "%d ft".format((value * 3.28084).toInt())
private fun formatSocialDate(value: String) = runCatching { java.time.OffsetDateTime.parse(value).format(java.time.format.DateTimeFormatter.ofLocalizedDateTime(java.time.format.FormatStyle.MEDIUM, java.time.format.FormatStyle.SHORT)) }.getOrDefault("")

@Composable
private fun RelativeActivityTime(value: String) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(value) {
        while (true) {
            delay(60_000)
            now = System.currentTimeMillis()
        }
    }
    val timestamp = runCatching { java.time.OffsetDateTime.parse(value).toInstant().toEpochMilli() }.getOrNull()
    val label = timestamp?.let {
        DateUtils.getRelativeTimeSpanString(
            it,
            now,
            DateUtils.MINUTE_IN_MILLIS,
            DateUtils.FORMAT_ABBREV_RELATIVE,
        ).toString()
    }.orEmpty()
    if (label.isNotEmpty()) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun String.plusDuration(durationSecs: Int?): String = runCatching {
    java.time.OffsetDateTime.parse(this)
        .plusSeconds((durationSecs ?: 0).toLong())
        .toString()
}.getOrDefault(this)

@Composable private fun CommentsDialog(post:SocialPost,comments:List<SocialComment>,add:(String)->Unit,delete:(SocialComment)->Unit,close:()->Unit){var body by rememberSaveable{mutableStateOf("")};AlertDialog(onDismissRequest=close,title={Text(stringResource(R.string.social_comments_for,post.author.displayName))},text={Column{LazyColumn(Modifier.heightIn(max=320.dp)){items(comments,key=SocialComment::id){comment->Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){Column(Modifier.weight(1f)){Text(comment.author.displayName,fontWeight=FontWeight.SemiBold);Text(comment.body)};if(comment.canDelete)IconButton({delete(comment)}){Icon(Icons.Outlined.Delete,stringResource(R.string.social_delete_comment))}}}};OutlinedTextField(body,{body=it.take(500)},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.social_add_comment))})}},confirmButton={TextButton({if(body.isNotBlank()){add(body);body=""}}){Text(stringResource(R.string.social_post_comment))}},dismissButton={TextButton(close){Text(stringResource(R.string.social_done))}})}

internal fun JsonElement?.routeCoordinates(): List<MapCoordinate> {
    val root = this as? JsonObject ?: return emptyList()
    if ((root["format"] as? JsonPrimitive)?.contentOrNull != "polyline5") return emptyList()
    val encoded = (root["encodedPolyline"] as? JsonPrimitive)?.contentOrNull ?: return emptyList()
    val pointCount = (root["pointCount"] as? JsonPrimitive)?.intOrNull ?: return emptyList()
    if (pointCount !in 2..120) return emptyList()
    var index = 0
    var latitude = 0
    var longitude = 0
    fun nextDelta(): Int? {
        var result = 0
        var shift = 0
        while (index < encoded.length && shift <= 30) {
            val value = encoded[index++].code - 63
            if (value !in 0..63) return null
            result = result or ((value and 0x1f) shl shift)
            if (value < 0x20) return if ((result and 1) == 0) result shr 1 else (result shr 1).inv()
            shift += 5
        }
        return null
    }
    val coordinates = mutableListOf<MapCoordinate>()
    while (index < encoded.length) {
        val latitudeDelta = nextDelta() ?: return emptyList()
        val longitudeDelta = nextDelta() ?: return emptyList()
        latitude += latitudeDelta
        longitude += longitudeDelta
        coordinates += MapCoordinate(latitude / 100_000.0, longitude / 100_000.0)
    }
    return coordinates.takeIf { it.size == pointCount } ?: emptyList()
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfileScreen(
    person: SocialPerson,
    posts: List<SocialPost>,
    close: () -> Unit,
    connect: () -> Unit,
    accept: () -> Unit,
    remove: () -> Unit,
    isCurrentUser: Boolean = false,
    isProcessing: Boolean = false,
    openActivity: (SocialPost) -> Unit,
) {
    var confirmsRemoval by remember { mutableStateOf(false) }
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            contentWindowInsets = WindowInsets.safeDrawing,
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.social_profile)) },
                    navigationIcon = {
                        IconButton(close) {
                            Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.social_back))
                        }
                    },
                    actions = {
                        when {
                            isCurrentUser -> Unit
                            person.relationship == "none" -> TextButton(connect, enabled = !isProcessing) { Text(stringResource(R.string.social_connect)) }
                            person.relationship == "pending" && person.connectionDirection == "incoming" -> {
                                TextButton(remove, enabled = !isProcessing) { Text(stringResource(R.string.social_decline)) }
                                TextButton(accept, enabled = !isProcessing) { Text(stringResource(R.string.social_accept)) }
                            }
                            person.relationship in setOf("accepted", "connected") -> IconButton({ confirmsRemoval = true }) {
                                Icon(Icons.Outlined.MoreVert, stringResource(R.string.social_profile_actions))
                            }
                        }
                    },
                )
            },
        ) { padding ->
            LazyColumn(
                Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                item {
                    Column(Modifier.fillMaxWidth().padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        SocialAvatar(person, 80.dp)
                        Spacer(Modifier.height(12.dp))
                        Text(person.displayName, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
                        person.username?.let { Text("@$it", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                }
                if (person.recognitions.isNotEmpty()) {
                    item { SectionHeader(stringResource(R.string.social_profile_milestones)) }
                    item {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            items(person.recognitions, key = { "${it.badgeId}-${it.awardedAt}" }) { award ->
                                Column(Modifier.width(86.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                                    Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primaryContainer) {
                                        Icon(Icons.Outlined.EmojiEvents, null, Modifier.padding(11.dp), tint = MaterialTheme.colorScheme.primary)
                                    }
                                    Spacer(Modifier.height(6.dp))
                                    Text(badgeLabel(award.badgeId), style = MaterialTheme.typography.labelSmall, maxLines = 2)
                                }
                            }
                        }
                    }
                }
                item { SectionHeader(stringResource(R.string.social_recent_activities)) }
                if (posts.isEmpty()) {
                    item { SocialCard { Text(stringResource(R.string.social_no_shared_activities), color = MaterialTheme.colorScheme.onSurfaceVariant) } }
                } else {
                    items(posts, key = SocialPost::id) { post ->
                        post.activity?.let { activity ->
                            SocialCard(onClick = { openActivity(post) }) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Column(Modifier.weight(1f)) {
                                        Text(activity.title, fontWeight = FontWeight.SemiBold)
                                        Text(formatSocialDate(activity.startedAt), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                    Icon(Icons.Outlined.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if (confirmsRemoval) AlertDialog(
        onDismissRequest = { confirmsRemoval = false },
        title = { Text(stringResource(R.string.social_remove_connection_confirmation_title)) },
        text = { Text(stringResource(R.string.social_remove_connection_confirmation_message, person.displayName)) },
        confirmButton = { TextButton({ remove(); confirmsRemoval = false }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text(stringResource(R.string.social_remove_connection)) } },
        dismissButton = { TextButton({ confirmsRemoval = false }) { Text(stringResource(R.string.social_cancel)) } },
    )
}
@Composable private fun reportReasonLabel(reason:ReportReason)=stringResource(when(reason){ReportReason.HARASSMENT->R.string.social_reason_harassment;ReportReason.HATE->R.string.social_reason_hate;ReportReason.SPAM->R.string.social_reason_spam;ReportReason.SEXUAL->R.string.social_reason_sexual;ReportReason.VIOLENCE->R.string.social_reason_violence;ReportReason.PRIVACY->R.string.social_reason_privacy;ReportReason.OTHER->R.string.social_reason_other})
@Composable private fun relationshipLabel(value:String)=when(value){"accepted","connected"->stringResource(R.string.social_relationship_connected);"pending"->stringResource(R.string.social_relationship_pending);else->stringResource(R.string.social_relationship_none)}
@Composable private fun badgeLabel(value:String)=stringResource(R.string.social_award_badge)
@Composable private fun GroupDialog(group: GroupSummary, close: () -> Unit, cheer: (String, String) -> Unit,focus:()->Unit,archive:()->Unit,invite:()->Unit) = AlertDialog(onDismissRequest = close, title = { Text(group.name) }, text = { LazyColumn { item { Text(stringResource(R.string.social_group_progress, group.completed, group.target ?: 0)) }; items(group.members, key = { it.person.id }) { member -> Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Text(member.person.displayName, Modifier.weight(1f)); IconButton({ cheer(member.person.id, "encouragement") }) { Icon(Icons.Outlined.FavoriteBorder, stringResource(R.string.social_cheer)) } } };item{TextButton(invite){Text(stringResource(R.string.social_invite))};Row{TextButton(focus){Text(stringResource(R.string.social_group_set_focus))};TextButton(archive){Text(stringResource(if(group.lifecycle=="archived")R.string.social_group_reactivate else R.string.social_group_archive))}}} } }, confirmButton = { TextButton(close) { Text(stringResource(R.string.social_done)) } })
@Composable private fun SocialEventDialog(event:SocialEvent,rsvp:()->Unit,invite:()->Unit,close:()->Unit)=AlertDialog(onDismissRequest=close,title={Text(event.name)},confirmButton={Row{TextButton(rsvp){Text(stringResource(if(event.joined)R.string.social_leave else R.string.social_join))};TextButton(invite){Text(stringResource(R.string.social_invite))}}},dismissButton={TextButton(close){Text(stringResource(R.string.social_done))}})
@Composable private fun PersonPickerDialog(title:String,people:List<SocialPerson>,close:()->Unit,confirm:(SocialPerson)->Unit){var selected by remember{mutableStateOf<SocialPerson?>(null)};AlertDialog(onDismissRequest=close,title={Text(title)},text={if(people.isEmpty())Text(stringResource(R.string.social_connections_empty))else LazyColumn{items(people,key=SocialPerson::id){person->Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){RadioButton(selected?.id==person.id,{selected=person});Text(person.displayName)}}}},confirmButton={TextButton({selected?.let(confirm)},enabled=selected!=null){Text(stringResource(R.string.social_invite))}},dismissButton={TextButton(close){Text(stringResource(R.string.social_done))}})}
