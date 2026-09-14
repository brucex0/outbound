package com.plainstride.outbound.feature.social

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import java.text.Normalizer
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import com.plainstride.outbound.core.analytics.*

data class SocialUiState(
    val home: SocialHome = SocialHome(), val loading: Boolean = true, val refreshing: Boolean = false,
    val offline: Boolean = false, val search: String = "", val searchResults: List<SocialPerson> = emptyList(),
    val selectedProfile: SocialPerson? = null, val selectedCircle: CircleSummary? = null,
    val selectedPost:SocialPost?=null,val comments:List<SocialComment> = emptyList(),
    val selectedEvent:SocialEvent?=null,val selectedGroup:SocialGroup?=null,val selectedInvitation:SocialInvitation?=null,
    val feedCursor: String? = null, val feedLoading: Boolean = false,
    val connectionRequestLoading: Boolean = false,
    val connectionProfileLoading: Boolean = false, val connectionProfileCode: String? = null,
    val connectionProfileIsSelf: Boolean = false,
)
enum class SocialMessage { ACTION_COMPLETE, ACTION_FAILED, REPORTED, BLOCKED }
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

    fun start(accountId: String, localeTag: String) {
        if (this.accountId == accountId && this.localeTag == localeTag) return
        this.accountId = accountId; this.localeTag = localeTag
        viewModelScope.launch { repository.observeHome(accountId, localeTag).collect { cached ->
            when (cached) { CachedSocialHome.Empty -> Unit; is CachedSocialHome.Available -> mutableState.update { it.copy(home = cached.value, loading = false, offline = cached.stale) } }
        } }
        refresh()
        analytics.record(AnalyticsEvent("social_opened", mapOf(AnalyticsProperty.Source to "tab")))
    }

    fun refresh() { val account = accountId ?: return; viewModelScope.launch {
        mutableState.update { it.copy(refreshing = true) }
        repository.refresh(account, localeTag).onFailure { mutableState.update { s -> s.copy(offline = true) }; messages.emit(SocialMessage.ACTION_FAILED) }
        mutableState.update { it.copy(refreshing = false, loading = false) }
    } }
    fun search(query: String) {
        mutableState.update { it.copy(search = query) }; searchJob?.cancel()
        val normalized = Normalizer.normalize(query.trim(), Normalizer.Form.NFKC)
        if (normalized.isEmpty()) { mutableState.update { it.copy(searchResults = emptyList()) }; return }
        searchJob = viewModelScope.launch { delay(300); repository.searchPeople(normalized).onSuccess { people -> mutableState.update { it.copy(searchResults = people) } } }
    }
    fun loadMore() { val cursor = mutableState.value.home.nextCursor ?: return; if (mutableState.value.feedLoading) return
        viewModelScope.launch { mutableState.update { it.copy(feedLoading = true) }; repository.loadFeed(cursor).onSuccess { page -> mutableState.update { s -> s.copy(home = s.home.copy(posts = (s.home.posts + page.items).distinctBy(SocialPost::id), nextCursor = page.nextCursor)) }; analytics.record(AnalyticsEvent("paginated_list_page_loaded", mapOf(AnalyticsProperty.Source to "social_feed", AnalyticsProperty.PageDepthBucket to "page_2_plus"))) }; mutableState.update { it.copy(feedLoading = false) } }
    }
    fun toggleCheer(post: SocialPost) = mutate("social_cheer_toggled") { repository.setCheer(post.id, !post.viewerHasCheered).getOrThrow(); refresh() }
    fun trackActivityDetailOpened() = analytics.record(AnalyticsEvent("activity_detail_opened", mapOf(AnalyticsProperty.Source to "social_feed")))
    fun openProfile(person: SocialPerson) { mutableState.update { it.copy(selectedProfile = person, connectionProfileCode = null, connectionProfileIsSelf = false) }; analytics.record(AnalyticsEvent("social_profile_opened", mapOf(AnalyticsProperty.Source to "social"))) }
    fun closeProfile() = mutableState.update { it.copy(selectedProfile = null, connectionProfileCode = null, connectionProfileIsSelf = false) }
    fun openTarget(type:String,id:String){when(type){"activity","post"->viewModelScope.launch{var post=mutableState.value.home.posts.firstOrNull{it.id==id||it.activity?.id==id};var cursor=mutableState.value.home.nextCursor;repeat(5){if(post!=null||cursor==null)return@repeat;repository.loadFeed(cursor).onSuccess{page->post=page.items.firstOrNull{it.id==id||it.activity?.id==id};cursor=page.nextCursor}};post?.let(::openComments)};"event"->viewModelScope.launch{repository.event(id).onSuccess{event->mutableState.update{it.copy(selectedEvent=event)}}};"circle"->viewModelScope.launch{repository.circle(id).onSuccess{circle->mutableState.update{it.copy(selectedCircle=circle)}}};"group"->mutableState.update{state->state.copy(selectedGroup=state.home.groups.firstOrNull{it.id==id})};"invitation"->mutableState.update{state->state.copy(selectedInvitation=state.home.invitations.firstOrNull{it.id==id||it.objectId==id})}}}
    fun closeTarget()=mutableState.update{it.copy(selectedEvent=null,selectedGroup=null,selectedInvitation=null)}
    fun openCircle(circle: CircleSummary) = viewModelScope.launch { repository.circle(circle.id).onSuccess { value -> mutableState.update { it.copy(selectedCircle = value) } } }
    fun closeCircle() = mutableState.update { it.copy(selectedCircle = null) }
    fun joinGroup(group: SocialGroup) = mutate("social_group_membership_changed") { repository.setGroupMembership(group.id, !group.joined).getOrThrow(); refresh() }
    fun report(post: SocialPost, reason: String) = mutate("social_content_reported", SocialMessage.REPORTED) { repository.reportPost(post.id, ReportReason.entries.firstOrNull { it.wireValue == reason } ?: ReportReason.OTHER).getOrThrow() }
    fun deletePost(post: SocialPost) = mutate("social_post_deleted") { repository.deletePost(post.id).getOrThrow(); refresh() }
    fun block(post: SocialPost) = mutate("social_person_blocked", SocialMessage.BLOCKED) { repository.block(post.author.id).getOrThrow(); refresh() }
    fun cheerCircle(circle: CircleSummary, recipientId: String, preset: String) = mutate("circle_cheer_sent") { repository.cheerCircle(circle.id, recipientId, preset).getOrThrow() }
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
    fun setEventRsvp(event:SocialEvent,going:Boolean,mode:String="in_person")=mutate("social_event_rsvp_changed"){repository.setEventRsvp(event.id,going,mode).getOrThrow();refresh()}
    fun inviteToEvent(event:SocialEvent,person:SocialPerson?)=mutate("social_event_invitation_sent"){repository.inviteToEvent(event.id,person?.id).getOrThrow()}
    fun connect(person:SocialPerson)=mutate("social_connection_requested"){repository.connect(person.id).getOrThrow();refresh()}
    fun acceptConnection(connectionId:String)=mutate("social_connection_accepted"){repository.accept(connectionId).getOrThrow();refresh()}
    fun removeConnection(connectionId:String)=mutate("social_connection_removed"){repository.removeConnection(connectionId).getOrThrow();refresh()}
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
    fun createCircle(name:String?,members:List<SocialPerson>,timeZone:String?)=mutate("circle_created"){repository.createCircle(name,members.map{it.id},timeZone).getOrThrow().let{created->mutableState.update{it.copy(selectedCircle=created)}};refresh()}
    fun inviteToCircle(circle:CircleSummary,members:List<SocialPerson>,idempotencyKey:String)=mutate("circle_invitation_sent"){repository.inviteToCircle(circle.id,members.map{it.id},idempotencyKey).getOrThrow();openCircle(circle)}
    fun setCircleFocus(circle:CircleSummary,mode:String,target:Int?,nextWeek:Boolean)=mutate("circle_focus_changed"){repository.setCircleFocus(circle.id,mode,target,nextWeek).getOrThrow();openCircle(circle)}
    fun setCircleArchived(circle:CircleSummary,archived:Boolean)=mutate("circle_lifecycle_changed"){repository.setCircleArchived(circle.id,archived).getOrThrow();closeCircle();refresh()}
    fun renameCircle(circle:CircleSummary,name:String)=mutate("circle_renamed"){repository.renameCircle(circle.id,name).getOrThrow().let{updated->mutableState.update{it.copy(selectedCircle=updated)}};refresh()}
    fun setCircleCommitment(circle:CircleSummary,target:Int?,skipped:Boolean)=mutate("circle_personal_target_changed"){repository.setCircleCommitment(circle.id,target,skipped).getOrThrow().let{updated->mutableState.update{it.copy(selectedCircle=updated)}};refresh()}
    fun setPrimaryCircle(circle:CircleSummary)=mutate("circle_primary_changed"){repository.setPrimaryCircle(circle.id).getOrThrow();refresh()}
    fun muteCircle(circle:CircleSummary,muted:Boolean)=mutate("circle_notifications_changed"){repository.muteCircle(circle.id,muted).getOrThrow().let{updated->mutableState.update{it.copy(selectedCircle=updated)}}}
    fun leaveCircle(circle:CircleSummary)=mutate("circle_member_left"){repository.leaveCircle(circle.id).getOrThrow();closeCircle();refresh()}
    fun removeCircleMember(circle:CircleSummary,userId:String)=mutate("circle_member_removed"){repository.removeCircleMember(circle.id,userId).getOrThrow().let{updated->mutableState.update{it.copy(selectedCircle=updated)}};refresh()}
    fun respondToInvitation(invitation:SocialInvitation,accept:Boolean)=mutate("social_invitation_responded"){repository.respondToInvitation(invitation,accept).getOrThrow();closeTarget();refresh()}
    private fun mutate(event: String, success: SocialMessage = SocialMessage.ACTION_COMPLETE, block: suspend () -> Unit) = viewModelScope.launch { runCatching { block() }.onSuccess { messages.emit(success); analytics.record(AnalyticsEvent(event, mapOf(AnalyticsProperty.Result to "success"))) }.onFailure { messages.emit(SocialMessage.ACTION_FAILED); analytics.record(AnalyticsEvent(event, mapOf(AnalyticsProperty.Result to "failure"))) } }

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
