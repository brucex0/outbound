package com.plainstride.outbound.feature.social

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import java.text.Normalizer
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import com.plainstride.outbound.core.analytics.*

data class SocialUiState(
    val home: SocialHome = SocialHome(), val loading: Boolean = true, val refreshing: Boolean = false,
    val offline: Boolean = false, val search: String = "", val searchResults: List<SocialPerson> = emptyList(),
    val groupDirectory: List<GroupSummary> = emptyList(), val groupDirectoryQuery: String = "",
    val groupDirectoryNextCursor: String? = null,
    val groupDirectoryLoading: Boolean = false, val groupDirectoryFailed: Boolean = false,
    val selectedProfile: SocialPerson? = null, val selectedGroupDetail: GroupSummary? = null,
    val selectedGroupId: String? = null, val selectedGroupInvitationId: String? = null, val groupLoading: Boolean = false,
    val groupLoadFailed: Boolean = false, val groupUnavailable: Boolean = false,
    val groupInvitationResponding: Boolean = false,
    val selectedPost:SocialPost?=null,val comments:List<SocialComment> = emptyList(),
    val selectedActivityPost: SocialPost? = null,
    val activityDetailPhotos: List<ActivityPhoto> = emptyList(),
    val activityDetailPhotosLoading: Boolean = false,
    val activityDetailPhotoBytes: Map<String, ByteArray> = emptyMap(),
    val selectedEvent:SocialEvent?=null,val selectedInvitation:SocialInvitation?=null,
    val feedCursor: String? = null, val feedLoading: Boolean = false,
    val feedLoadFailed: Boolean = false,
    val connectionRequestLoading: Boolean = false,
    val connectionsLoadingMore: Boolean = false,
    val connectionsLoadFailed: Boolean = false,
    val connectionProfileLoading: Boolean = false, val connectionProfileCode: String? = null,
    val connectionProfileIsSelf: Boolean = false,
)
enum class SocialMessage { ACTION_COMPLETE, ACTION_FAILED, REPORTED, BLOCKED, GROUP_CREATED, GROUP_CREATION_FAILED, GROUP_SETTINGS_SAVED, GROUP_SETTINGS_FAILED, GROUP_JOINED, GROUP_DECLINED, GROUP_INVITATION_FAILED }
enum class ConnectionFeedback { REQUESTED, ALREADY_PENDING, INCOMING_PENDING, ALREADY_CONNECTED, SELF, UPDATED, REQUEST_FAILED, PROFILE_LOAD_FAILED, INVITE_LINK_FAILED }
sealed interface ConnectionEffect {
    data class Feedback(val value: ConnectionFeedback, val closeScanner: Boolean) : ConnectionEffect
    data class ShareInvitation(val url: String) : ConnectionEffect
}

