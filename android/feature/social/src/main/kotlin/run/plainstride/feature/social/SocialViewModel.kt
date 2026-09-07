package run.plainstride.feature.social

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import java.text.Normalizer
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import run.plainstride.core.analytics.*

data class SocialUiState(
    val home: SocialHome = SocialHome(), val loading: Boolean = true, val refreshing: Boolean = false,
    val offline: Boolean = false, val search: String = "", val searchResults: List<SocialPerson> = emptyList(),
    val selectedProfile: SocialPerson? = null, val selectedCircle: CircleSummary? = null,
    val selectedPost:SocialPost?=null,val comments:List<SocialComment> = emptyList(),
    val feedCursor: String? = null, val feedLoading: Boolean = false,
)
enum class SocialMessage { ACTION_COMPLETE, ACTION_FAILED, REPORTED, BLOCKED }

@HiltViewModel class SocialViewModel @Inject constructor(
    private val repository: SocialRepository,
    private val analytics: ProductAnalytics,
) : ViewModel() {
    private val mutableState = MutableStateFlow(SocialUiState())
    val state = mutableState.asStateFlow()
    val messages = MutableSharedFlow<SocialMessage>(extraBufferCapacity = 4)
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
    fun openProfile(person: SocialPerson) { mutableState.update { it.copy(selectedProfile = person) }; analytics.record(AnalyticsEvent("social_profile_opened", mapOf(AnalyticsProperty.Source to "social"))) }
    fun closeProfile() = mutableState.update { it.copy(selectedProfile = null) }
    fun openCircle(circle: CircleSummary) = viewModelScope.launch { repository.circle(circle.id).onSuccess { value -> mutableState.update { it.copy(selectedCircle = value) } } }
    fun closeCircle() = mutableState.update { it.copy(selectedCircle = null) }
    fun joinGroup(group: SocialGroup) = mutate("social_group_membership_changed") { repository.setGroupMembership(group.id, !group.joined).getOrThrow(); refresh() }
    fun report(post: SocialPost, reason: String) = mutate("social_content_reported", SocialMessage.REPORTED) { repository.reportPost(post.id, ReportReason.entries.firstOrNull { it.wireValue == reason } ?: ReportReason.OTHER).getOrThrow() }
    fun block(post: SocialPost) = mutate("social_person_blocked", SocialMessage.BLOCKED) { repository.block(post.author.id).getOrThrow(); refresh() }
    fun cheerCircle(circle: CircleSummary, recipientId: String, preset: String) = mutate("circle_cheer_sent") { repository.cheerCircle(circle.id, recipientId, preset).getOrThrow() }
    fun openComments(post:SocialPost)=viewModelScope.launch{repository.comments(post.id).onSuccess{comments->mutableState.update{it.copy(selectedPost=post,comments=comments)}};analytics.record(AnalyticsEvent("social_comments_opened"))}
    fun closeComments()=mutableState.update{it.copy(selectedPost=null,comments=emptyList())}
    fun addComment(body:String){val post=mutableState.value.selectedPost?:return;mutate("social_comment_created"){repository.addComment(post.id,body).getOrThrow();openComments(post)}}
    fun deleteComment(comment:SocialComment){val post=mutableState.value.selectedPost?:return;mutate("social_comment_deleted"){repository.deleteComment(comment.id).getOrThrow();openComments(post)}}
    fun setEventRsvp(event:SocialEvent,going:Boolean,mode:String="in_person")=mutate("social_event_rsvp_changed"){repository.setEventRsvp(event.id,going,mode).getOrThrow();refresh()}
    fun inviteToEvent(event:SocialEvent,person:SocialPerson?)=mutate("social_event_invitation_sent"){repository.inviteToEvent(event.id,person?.id).getOrThrow()}
    fun connect(person:SocialPerson)=mutate("social_connection_requested"){repository.connect(person.id).getOrThrow();refresh()}
    fun acceptConnection(connectionId:String)=mutate("social_connection_accepted"){repository.accept(connectionId).getOrThrow();refresh()}
    fun removeConnection(connectionId:String)=mutate("social_connection_removed"){repository.removeConnection(connectionId).getOrThrow();refresh()}
    fun createCircle(name:String?,members:List<SocialPerson>,timeZone:String?)=mutate("circle_created"){repository.createCircle(name,members.map{it.id},timeZone).getOrThrow();refresh()}
    fun inviteToCircle(circle:CircleSummary,members:List<SocialPerson>,idempotencyKey:String)=mutate("circle_invitation_sent"){repository.inviteToCircle(circle.id,members.map{it.id},idempotencyKey).getOrThrow();openCircle(circle)}
    fun setCircleFocus(circle:CircleSummary,mode:String,target:Int?,nextWeek:Boolean)=mutate("circle_focus_changed"){repository.setCircleFocus(circle.id,mode,target,nextWeek).getOrThrow();openCircle(circle)}
    fun setCircleArchived(circle:CircleSummary,archived:Boolean)=mutate("circle_lifecycle_changed"){repository.setCircleArchived(circle.id,archived).getOrThrow();closeCircle();refresh()}
    private fun mutate(event: String, success: SocialMessage = SocialMessage.ACTION_COMPLETE, block: suspend () -> Unit) = viewModelScope.launch { runCatching { block() }.onSuccess { messages.emit(success); analytics.record(AnalyticsEvent(event, mapOf(AnalyticsProperty.Result to "success"))) }.onFailure { messages.emit(SocialMessage.ACTION_FAILED); analytics.record(AnalyticsEvent(event, mapOf(AnalyticsProperty.Result to "failure"))) } }
}