@HiltViewModel class SocialViewModel @Inject constructor(
    private val repository: SocialRepository,
    private val analytics: ProductAnalytics,
) : ViewModel() {
    private val mutableState = MutableStateFlow(SocialUiState())
    val state = mutableState.asStateFlow()
    val messages = MutableSharedFlow<SocialMessage>(extraBufferCapacity = 4)
    val connectionEffects = MutableSharedFlow<ConnectionEffect>(extraBufferCapacity = 4)
    private var accountId: String? = null
    private var localeTag = "en"
    private var searchJob: Job? = null
    private var groupDirectoryJob: Job? = null
    private var groupLoadJob: Job? = null
    private var activityPhotoJob: Job? = null
    private var activityFeedLoadTracked = false
    private var feedPagesLoaded = 1
    private var connectionPagesLoaded = 1

    fun start(accountId: String, localeTag: String) {
        if (this.accountId == accountId && this.localeTag == localeTag) return
        this.accountId = accountId; this.localeTag = localeTag
        groupLoadJob?.cancel()
        mutableState.update { it.copy(selectedGroupId = null, selectedGroupDetail = null, groupLoading = false, groupLoadFailed = false, groupUnavailable = false, groupInvitationResponding = false) }
        groupDirectoryJob?.cancel()
        mutableState.update { it.copy(groupDirectory = emptyList(), groupDirectoryQuery = "", groupDirectoryNextCursor = null, groupDirectoryLoading = false, groupDirectoryFailed = false) }
        activityFeedLoadTracked = false
        feedPagesLoaded = 1
        connectionPagesLoaded = 1
        viewModelScope.launch { repository.observeHome(accountId, localeTag).collect { cached ->
            when (cached) {
                CachedSocialHome.Empty -> Unit
                is CachedSocialHome.Available -> {
                    mutableState.update { it.copy(home = cached.value, loading = false, offline = cached.stale) }
                    if (!activityFeedLoadTracked) trackActivityFeedLoaded(cached.value.posts)
                }
            }
        } }
        refresh()
        analytics.record(AnalyticsEvent("social_opened", mapOf(AnalyticsProperty.Source to "tab")))
    }

    fun refresh() { val account = accountId ?: return; viewModelScope.launch {
        mutableState.update { it.copy(refreshing = true) }
        repository.refresh(account, localeTag)
            .onFailure { mutableState.update { s -> s.copy(offline = true) }; messages.emit(SocialMessage.ACTION_FAILED) }
        mutableState.update { it.copy(refreshing = false, loading = false) }
    } }
    fun trackConnectionsOpened(entrySource: String) = analytics.record(AnalyticsEvent(
        "connections_opened",
        mapOf(AnalyticsProperty.EntrySource to entrySource),
    ))
    fun search(query: String) {
        mutableState.update { it.copy(search = query) }; searchJob?.cancel()
        val normalized = Normalizer.normalize(query.trim(), Normalizer.Form.NFKC)
        if (normalized.isEmpty()) { mutableState.update { it.copy(searchResults = emptyList()) }; return }
        searchJob = viewModelScope.launch { delay(300); repository.searchPeople(normalized).onSuccess { people -> mutableState.update { it.copy(searchResults = people) } } }
    }
    fun searchGroupDirectory(query: String) {
        mutableState.update { it.copy(groupDirectoryQuery = query, groupDirectory = emptyList(), groupDirectoryNextCursor = null) }
        groupDirectoryJob?.cancel()
        groupDirectoryJob = viewModelScope.launch {
            delay(300)
            loadGroupDirectory(query)
        }
    }
    fun refreshGroupDirectory() {
        groupDirectoryJob?.cancel()
        groupDirectoryJob = viewModelScope.launch { loadGroupDirectory(mutableState.value.groupDirectoryQuery, cursor = null) }
    }
    fun loadMoreGroupDirectory() {
        val state = mutableState.value
        val cursor = state.groupDirectoryNextCursor ?: return
        if (state.groupDirectoryLoading) return
        groupDirectoryJob?.cancel()
        groupDirectoryJob = viewModelScope.launch { loadGroupDirectory(state.groupDirectoryQuery, cursor) }
    }
    private suspend fun loadGroupDirectory(query: String, cursor: String? = null) {
        mutableState.update { it.copy(groupDirectoryLoading = true, groupDirectoryFailed = false) }
        repository.discoverGroups(query, cursor).onSuccess { response ->
            val groups = response.groups.filter { group -> group.currentUserRole == null }
            mutableState.update { state -> state.copy(
                groupDirectory = if (cursor == null) groups else (state.groupDirectory + groups).distinctBy(GroupSummary::id),
                groupDirectoryNextCursor = response.nextCursor,
                groupDirectoryLoading = false,
            ) }
            if (query.isNotBlank()) analytics.record(AnalyticsEvent("group_discovery_searched", mapOf(
                AnalyticsProperty.EntrySource to "groups",
                AnalyticsProperty.CountBucket to countBucket(groups.size),
            )))
        }.onFailure {
            mutableState.update { it.copy(groupDirectoryLoading = false, groupDirectoryFailed = true) }
        }
    }
    fun loadMore() { val cursor = mutableState.value.home.nextCursor ?: return; if (mutableState.value.feedLoading) return
        viewModelScope.launch {
            mutableState.update { it.copy(feedLoading = true, feedLoadFailed = false) }
            repository.loadFeed(cursor).onSuccess { page ->
                mutableState.update { s -> s.copy(home = s.home.copy(posts = (s.home.posts + page.items).distinctBy(SocialPost::id), nextCursor = page.nextCursor)) }
                feedPagesLoaded += 1
                analytics.record(AnalyticsEvent("paginated_list_page_loaded", mapOf(
                    AnalyticsProperty.Source to "activity_feed",
                    AnalyticsProperty.CountBucket to countBucket(page.items.size),
                    AnalyticsProperty.PageDepthBucket to when { feedPagesLoaded == 2 -> "page_2"; feedPagesLoaded <= 4 -> "pages_3_4"; else -> "page_5_plus" },
                )))
            }.onFailure { mutableState.update { it.copy(feedLoadFailed = true) } }
            mutableState.update { it.copy(feedLoading = false) }
        }
    }
    fun loadMoreConnections() {
        val current = mutableState.value
        val cursor = current.home.connectionNextCursor ?: return
        if (current.connectionsLoadingMore) return
        viewModelScope.launch {
            mutableState.update { it.copy(connectionsLoadingMore = true, connectionsLoadFailed = false) }
            repository.loadConnections(cursor).onSuccess { page ->
                mutableState.update { state -> state.copy(home = state.home.copy(
                    connections = (state.home.connections + page.items).distinctBy { it.connectionId ?: it.id },
                    connectionNextCursor = page.nextCursor,
                )) }
                connectionPagesLoaded += 1
                analytics.record(AnalyticsEvent("paginated_list_page_loaded", mapOf(
                    AnalyticsProperty.Source to "connections",
                    AnalyticsProperty.CountBucket to countBucket(page.items.size),
                    AnalyticsProperty.PageDepthBucket to when { connectionPagesLoaded == 2 -> "page_2"; connectionPagesLoaded <= 4 -> "pages_3_4"; else -> "page_5_plus" },
                )))
            }.onFailure { mutableState.update { it.copy(connectionsLoadFailed = true) } }
            mutableState.update { it.copy(connectionsLoadingMore = false) }
        }
    }
    fun toggleCheer(post: SocialPost) = mutate("social_cheer_toggled") { repository.setCheer(post.id, !post.viewerHasCheered).getOrThrow(); refresh() }
    fun trackSocialTabSelected(tab: String) = analytics.record(AnalyticsEvent("social_tab_selected", mapOf(
        AnalyticsProperty.SelectionType to tab,
        AnalyticsProperty.EntrySource to "tab_row",
    )))
    fun trackActivityDetailOpened() = analytics.record(AnalyticsEvent("activity_detail_opened", mapOf(AnalyticsProperty.SourceType to "social_feed")))
    fun trackFirstFeedCardVisible(post: SocialPost) = analytics.record(AnalyticsEvent(
        "social_feed_first_card_visible",
        mapOf(AnalyticsProperty.SourceType to if (post.isCurrentUser) "self" else "connection"),
    ))
    fun trackActiveNowExposed(count: Int) = analytics.record(AnalyticsEvent(
        "social_active_now_exposed",
        mapOf(AnalyticsProperty.CountBucket to countBucket(count)),
    ))
    fun trackActiveNowSelected(selection: String) = analytics.record(AnalyticsEvent(
        "social_active_now_selected",
        mapOf(AnalyticsProperty.SelectionType to selection, AnalyticsProperty.EntrySource to "active_now"),
    ))
    fun trackUpcomingExposed(events: List<SocialEvent>) = analytics.record(AnalyticsEvent(
        "social_upcoming_exposed",
        mapOf(
            AnalyticsProperty.CountBucket to countBucket(events.size),
            AnalyticsProperty.SourceType to if (events.any { it.source?.kind == "directInvitation" && !it.joined }) "action_required" else "relevant",
        ),
    ))
    fun trackUpcomingSelected(selection: String) = analytics.record(AnalyticsEvent(
        "social_upcoming_selected",
        mapOf(AnalyticsProperty.SelectionType to selection, AnalyticsProperty.EntrySource to "feed"),
    ))
    fun trackActivitySplitsViewed(count: Int) = analytics.record(AnalyticsEvent("activity_splits_viewed", mapOf(
        AnalyticsProperty.SourceType to "social_feed",
        AnalyticsProperty.CountBucket to countBucket(count),
    )))
    private fun trackActivityFeedLoaded(posts: List<SocialPost>) {
        activityFeedLoadTracked = true
        val source = when {
            posts.isEmpty() -> "empty"
            posts.any { !it.isCurrentUser } -> "connections"
            else -> "self_only"
        }
        val exactTimestampCount = posts.count { it.activity?.startedAt?.isNotBlank() == true }
        val timestampSource = when {
            posts.isEmpty() -> "empty"
            exactTimestampCount == posts.size -> "activity_start"
            exactTimestampCount == 0 -> "post_created_fallback"
            else -> "mixed"
        }
        analytics.record(AnalyticsEvent("activity_feed_loaded", mapOf(
            AnalyticsProperty.CountBucket to countBucket(posts.size),
            AnalyticsProperty.SourceType to source,
            AnalyticsProperty.TimestampSource to timestampSource,
        )))
    }

    private fun countBucket(count: Int) = when (count.coerceAtLeast(0)) {
        0 -> "0"
        1 -> "1"
        in 2..3 -> "2_3"
        in 4..7 -> "4_7"
        else -> "8_plus"
    }
    fun trackActivityPhotoPreviewed() = analytics.record(AnalyticsEvent(
        "photo_previewed",
        mapOf(AnalyticsProperty.SourceType to "activity_detail_carousel"),
    ))
    fun openActivityDetail(post: SocialPost) {
        val activity = post.activity ?: return
        activityPhotoJob?.cancel()
        mutableState.update { it.copy(
            selectedActivityPost = post,
            activityDetailPhotos = activity.photos,
            activityDetailPhotosLoading = activity.totalPhotoCount > activity.photos.size,
            activityDetailPhotoBytes = emptyMap(),
        ) }
        trackActivityDetailOpened()
        if (activity.recognitions.isNotEmpty()) analytics.record(AnalyticsEvent("activity_recognition_viewed", mapOf(
            AnalyticsProperty.SourceType to "social_feed",
            AnalyticsProperty.CountBucket to countBucket(activity.recognitions.size),
        )))
        if (activity.energyKilocalories != null) analytics.record(AnalyticsEvent("feature_exposed", mapOf(
            AnalyticsProperty.Feature to "completed_workout_calories",
            AnalyticsProperty.SourceType to "social_feed",
        )))
        activityPhotoJob = viewModelScope.launch {
            var photos = activity.photos
            if (activity.totalPhotoCount > photos.size) {
                repository.loadPostPhotos(post.id).onSuccess { photos = it }
            }
            if (mutableState.value.selectedActivityPost?.id != post.id) return@launch
            mutableState.update { it.copy(activityDetailPhotos = photos, activityDetailPhotosLoading = false) }
            photos.forEach { photo ->
                launch {
                    repository.downloadPostPhoto(photo.id).onSuccess { bytes ->
                        mutableState.update { state ->
                            if (state.selectedActivityPost?.id == post.id) {
                                state.copy(activityDetailPhotoBytes = state.activityDetailPhotoBytes + (photo.id to bytes))
                            } else state
                        }
                    }
                }
            }
        }
    }
    fun loadActivityPhotoContent(photoId: String) {
        val postId = mutableState.value.selectedActivityPost?.id ?: return
        if (mutableState.value.activityDetailPhotoBytes.containsKey("content:$photoId")) return
        viewModelScope.launch {
            repository.downloadPostPhoto(photoId, thumbnail = false).onSuccess { bytes ->
                mutableState.update { state ->
                    if (state.selectedActivityPost?.id == postId) {
                        state.copy(activityDetailPhotoBytes = state.activityDetailPhotoBytes + ("content:$photoId" to bytes))
                    } else state
                }
            }
        }
    }
    suspend fun loadFeedPhotoThumbnail(url: String): ByteArray? {
        val path = android.net.Uri.parse(url).pathSegments
        val marker = path.indexOf("activity-photos")
        val photoId = path.getOrNull(marker + 1)
        val representation = path.getOrNull(marker + 2)
        if (marker >= 0 && photoId != null && representation == "thumbnail") {
            return repository.downloadPostPhoto(photoId, thumbnail = true).getOrNull()
        }
        return null
    }
    fun closeActivityDetail() {
        activityPhotoJob?.cancel()
        activityPhotoJob = null
        mutableState.update { it.copy(
            selectedActivityPost = null,
            activityDetailPhotos = emptyList(),
            activityDetailPhotosLoading = false,
            activityDetailPhotoBytes = emptyMap(),
        ) }
    }
    fun trackProfileOpened() = analytics.record(AnalyticsEvent("social_profile_opened", mapOf(AnalyticsProperty.Source to "social")))
    fun openProfile(person: SocialPerson) { mutableState.update { it.copy(selectedProfile = person, connectionProfileCode = null, connectionProfileIsSelf = false) }; trackProfileOpened() }
    fun closeProfile() = mutableState.update { it.copy(selectedProfile = null, connectionProfileCode = null, connectionProfileIsSelf = false) }
    fun openTarget(type:String,id:String,entrySource:String="deep_link"){when(type){"activity","post"->viewModelScope.launch{var post=mutableState.value.home.posts.firstOrNull{it.id==id||it.activity?.id==id};var cursor=mutableState.value.home.nextCursor;repeat(5){if(post!=null||cursor==null)return@repeat;repository.loadFeed(cursor).onSuccess{page->post=page.items.firstOrNull{it.id==id||it.activity?.id==id};cursor=page.nextCursor}};post?.let(::openComments)};"event"->viewModelScope.launch{repository.event(id).onSuccess{event->mutableState.update{it.copy(selectedEvent=event)};analytics.record(AnalyticsEvent("activity_event_detail_opened",mapOf(AnalyticsProperty.EntrySource to entrySource)))}};"group"->loadGroup(id,entrySource);"invitation"->{val invitation=mutableState.value.home.invitations.firstOrNull{it.id==id||it.objectId==id};if(invitation?.kind=="group"&&invitation.objectId!=null)loadGroup(invitation.objectId,"invitation",invitation.id)else mutableState.update{it.copy(selectedInvitation=invitation)}}}}
    fun closeTarget() { closeGroup(); mutableState.update { it.copy(selectedEvent = null, selectedInvitation = null) } }
    fun closeEvent()=mutableState.update{it.copy(selectedEvent=null)}
    fun openGroup(group: GroupSummary) = loadGroup(group.id, "groups")

    fun retryGroup() { mutableState.value.selectedGroupId?.let { loadGroup(it, "group_retry", mutableState.value.selectedGroupInvitationId) } }

    private fun loadGroup(id: String, entrySource: String, invitationId: String? = null) {
        val targetInvitationId = invitationId ?: if (entrySource == "invitation") mutableState.value.home.invitations.firstOrNull { it.kind == "group" && it.objectId == id }?.id else null
        groupLoadJob?.cancel()
        mutableState.update { it.copy(selectedGroupId = id, selectedGroupInvitationId = targetInvitationId, selectedGroupDetail = null, groupLoading = true, groupLoadFailed = false, groupUnavailable = false) }
        groupLoadJob = viewModelScope.launch {
            repository.group(id, targetInvitationId).onSuccess { group ->
                if (mutableState.value.selectedGroupId != id) return@onSuccess
                mutableState.update { it.copy(selectedGroupDetail = group, groupLoading = false) }
                analytics.record(AnalyticsEvent("group_opened", mapOf(
                    AnalyticsProperty.EntrySource to entrySource,
                    AnalyticsProperty.SelectionType to if (group.invitationPreview) "invited" else "group",
                )))
                if (group.invitationPreview) analytics.record(AnalyticsEvent("feature_exposed", mapOf(AnalyticsProperty.Feature to "group_invitation_preview")))
            }.onFailure { error ->
                if (error is CancellationException) throw error
                if (mutableState.value.selectedGroupId != id) return@onFailure
                logGroupFailure("load group detail", error)
                val unavailable = (error as? SocialException)?.reason in setOf(SocialError.FORBIDDEN, SocialError.NOT_FOUND, SocialError.CONFLICT)
                mutableState.update { it.copy(groupLoading = false, groupLoadFailed = true, groupUnavailable = unavailable) }
            }
        }
    }

    fun respondToGroupPreview(group: GroupSummary, accept: Boolean) {
        val invitation = group.pendingInvitation ?: return
        if (mutableState.value.groupInvitationResponding) return
        val account = accountId
        mutableState.update { it.copy(groupInvitationResponding = true) }
        viewModelScope.launch {
            val result = if (accept) repository.acceptGroupInvitation(invitation.id) else
                repository.respondToInvitation(SocialInvitation(invitation.id, "group", group.name, invitation.sender, group.id), false).map { null }
            if (accountId != account) return@launch
            mutableState.update { it.copy(groupInvitationResponding = false) }
            result.onSuccess { joined ->
                mutableState.update { state -> state.copy(home = state.home.copy(invitations = state.home.invitations.filterNot { it.id == invitation.id })) }
                if (mutableState.value.selectedGroupId == group.id) {
                    if (accept && joined != null) mutableState.update { it.copy(selectedGroupDetail = joined) }
                    else closeGroup()
                }
                val properties = mutableMapOf<AnalyticsProperty, Any>(AnalyticsProperty.EntrySource to "group_invitation_preview")
                if (accept) properties[AnalyticsProperty.ParticipantCountBucket] = countBucket(joined?.memberCount ?: group.memberCount)
                analytics.record(AnalyticsEvent(if (accept) "group_invitation_accepted" else "group_invitation_declined", properties))
                messages.emit(if (accept) SocialMessage.GROUP_JOINED else SocialMessage.GROUP_DECLINED)
                refresh()
            }.onFailure { error ->
                if (error is CancellationException) throw error
                logGroupFailure(if (accept) "accept group invitation" else "decline group invitation", error)
                analytics.record(AnalyticsEvent("group_operation_failed", mapOf(
                    AnalyticsProperty.SourceType to "group_invitation_preview", AnalyticsProperty.ErrorCategory to "api_unavailable",
                )))
                messages.emit(SocialMessage.GROUP_INVITATION_FAILED)
                // Revalidate after failure so a revoked/expired invitation loses its actions.
                if (mutableState.value.selectedGroupId == group.id) loadGroup(group.id, "group_retry", invitation.id)
            }
        }
    }

    private fun logGroupFailure(operation: String, error: Throwable) {
        val apiError = error as? SocialException
        Log.w("SocialViewModel", "$operation failed status=${apiError?.httpStatus} category=${apiError?.reason ?: error.javaClass.simpleName}")
    }
    fun consumeGroupInvite(token: String) = mutate("group_invite_link_consumed") { repository.consumeGroupInvite(token).getOrThrow().let { group -> mutableState.update { it.copy(selectedGroupDetail = group) } }; refresh() }
    fun closeGroup() {
        groupLoadJob?.cancel()
        mutableState.update { it.copy(selectedGroupId = null, selectedGroupInvitationId = null, selectedGroupDetail = null, groupLoading = false, groupLoadFailed = false, groupUnavailable = false) }
    }
    fun joinGroup(group: GroupSummary) = mutate("social_group_membership_changed") { repository.setGroupMembership(group.id, group.role == null).getOrThrow(); refresh(); refreshGroupDirectory() }
    fun reportPerson(person: SocialPerson, reason: ReportReason, feedback: (Boolean) -> Unit) = mutate("social_content_reported", SocialMessage.REPORTED, feedback) { repository.reportPerson(person.id, reason).getOrThrow() }
    fun report(post: SocialPost, reason: String) = mutate("social_content_reported", SocialMessage.REPORTED) { repository.reportPost(post.id, ReportReason.entries.firstOrNull { it.wireValue == reason } ?: ReportReason.OTHER).getOrThrow() }
    fun deletePost(post: SocialPost) = mutate("social_post_deleted") { repository.deletePost(post.id).getOrThrow(); refresh() }
    fun block(post: SocialPost) = mutate("social_person_blocked", SocialMessage.BLOCKED) { repository.block(post.author.id).getOrThrow(); refresh() }
    fun cheerGroup(group: GroupSummary, recipientId: String, preset: String) = mutate("group_cheer_sent") { repository.cheerGroup(group.id, recipientId, preset).getOrThrow() }
    fun openComments(post:SocialPost)=viewModelScope.launch{repository.comments(post.id).onSuccess{comments->mutableState.update{it.copy(selectedPost=post,comments=comments)}};analytics.record(AnalyticsEvent("social_comments_opened"))}
    fun closeComments()=mutableState.update{it.copy(selectedPost=null,comments=emptyList())}
    fun addComment(body:String){
        val post=mutableState.value.selectedPost?:return
        val clean=body.trim();if(clean.isEmpty())return
        viewModelScope.launch { repository.addComment(post.id,clean).fold(onSuccess={comment->
            mutableState.update{state->state.copy(comments=state.comments+comment,selectedPost=state.selectedPost?.copy(commentCount=state.selectedPost.commentCount+1),home=state.home.copy(posts=state.home.posts.map{if(it.id==post.id)it.copy(commentCount=it.commentCount+1)else it}))}
            messages.emit(SocialMessage.ACTION_COMPLETE);analytics.record(AnalyticsEvent("social_comment_created",mapOf(AnalyticsProperty.Result to "success")))
        },onFailure={messages.emit(SocialMessage.ACTION_FAILED);analytics.record(AnalyticsEvent("social_comment_created",mapOf(AnalyticsProperty.Result to "failure")))}) }
    }
    fun deleteComment(comment:SocialComment){
        val post=mutableState.value.selectedPost?:return;val previous=mutableState.value
        mutableState.update{state->state.copy(comments=state.comments.filterNot{it.id==comment.id},selectedPost=state.selectedPost?.copy(commentCount=(state.selectedPost.commentCount-1).coerceAtLeast(0)),home=state.home.copy(posts=state.home.posts.map{if(it.id==post.id)it.copy(commentCount=(it.commentCount-1).coerceAtLeast(0))else it}))}
        viewModelScope.launch { repository.deleteComment(comment.id).onSuccess{messages.emit(SocialMessage.ACTION_COMPLETE);analytics.record(AnalyticsEvent("social_comment_deleted",mapOf(AnalyticsProperty.Result to "success")))}.onFailure{mutableState.value=previous;messages.emit(SocialMessage.ACTION_FAILED);analytics.record(AnalyticsEvent("social_comment_deleted",mapOf(AnalyticsProperty.Result to "failure")))}}
    }
    fun setEventRsvp(event:SocialEvent,going:Boolean,mode:String="in_person")=mutate("social_event_rsvp_changed"){repository.setEventRsvp(event.id,going,mode).getOrThrow();repository.event(event.id).onSuccess{updated->mutableState.update{it.copy(selectedEvent=updated)}};refresh()}
    fun refreshEvent(eventId:String)=viewModelScope.launch{repository.event(eventId).onSuccess{updated->mutableState.update{state->if(state.selectedEvent?.id==eventId)state.copy(selectedEvent=updated)else state}}}
    fun inviteToEvent(event:SocialEvent,person:SocialPerson?)=mutate("social_event_invitation_sent"){repository.inviteToEvent(event.id,person?.id).getOrThrow()}
    fun connect(person:SocialPerson)=mutate("social_connection_requested"){repository.connect(person.id).getOrThrow();refresh()}
    fun acceptConnection(connectionId:String)=mutate("social_connection_accepted"){repository.accept(connectionId).getOrThrow();refresh()}
    fun removeConnection(connectionId: String) = mutate("social_connection_removed") {
        removeConnectionAndRefresh(connectionId)
    }
    fun disconnectProfile(connectionId: String, onRemoved: () -> Unit, feedback: (Boolean) -> Unit) = mutate("social_connection_removed", feedback = feedback) {
        removeConnectionAndRefresh(connectionId)
        onRemoved()
    }
    private suspend fun removeConnectionAndRefresh(connectionId: String) {
        repository.removeConnection(connectionId).getOrThrow()
        mutableState.update { state -> state.copy(
            home = state.home.copy(connections = state.home.connections.filterNot { it.connectionId == connectionId }),
        ) }
        refresh()
    }
    fun scannerOpened() = analytics.record(AnalyticsEvent("feature_exposed", mapOf(AnalyticsProperty.Feature to "connection_qr_scanner")))
    fun inviteByLink() = viewModelScope.launch {
        repository.referralLink().fold(
            onSuccess = { connectionEffects.emit(ConnectionEffect.ShareInvitation(it.url)) },
            onFailure = { connectionEffects.emit(ConnectionEffect.Feedback(ConnectionFeedback.INVITE_LINK_FAILED, closeScanner = false)) },
        )
    }
    fun openConnectionCodeProfile(code: String) {
        if (mutableState.value.connectionProfileLoading) return
        mutableState.update { it.copy(connectionProfileLoading = true, selectedProfile = null, connectionProfileCode = null, connectionProfileIsSelf = false) }
        viewModelScope.launch {
            repository.connectionLinkPreview(code).fold(
                onSuccess = { preview ->
                    mutableState.update { it.copy(
                        connectionProfileLoading = false,
                        selectedProfile = preview.person,
                        connectionProfileCode = code,
                        connectionProfileIsSelf = preview.isSelf,
                    ) }
                    analytics.record(AnalyticsEvent("social_profile_opened", mapOf(AnalyticsProperty.EntrySource to "connection_qr_code")))
                },
                onFailure = { error ->
                    mutableState.update { it.copy(connectionProfileLoading = false) }
                    val reason = (error as? SocialException)?.reason
                    analytics.record(AnalyticsEvent("social_operation_failed", mapOf(
                        AnalyticsProperty.SourceType to "connection_qr_profile",
                        AnalyticsProperty.ErrorCategory to if (reason in setOf(SocialError.FORBIDDEN, SocialError.NOT_FOUND, SocialError.INVALID_RESPONSE)) "invalid_link" else "api_unavailable",
                    )))
                    connectionEffects.emit(ConnectionEffect.Feedback(ConnectionFeedback.PROFILE_LOAD_FAILED, closeScanner = false))
                },
            )
        }
    }
    fun connectFromConnectionCode() {
        val code = mutableState.value.connectionProfileCode ?: return
        if (mutableState.value.connectionRequestLoading) return
        mutableState.update { it.copy(connectionRequestLoading = true) }
        viewModelScope.launch {
            repository.consumeConnectionLink(code).fold(
                onSuccess = { response ->
                    mutableState.update { it.copy(connectionRequestLoading = false, selectedProfile = response.person) }
                    analytics.record(AnalyticsEvent("connection_qr_code_request_result", mapOf(
                        AnalyticsProperty.Result to (response.result.takeIf { it in CONNECTION_RESULTS } ?: "unknown"),
                    )))
                    connectionEffects.emit(ConnectionEffect.Feedback(connectionFeedback(response.result), closeScanner = false))
                    if (response.result != "self") refresh()
                },
                onFailure = {
                    mutableState.update { it.copy(connectionRequestLoading = false) }
                    analytics.record(AnalyticsEvent("connection_qr_code_request_result", mapOf(AnalyticsProperty.Result to "failure")))
                    connectionEffects.emit(ConnectionEffect.Feedback(ConnectionFeedback.REQUEST_FAILED, closeScanner = false))
                },
            )
        }
    }
    fun createGroup(template:String,name:String?,city:String?,members:List<SocialPerson>,timeZone:String?,onComplete:(Boolean)->Unit={})=viewModelScope.launch {
        repository.createGroup(template,name,city,members.map{it.id},timeZone).fold(
            onSuccess = { created ->
                mutableState.update { it.copy(selectedGroupDetail=created) }
                refresh()
                if (template == "motivation") messages.emit(SocialMessage.GROUP_CREATED)
                analytics.record(AnalyticsEvent("group_creation_completed", mapOf(
                    AnalyticsProperty.EntrySource to "social",
                    AnalyticsProperty.ParticipantCountBucket to countBucket(members.size + 1),
                )))
                if (members.isNotEmpty()) analytics.record(AnalyticsEvent("group_invitation_sent", mapOf(
                    AnalyticsProperty.EntrySource to "creation",
                    AnalyticsProperty.ParticipantCountBucket to countBucket(members.size),
                    AnalyticsProperty.Result to "success",
                )))
                onComplete(true)
            },
            onFailure = {
                messages.emit(SocialMessage.GROUP_CREATION_FAILED)
                analytics.record(AnalyticsEvent("group_creation_failed", mapOf(
                    AnalyticsProperty.EntrySource to "social",
                    AnalyticsProperty.ErrorCategory to "api_unavailable",
                )))
                onComplete(false)
            },
        )
    }
    fun trackGroupTemplateSelected(template:String) = analytics.record(AnalyticsEvent("group_template_selected", mapOf(AnalyticsProperty.SelectionType to template)))
    fun inviteToGroup(group:GroupSummary,members:List<SocialPerson>,idempotencyKey:String)=mutate("group_invitation_sent"){repository.inviteToGroup(group.id,members.map{it.id},idempotencyKey).getOrThrow();openGroup(group)}
    fun setGroupFocus(group:GroupSummary,mode:String,target:Int?,nextWeek:Boolean)=mutate("group_focus_changed"){repository.setGroupFocus(group.id,mode,target,nextWeek).getOrThrow();openGroup(group)}
    fun createGroupActivity(group: GroupSummary, title: String, location: String?) = mutate("group_activity_created") {
        val startsAt = java.time.OffsetDateTime.now().plusDays(1).withHour(9).withMinute(0).withSecond(0).withNano(0).toString()
        repository.createEvent(CreateEventBody(title = title.trim(), startsAt = startsAt, locationName = location?.trim()?.takeIf { it.isNotEmpty() }, groupId = group.id)).getOrThrow()
        openGroup(group)
    }
    fun setGroupArchived(group:GroupSummary,archived:Boolean)=mutate("group_lifecycle_changed"){repository.setGroupArchived(group.id,archived).getOrThrow().let{updated->mutableState.update{it.copy(selectedGroupDetail=updated)}};refresh()}
    fun renameGroup(group:GroupSummary,name:String)=mutate("group_renamed"){repository.renameGroup(group.id,name).getOrThrow().let{updated->mutableState.update{it.copy(selectedGroupDetail=updated)}};refresh()}
    fun saveGroupSettings(group:GroupSummary,name:String,city:String,resetWeekday:Int,timeZone:String,apply:String,muted:Boolean,applyChanged:Boolean)=viewModelScope.launch {
        runCatching {
            var updated = group
            if (name.trim() != group.name || city.trim() != group.city.orEmpty()) {
                updated = repository.updateGroupDetails(group.id, name, city).getOrThrow()
                if (name.trim() != group.name) analytics.record(AnalyticsEvent("group_name_changed"))
                if (city.trim() != group.city.orEmpty()) analytics.record(AnalyticsEvent("group_location_changed"))
            }
            if (resetWeekday != group.resetWeekday || timeZone.trim() != group.timeZone || applyChanged) {
                updated = repository.updateGroupCalendar(group.id, resetWeekday, timeZone.trim(), apply).getOrThrow()
                analytics.record(AnalyticsEvent("group_calendar_changed", mapOf(AnalyticsProperty.SourceType to apply)))
            }
            if (muted != group.currentUserMuted) {
                updated = repository.muteGroup(group.id, muted).getOrThrow()
                analytics.record(AnalyticsEvent("group_notifications_changed", mapOf(AnalyticsProperty.SelectionType to if (muted) "muted" else "unmuted")))
            }
            mutableState.update { it.copy(selectedGroupDetail = updated) }
            refresh()
        }.onSuccess { messages.emit(SocialMessage.GROUP_SETTINGS_SAVED) }
            .onFailure {
                Log.w("SocialViewModel", "Group settings save failed (${it.javaClass.simpleName})")
                analytics.record(AnalyticsEvent("group_operation_failed", mapOf(
                    AnalyticsProperty.SourceType to "group_settings",
                    AnalyticsProperty.ErrorCategory to "api_unavailable",
                )))
                messages.emit(SocialMessage.GROUP_SETTINGS_FAILED)
            }
    }
    fun cancelGroupInvitation(group:GroupSummary,invitationId:String)=mutate("group_invitation_cancelled"){repository.cancelGroupInvitation(group.id,invitationId).getOrThrow().let{updated->mutableState.update{it.copy(selectedGroupDetail=updated)}};refresh()}
    fun updateGroupMemberRole(group:GroupSummary,userId:String,role:String)=mutate("group_member_role_changed"){repository.updateGroupMemberRole(group.id,userId,role).getOrThrow().let{updated->mutableState.update{it.copy(selectedGroupDetail=updated)}};refresh()}
    fun transferGroupOwnership(group:GroupSummary,userId:String)=mutate("group_ownership_transferred"){repository.transferGroupOwnership(group.id,userId).getOrThrow().let{updated->mutableState.update{it.copy(selectedGroupDetail=updated)}};refresh()}
    fun createGroupNotice(group:GroupSummary,title:String?,body:String,pinned:Boolean)=mutate("group_notice_published"){repository.createGroupNotice(group.id,title,body,pinned).getOrThrow().let{updated->mutableState.update{it.copy(selectedGroupDetail=updated)}}}
    fun markGroupNoticesRead(group:GroupSummary)=mutate("group_notices_read"){repository.markGroupNoticesRead(group.id).getOrThrow().let{updated->mutableState.update{it.copy(selectedGroupDetail=updated)}}}
    fun setGroupCommitment(group:GroupSummary,target:Int?,skipped:Boolean)=mutate("group_personal_target_changed"){repository.setGroupCommitment(group.id,target,skipped).getOrThrow().let{updated->mutableState.update{it.copy(selectedGroupDetail=updated)}};refresh()}
    fun muteGroup(group:GroupSummary,muted:Boolean)=mutate("group_notifications_changed"){repository.muteGroup(group.id,muted).getOrThrow().let{updated->mutableState.update{it.copy(selectedGroupDetail=updated)}}}
    fun leaveGroup(group:GroupSummary)=mutate("group_member_left"){repository.leaveGroup(group.id).getOrThrow();closeGroup();refresh()}
    fun removeGroupMember(group:GroupSummary,userId:String)=mutate("group_member_removed"){repository.removeGroupMember(group.id,userId).getOrThrow().let{updated->mutableState.update{it.copy(selectedGroupDetail=updated)}};refresh()}
    fun trackGroupMembersOpened(memberCount: Int) = analytics.record(AnalyticsEvent("group_members_opened", mapOf(
        AnalyticsProperty.EntrySource to "group_detail",
        AnalyticsProperty.ParticipantCountBucket to when (memberCount.coerceAtLeast(0)) {
            0 -> "0"; 1 -> "1"; in 2..3 -> "2_3"; in 4..7 -> "4_7"; else -> "8_plus"
        },
    )))
    fun respondToInvitation(invitation:SocialInvitation,accept:Boolean)=mutate("social_invitation_responded"){repository.respondToInvitation(invitation,accept).getOrThrow();closeTarget();refresh()}
    private fun mutate(
        event: String,
        success: SocialMessage = SocialMessage.ACTION_COMPLETE,
        feedback: ((Boolean) -> Unit)? = null,
        block: suspend () -> Unit,
    ) = viewModelScope.launch {
        runCatching { block() }.onSuccess {
            feedback?.invoke(true)
            messages.emit(success)
            analytics.record(AnalyticsEvent(event, mapOf(AnalyticsProperty.Result to "success")))
        }.onFailure { error ->
            if (error is CancellationException) throw error
            val socialError = error as? SocialException
            Log.w("SocialViewModel", "$event failed (type=${error.javaClass.simpleName}, status=${socialError?.httpStatus}, reason=${socialError?.reason})")
            feedback?.invoke(false)
            messages.emit(SocialMessage.ACTION_FAILED)
            analytics.record(AnalyticsEvent(event, mapOf(AnalyticsProperty.Result to "failure")))
        }
    }

    private companion object {
        val CONNECTION_RESULTS = setOf("requested", "already_pending", "incoming_pending", "already_connected", "self")
        fun connectionFeedback(result: String) = when (result) {
            "requested" -> ConnectionFeedback.REQUESTED
            "already_pending" -> ConnectionFeedback.ALREADY_PENDING
            "incoming_pending" -> ConnectionFeedback.INCOMING_PENDING
            "already_connected" -> ConnectionFeedback.ALREADY_CONNECTED
            "self" -> ConnectionFeedback.SELF
            else -> ConnectionFeedback.UPDATED
        }
    }
}
