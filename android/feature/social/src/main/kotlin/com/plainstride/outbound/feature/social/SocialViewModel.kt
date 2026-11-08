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
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import com.plainstride.outbound.core.analytics.*

data class SocialUiState(
    val destinationLoading: Boolean = false, val destinationFailed: Boolean = false,
    val liveSessions: List<ActiveLiveSession> = emptyList(),
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
    val commentsLoading: Boolean = false,
    val selectedActivityPost: SocialPost? = null,
    val activityDetailPhotos: List<ActivityPhoto> = emptyList(),
    val activityDetailPhotosLoading: Boolean = false,
    val activityDetailPhotoBytes: Map<String, ByteArray> = emptyMap(),
    val selectedEvent:SocialEvent?=null,val selectedInvitation:SocialInvitation?=null,
    val eventCancelling: Boolean = false,
    val feedCursor: String? = null, val feedLoading: Boolean = false,
    val feedLoadFailed: Boolean = false,
    val connectionRequestLoading: Boolean = false,
    val connectionsLoadingMore: Boolean = false,
    val connectionsLoadFailed: Boolean = false,
    val connectionProfileLoading: Boolean = false, val connectionProfileCode: String? = null,
    val connectionProfileIsSelf: Boolean = false,
)
enum class SocialMessage { ACTION_COMPLETE, ACTION_FAILED, REPORTED, BLOCKED, GROUP_CREATED, GROUP_CREATION_FAILED, GROUP_SETTINGS_SAVED, GROUP_SETTINGS_FAILED, GROUP_JOINED, GROUP_MEMBERSHIP_PENDING, GROUP_DECLINED, GROUP_INVITATION_FAILED, EVENT_JOINED, EVENT_LEFT, EVENT_RSVP_FAILED, EVENT_CANCELLATION_FAILED }
enum class ConnectionFeedback { REQUESTED, ALREADY_PENDING, INCOMING_PENDING, ALREADY_CONNECTED, SELF, UPDATED, REQUEST_FAILED, PROFILE_LOAD_FAILED, INVITE_LINK_FAILED }
sealed interface ConnectionEffect {
    data class Feedback(val value: ConnectionFeedback, val closeScanner: Boolean) : ConnectionEffect
    data class ShareInvitation(val url: String) : ConnectionEffect
}

@HiltViewModel class SocialViewModel @Inject constructor(
    private val groups: com.plainstride.outbound.core.data.GroupActivityRepository,
    private val repository: SocialRepository,
    private val destinations: SocialDestinationCache,
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
    private var groupCacheJob: Job? = null
    private var activityPhotoJob: Job? = null
    private var commentsLoadJob: Job? = null
    private var activityFeedLoadTracked = false
    private var feedPagesLoaded = 1
    private var connectionPagesLoaded = 1
    private val connectionRefreshLock = Mutex()

    private var trackHomeExposure = false
    fun start(accountId: String, localeTag: String, trackOpen: Boolean = true) {
        if (trackOpen) analytics.record(AnalyticsEvent("social_opened", mapOf(AnalyticsProperty.Source to "tab")))
        if (this.accountId == accountId && this.localeTag == localeTag) {
            if (trackOpen) {
                trackHomeExposure = true
                if (!activityFeedLoadTracked) trackActivityFeedLoaded(mutableState.value.home.posts)
            }
            return
        }
        trackHomeExposure = trackOpen
        this.accountId = accountId; this.localeTag = localeTag
        groupLoadJob?.cancel()
        groupCacheJob?.cancel()
        mutableState.update { it.copy(liveSessions = emptyList(), selectedGroupId = null, selectedGroupDetail = null, groupLoading = false, groupLoadFailed = false, groupUnavailable = false, groupInvitationResponding = false) }
        groupDirectoryJob?.cancel()
        mutableState.update { it.copy(groupDirectory = emptyList(), groupDirectoryQuery = "", groupDirectoryNextCursor = null, groupDirectoryLoading = false, groupDirectoryFailed = false) }
        activityFeedLoadTracked = false
        feedPagesLoaded = 1
        connectionPagesLoaded = 1
        viewModelScope.launch { repository.observeHome(accountId, localeTag).collect { cached ->
            when (cached) {
                CachedSocialHome.Empty -> Unit
                is CachedSocialHome.Available -> {
                    mutableState.update { state -> state.copy(
                        home = cached.value.copy(posts = cached.value.posts.map { incoming ->
                            val pending = state.home.posts.firstOrNull { it.id == incoming.id && it.id in cheerRequests }
                            if (pending != null) incoming.copy(viewerHasCheered = pending.viewerHasCheered, cheerCount = pending.cheerCount) else incoming
                        }), loading = false, offline = cached.stale,
                        selectedActivityPost = state.selectedActivityPost?.let { selected -> cached.value.posts.firstOrNull { it.id == selected.id && it.id !in cheerRequests } ?: selected },
                        selectedPost = state.selectedPost?.let { selected -> cached.value.posts.firstOrNull { it.id == selected.id && it.id !in cheerRequests } ?: selected },
                    ) }
                    if (trackHomeExposure && !activityFeedLoadTracked) trackActivityFeedLoaded(cached.value.posts)
                }
            }
        } }
        refresh()
    }

    fun retryGroupParticipation() = viewModelScope.launch { groups.flush() }
    fun refresh() { val account = accountId ?: return; viewModelScope.launch {
        groups.flush()
        mutableState.update { it.copy(refreshing = true) }
        connectionRefreshLock.withLock {
            repository.refresh(account, localeTag, mutableState.value.home.let { SocialPage(it.connections, it.connectionNextCursor) })
                .onFailure { logPresenceFailure("feed_refresh", it); mutableState.update { s -> s.copy(offline = true) }; messages.emit(SocialMessage.ACTION_FAILED) }
        }
        refreshLiveSessions()
        mutableState.update { it.copy(refreshing = false, loading = false) }
    } }
    /** Called only while Social is selected and the app is in the foreground. */
    suspend fun refreshActiveNow() = coroutineScope {
        val account = accountId ?: return@coroutineScope
        val connections = async {
            connectionRefreshLock.withLock {
                repository.refreshConnections(account, localeTag, mutableState.value.home.connections.size)
                    .onFailure { logPresenceFailure("connections_refresh", it) }
            }
        }
        val live = async { refreshLiveSessions() }
        connections.await()
        live.await()
    }

    private suspend fun refreshLiveSessions() {
        val account = accountId ?: return
        repository.invitedLiveSessions().onSuccess { sessions ->
            currentCoroutineContext().ensureActive()
            if (accountId == account) mutableState.update { it.copy(liveSessions = sessions.filter { session -> session.status == "active" }) }
        }.onFailure { logPresenceFailure("live_sessions_refresh", it) }
    }

    private suspend fun logPresenceFailure(operation: String, error: Throwable) {
        currentCoroutineContext().ensureActive()
        if (error is CancellationException) throw error
        Log.w("PlainstrideSocial", "$operation failed category=${(error as? SocialException)?.reason ?: error.javaClass.simpleName} status=${(error as? SocialException)?.httpStatus}")
    }

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
        if (current.home.connectionNextCursor == null || current.connectionsLoadingMore) return
        viewModelScope.launch {
            mutableState.update { it.copy(connectionsLoadingMore = true, connectionsLoadFailed = false) }
            connectionRefreshLock.withLock {
                val latestCursor = mutableState.value.home.connectionNextCursor
                if (latestCursor != null) repository.loadConnections(accountId ?: return@withLock, localeTag, latestCursor).onSuccess { page ->
                    connectionPagesLoaded += 1
                    analytics.record(AnalyticsEvent("paginated_list_page_loaded", mapOf(
                        AnalyticsProperty.Source to "connections",
                        AnalyticsProperty.CountBucket to countBucket(page.items.size),
                        AnalyticsProperty.PageDepthBucket to when { connectionPagesLoaded == 2 -> "page_2"; connectionPagesLoaded <= 4 -> "pages_3_4"; else -> "page_5_plus" },
                    )))
                }.onFailure { logPresenceFailure("connections_page_load", it); mutableState.update { it.copy(connectionsLoadFailed = true) } }
            }
            mutableState.update { it.copy(connectionsLoadingMore = false) }
        }
    }
    private val cheerRequests = mutableSetOf<String>()

    /** Feed, activity detail and the comment drawer always receive the same post mutation. */
    private fun updatePost(id: String, transform: (SocialPost) -> SocialPost) {
        mutableState.update { state -> state.copy(
            home = state.home.copy(posts = state.home.posts.map { if (it.id == id) transform(it) else it }),
            selectedActivityPost = state.selectedActivityPost?.let { if (it.id == id) transform(it) else it },
            selectedPost = state.selectedPost?.let { if (it.id == id) transform(it) else it },
        ) }
    }

    private suspend fun persistPost(id: String) {
        val account = accountId ?: return
        val state = mutableState.value
        val post = state.home.posts.firstOrNull { it.id == id }
            ?: state.selectedActivityPost?.takeIf { it.id == id } ?: return
        try {
            repository.cachePost(account, localeTag, post)
            destinations.savePost(account, post)
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            // The server mutation succeeded; a local cache failure must not report it as failed.
            logPresenceFailure("post_cache_write", error)
        }
    }

    fun toggleCheer(post: SocialPost) {
        if (!cheerRequests.add(post.id)) return
        val current = mutableState.value.home.posts.firstOrNull { it.id == post.id }
            ?: mutableState.value.selectedActivityPost?.takeIf { it.id == post.id } ?: post
        val cheered = !current.viewerHasCheered
        updatePost(post.id) { it.copy(viewerHasCheered = cheered, cheerCount = (current.cheerCount + if (cheered) 1 else -1).coerceAtLeast(0)) }
        mutate("social_cheer_toggled") {
            try {
                repository.setCheer(post.id, cheered).getOrElse { error ->
                    updatePost(post.id) { it.copy(viewerHasCheered = current.viewerHasCheered, cheerCount = current.cheerCount) }
                    throw error
                }
                persistPost(post.id)
            } finally { cheerRequests.remove(post.id) }
        }
    }
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
    fun trackActivitySplitsViewed(count: Int) {
        analytics.record(AnalyticsEvent("feature_exposed", mapOf(
            AnalyticsProperty.Feature to "social_activity_recorded_splits",
        )))
        analytics.record(AnalyticsEvent("activity_splits_viewed", mapOf(
            AnalyticsProperty.SourceType to "social_feed",
            AnalyticsProperty.CountBucket to countBucket(count),
        )))
    }
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

    fun trackGroupMomentOpened(type: String) = analytics.record(AnalyticsEvent("group_moment_opened", mapOf(
        AnalyticsProperty.EntrySource to "group_detail",
        AnalyticsProperty.SelectionType to type.takeIf { it in setOf("cheer", "completed_activity", "weekly_completion") }.orEmpty().ifEmpty { "other" },
    )))

    suspend fun loadGroupMomentPhoto(url: String): ByteArray? {
        val path = android.net.Uri.parse(url).pathSegments
        val marker = path.indexOf("activity-photos")
        val photoId = path.getOrNull(marker + 1)
        val representation = path.getOrNull(marker + 2)
        if (marker < 0 || photoId == null || representation !in setOf("thumbnail", "content")) return null
        val result = repository.downloadPostPhoto(photoId, thumbnail = representation == "thumbnail")
        result.exceptionOrNull()?.let { error ->
            if (error is CancellationException) throw error
            Log.w("PlainstrideSocial", "Load moment photo failed (HTTP ${(error as? SocialException)?.httpStatus}, type ${error.javaClass.simpleName})")
        }
        return result.getOrNull()
    }

    suspend fun loadGroupMomentResults(eventId: String): Result<ActivityEventResult> {
        val result = repository.eventResults(eventId)
        result.exceptionOrNull()?.let { error ->
            if (error is CancellationException) throw error
            Log.w("PlainstrideSocial", "Load moment participation results failed (HTTP ${(error as? SocialException)?.httpStatus}, type ${error.javaClass.simpleName})")
        }
        analytics.record(AnalyticsEvent("group_moment_results_loaded", buildMap {
            put(AnalyticsProperty.Result, if (result.isSuccess) "success" else "failure")
            result.getOrNull()?.let { put(AnalyticsProperty.CountBucket, countBucket(it.participants.size)) }
        }))
        return result
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
    suspend fun ensureActivityDetail(postId: String): Boolean {
        if (mutableState.value.selectedActivityPost?.id == postId) return true
        val account = accountId
        val cached = mutableState.value.home.posts.firstOrNull { it.id == postId }
            ?: account?.let { destinations.post(it, postId) }
            ?: cachedHome()?.posts?.firstOrNull { it.id == postId }
        if (cached != null) openActivityDetail(cached)
        // Notifications can refer to posts older than the currently loaded feed.
        var cursor: String? = null
        val visited = mutableSetOf<String?>()
        while (visited.add(cursor)) {
            currentCoroutineContext().ensureActive()
            val result = repository.loadFeed(cursor)
            val page = result.getOrElse { error ->
                if (error is kotlinx.coroutines.CancellationException) throw error
                android.util.Log.w("PlainstrideSocial", "notification_post_load failed category=${(error as? SocialException)?.reason ?: SocialError.UNEXPECTED} status=${(error as? SocialException)?.httpStatus} type=${error.javaClass.simpleName}")
                return cached != null
            }
            page.items.firstOrNull { it.id == postId }?.let {
                if (account != null) destinations.savePost(account, it)
                openActivityDetail(it)
                return true
            }
            cursor = page.nextCursor ?: break
        }
        android.util.Log.i("PlainstrideSocial", "notification_post_load unavailable in visible feed")
        closeActivityDetail()
        return false
    }

    fun openActivityDetail(post: SocialPost) {
        val activity = post.activity ?: return
        val firstOpen = mutableState.value.selectedActivityPost?.id != post.id
        activityPhotoJob?.cancel()
        mutableState.update { state -> state.copy(
            home = state.home.copy(posts = state.home.posts.map { if (it.id == post.id) post else it }),
            selectedActivityPost = post,
            activityDetailPhotos = activity.photos,
            activityDetailPhotosLoading = activity.totalPhotoCount > activity.photos.size,
            activityDetailPhotoBytes = emptyMap(),
        ) }
        if (firstOpen) trackActivityDetailOpened()
        if (firstOpen && activity.recognitions.isNotEmpty()) analytics.record(AnalyticsEvent("activity_recognition_viewed", mapOf(
            AnalyticsProperty.SourceType to "social_feed",
            AnalyticsProperty.CountBucket to countBucket(activity.recognitions.size),
        )))
        if (firstOpen && activity.energyKilocalories != null) analytics.record(AnalyticsEvent("feature_exposed", mapOf(
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
    fun prepareProfile(person: SocialPerson, onReady: () -> Unit) = viewModelScope.launch {
        val account = accountId ?: return@launch
        try {
            repository.cacheProfilePreview(account, person)
            onReady()
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            logGroupFailure("profile_preview_store", error)
            // Cache storage is best effort; the ID-addressed page can still fetch online.
            onReady()
        }
    }
    private suspend fun cachedHome(): SocialHome? = accountId?.let { account ->
        (repository.observeHome(account, localeTag).first() as? CachedSocialHome.Available)?.value
    }

    fun loadProfile(id: String, entrySource: String) = viewModelScope.launch {
        if (mutableState.value.selectedProfile?.id == id) return@launch
        mutableState.update { it.copy(destinationLoading = true, destinationFailed = false) }
        val home = cachedHome() ?: mutableState.value.home
        val cached = home.connections.firstOrNull { it.id == id }
            ?: accountId?.let { repository.cachedProfilePreview(it, id) }
            ?: home.posts.firstOrNull { it.author.id == id }?.author
        if (cached != null) mutableState.update { it.copy(selectedProfile = cached) }
        val result = repository.profile(id)
        result.onSuccess { person ->
            try { accountId?.let { repository.cacheProfilePreview(it, person) } }
            catch (error: Exception) {
                if (error is CancellationException) throw error
                logGroupFailure("profile_preview_store", error)
            }
            mutableState.update { it.copy(selectedProfile = person, destinationLoading = false) }
        }.onFailure {
            if ((it as? SocialException)?.reason in setOf(SocialError.FORBIDDEN, SocialError.NOT_FOUND)) mutableState.update { state -> state.copy(selectedProfile = null) }
            destinationFailure("profile_load", it)
        }
        if (result.isSuccess || cached != null) analytics.record(AnalyticsEvent("social_profile_opened", mapOf(
            AnalyticsProperty.Source to "social", AnalyticsProperty.EntrySource to entrySource,
        )))
    }

    fun loadEvent(id: String, entrySource: String) = viewModelScope.launch {
        if (mutableState.value.selectedEvent?.id == id) return@launch
        eventEntrySource = entrySource
        mutableState.update { it.copy(destinationLoading = true, destinationFailed = false) }
        val account = accountId
        val cached = account?.let { destinations.event(it, id) }
            ?: cachedHome()?.let { home -> (home.upcomingRuns + home.pastEvents).firstOrNull { it.id == id } }
        if (cached != null) mutableState.update { it.copy(selectedEvent = cached) }
        repository.event(id).onSuccess { event ->
            if (account != null) destinations.saveEvent(account, event)
            mutableState.update { it.copy(selectedEvent = event, destinationLoading = false) }
            analytics.record(AnalyticsEvent("activity_event_detail_opened", mapOf(AnalyticsProperty.EntrySource to entrySource)))
        }.onFailure {
            if ((it as? SocialException)?.reason in setOf(SocialError.FORBIDDEN, SocialError.NOT_FOUND)) mutableState.update { state -> state.copy(selectedEvent = null) }
            destinationFailure("event_load", it)
        }
    }

    fun loadInvitation(id: String) = viewModelScope.launch {
        if (mutableState.value.selectedInvitation?.id == id) return@launch
        mutableState.update { it.copy(destinationLoading = true, destinationFailed = false) }
        val account = accountId ?: return@launch
        val initial = destinations.invitation(account, id)
            ?: cachedHome()?.invitations?.firstOrNull { it.id == id || it.objectId == id }
        if (initial != null) mutableState.update { it.copy(selectedInvitation = initial) }
        val refresh = repository.refresh(account, localeTag, SocialPage(emptyList(), null))
        val cached = repository.observeHome(account, localeTag).first()
        val home = (cached as? CachedSocialHome.Available)?.value ?: mutableState.value.home
        val invitation = home.invitations.firstOrNull { it.id == id || it.objectId == id }
        if (invitation == null) {
            if (refresh.isSuccess) mutableState.update { it.copy(selectedInvitation = null) }
            destinationFailure("invitation_load", refresh.exceptionOrNull() ?: SocialException(SocialError.NOT_FOUND))
        } else {
            destinations.saveInvitation(account, invitation)
            mutableState.update { it.copy(selectedInvitation = invitation, destinationLoading = false) }
        }
    }

    fun resolveGroupInvite(token: String, onResolved: (String) -> Unit) = viewModelScope.launch {
        mutableState.update { it.copy(destinationLoading = true, destinationFailed = false) }
        repository.consumeGroupInvite(token).onSuccess { group ->
            accountId?.let { destinations.saveGroup(it, group, null) }
            analytics.record(AnalyticsEvent("group_invite_link_consumed", mapOf(AnalyticsProperty.Result to "success")))
            onResolved(group.id)
        }.onFailure {
            if (it is CancellationException) throw it
            analytics.record(AnalyticsEvent("group_invite_link_consumed", mapOf(AnalyticsProperty.Result to "failure")))
            destinationFailure("group_invite_resolve", it)
        }
    }

    private fun destinationFailure(operation: String, error: Throwable) {
        if (error is CancellationException) throw error
        logGroupFailure(operation, error)
        mutableState.update { it.copy(destinationLoading = false, destinationFailed = true) }
        analytics.record(AnalyticsEvent("social_operation_failed", mapOf(
            AnalyticsProperty.SourceType to operation, AnalyticsProperty.ErrorCategory to "api_unavailable",
        )))
    }
    fun closeTarget() { closeGroup(); mutableState.update { it.copy(selectedEvent = null, selectedInvitation = null) } }
    fun closeEvent()=mutableState.update{it.copy(selectedEvent=null)}
    fun openGroup(group: GroupSummary) = loadGroup(group.id, "groups")

    fun retryGroup() { mutableState.value.selectedGroupId?.let { loadGroup(it, "group_retry", mutableState.value.selectedGroupInvitationId) } }

    fun loadGroup(id: String, entrySource: String, invitationId: String? = null) {
        val targetInvitationId = invitationId ?: if (entrySource == "invitation") mutableState.value.home.invitations.firstOrNull { it.kind == "group" && it.objectId == id }?.id else null
        groupLoadJob?.cancel()
        groupCacheJob?.cancel()
        mutableState.update { it.copy(selectedGroupId = id, selectedGroupInvitationId = targetInvitationId, selectedGroupDetail = null, groupLoading = true, groupLoadFailed = false, groupUnavailable = false) }
        groupLoadJob = viewModelScope.launch {
            val account = accountId
            if (account != null) groupCacheJob = viewModelScope.launch {
                destinations.observeGroup(account, id).collect { group ->
                    if (group != null) mutableState.update { state ->
                        if (state.selectedGroupId == id && !state.groupUnavailable && state.selectedGroupDetail?.invitationPreview == false) state.copy(selectedGroupDetail = group) else state
                    }
                }
            }
            val cached = account?.let { destinations.group(it, id, targetInvitationId) }
                ?: cachedHome()?.groups?.firstOrNull { it.id == id }
            if (cached != null && mutableState.value.selectedGroupId == id) mutableState.update { it.copy(selectedGroupDetail = cached) }
            repository.group(id, targetInvitationId).onSuccess { incoming ->
                val group = if (account != null) destinations.saveGroup(account, incoming, targetInvitationId) else incoming
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
                mutableState.update { it.copy(selectedGroupDetail = if (unavailable) null else it.selectedGroupDetail, groupLoading = false, groupLoadFailed = true, groupUnavailable = unavailable) }
                if (unavailable && account != null) destinations.removeGroup(account, id, targetInvitationId)
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
                if (account != null) {
                    if (accept && joined != null) {
                        destinations.saveGroup(account, joined, invitation.id)
                        destinations.saveGroup(account, joined, null)
                    } else destinations.removeGroup(account, group.id, invitation.id)
                }
                mutableState.update { state ->
                    val pendingInvitation = joined?.takeIf { it.invitationPreview }?.pendingInvitation
                    val invitations = state.home.invitations.filterNot { it.id == invitation.id } +
                        (pendingInvitation?.let { listOf(SocialInvitation(it.id, "group", group.name, it.sender, group.id, it.status)) } ?: emptyList())
                    state.copy(home = state.home.copy(invitations = invitations, groups = if(joined?.invitationPreview == true) state.home.groups.filterNot { it.id == group.id } else state.home.groups))
                }
                if (mutableState.value.selectedGroupId == group.id) {
                    if (accept && joined != null) mutableState.update { it.copy(selectedGroupDetail = joined) }
                    else closeGroup()
                }
                val properties = mutableMapOf<AnalyticsProperty, Any>(AnalyticsProperty.EntrySource to "group_invitation_preview")
                if (accept) properties[AnalyticsProperty.ParticipantCountBucket] = countBucket(joined?.memberCount ?: group.memberCount)
                analytics.record(AnalyticsEvent(if (accept) "group_invitation_accepted" else "group_invitation_declined", properties))
                if (joined?.invitationPreview == true) analytics.record(AnalyticsEvent("group_membership_request_submitted", mapOf(AnalyticsProperty.SourceType to "member_invitation")))
                messages.emit(if (accept && joined?.invitationPreview == true) SocialMessage.GROUP_MEMBERSHIP_PENDING else if (accept) SocialMessage.GROUP_JOINED else SocialMessage.GROUP_DECLINED)
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
        groupCacheJob?.cancel()
        mutableState.update { it.copy(selectedGroupId = null, selectedGroupInvitationId = null, selectedGroupDetail = null, groupLoading = false, groupLoadFailed = false, groupUnavailable = false) }
    }
    /** Refresh after a nested event returns, retaining the current page on transient failure. */
    fun refreshSelectedGroup() = viewModelScope.launch {
        val state = mutableState.value
        val id = state.selectedGroupId ?: return@launch
        val account = accountId ?: return@launch
        runCatching { repository.group(id, state.selectedGroupInvitationId).getOrThrow() }.onSuccess { incoming ->
            val group = destinations.saveGroup(account, incoming, state.selectedGroupInvitationId)
            if (accountId == account && mutableState.value.selectedGroupId == id) mutableState.update { it.copy(selectedGroupDetail = group, groupLoading = false, groupLoadFailed = false, groupUnavailable = false) }
        }.onFailure { error ->
            if (error is CancellationException) throw error
            logGroupFailure("group_return_refresh", error)
            if ((error as? SocialException)?.reason in setOf(SocialError.FORBIDDEN, SocialError.NOT_FOUND)) {
                destinations.removeGroup(account, id, state.selectedGroupInvitationId)
                if (accountId == account && mutableState.value.selectedGroupId == id) mutableState.update { it.copy(selectedGroupDetail = null, groupUnavailable = true, groupLoadFailed = true) }
            }
        }
    }
    fun joinGroup(group: GroupSummary) = mutate("social_group_membership_changed") { repository.setGroupMembership(group.id, group.role == null).getOrThrow(); if(group.role == null && group.joinPolicy == "request") analytics.record(AnalyticsEvent("group_membership_request_submitted",mapOf(AnalyticsProperty.SourceType to "self_join"))); refresh(); refreshGroupDirectory() }
    fun reportPerson(person: SocialPerson, reason: ReportReason, feedback: (Boolean) -> Unit) = mutate("social_content_reported", SocialMessage.REPORTED, feedback) { repository.reportPerson(person.id, reason).getOrThrow() }
    fun report(post: SocialPost, reason: String) = mutate("social_content_reported", SocialMessage.REPORTED) { repository.reportPost(post.id, ReportReason.entries.firstOrNull { it.wireValue == reason } ?: ReportReason.OTHER).getOrThrow() }
    fun deletePost(post: SocialPost) = mutate("social_post_deleted") { repository.deletePost(post.id).getOrThrow(); refresh() }
    fun block(post: SocialPost) = mutate("social_person_blocked", SocialMessage.BLOCKED) { repository.block(post.author.id).getOrThrow(); refresh() }
    fun openComments(post: SocialPost) {
        commentsLoadJob?.cancel()
        mutableState.update { it.copy(selectedPost = post, comments = emptyList(), commentsLoading = true) }
        commentsLoadJob = viewModelScope.launch {
            repository.comments(post.id).onSuccess { comments ->
                mutableState.update { if (it.selectedPost?.id == post.id) it.copy(comments = comments, commentsLoading = false) else it }
            }.onFailure { error ->
                if (error is CancellationException) throw error
                logPresenceFailure("comments_load", error)
                mutableState.update { it.copy(commentsLoading = false) }
                messages.emit(SocialMessage.ACTION_FAILED)
            }
        }
        analytics.record(AnalyticsEvent("social_comments_opened"))
    }
    fun closeComments() {
        commentsLoadJob?.cancel()
        mutableState.update { it.copy(selectedPost = null, comments = emptyList(), commentsLoading = false) }
    }
    fun addComment(body: String, feedback: (Boolean) -> Unit) {
        val post = mutableState.value.selectedPost ?: return
        val clean = body.trim(); if (clean.isEmpty()) return
        mutate("social_comment_created", feedback = feedback, emitFailureMessage = false) {
            val comment = repository.addComment(post.id, clean).getOrThrow()
            updatePost(post.id) { it.copy(commentCount = it.commentCount + 1) }
            mutableState.update { if (it.selectedPost?.id == post.id) it.copy(comments = (it.comments + comment).distinctBy { item -> item.id }) else it }
            persistPost(post.id)
        }
    }
    fun reportComment(comment: SocialComment) = mutate("social_content_reported", SocialMessage.REPORTED) {
        repository.reportComment(comment.id).getOrThrow()
    }
    fun trackSaveRouteExposed() = analytics.record(AnalyticsEvent("feature_exposed", mapOf(AnalyticsProperty.Feature to "save_route")))
    fun deleteComment(comment: SocialComment) {
        val post = mutableState.value.selectedPost ?: return
        val previousIndex = mutableState.value.comments.indexOfFirst { it.id == comment.id }
        if (previousIndex < 0) return
        updatePost(post.id) { it.copy(commentCount = (it.commentCount - 1).coerceAtLeast(0)) }
        mutableState.update { it.copy(comments = it.comments.filterNot { item -> item.id == comment.id }) }
        mutate("social_comment_deleted") {
            repository.deleteComment(comment.id).getOrElse { error ->
                updatePost(post.id) { it.copy(commentCount = it.commentCount + 1) }
                mutableState.update { state ->
                    if (state.selectedPost?.id == post.id && state.comments.none { it.id == comment.id }) {
                        state.copy(comments = state.comments.toMutableList().apply { add(previousIndex.coerceAtMost(size), comment) })
                    } else state
                }
                throw error
            }
            persistPost(post.id)
        }
    }

    fun setEventRsvp(event:SocialEvent,going:Boolean,mode:String="in_person")=mutate("social_event_rsvp_changed", success = if(going) SocialMessage.EVENT_JOINED else SocialMessage.EVENT_LEFT, failure = SocialMessage.EVENT_RSVP_FAILED){val result = repository.setEventRsvp(event.id,going,mode); analytics.record(AnalyticsEvent("activity_event_rsvp_result", mapOf(AnalyticsProperty.EntrySource to eventEntrySource, AnalyticsProperty.SelectionType to if(going) "join" else "leave", AnalyticsProperty.Result to if(result.isSuccess) "success" else "failure"))); result.getOrThrow();repository.event(event.id).onSuccess{updated->mutableState.update{it.copy(selectedEvent=updated)}};refresh()}
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
        if (mutableState.value.connectionProfileLoading ||
            (mutableState.value.connectionProfileCode == code && mutableState.value.selectedProfile != null)) return
        mutableState.update { it.copy(connectionProfileLoading = true, destinationLoading = true, destinationFailed = false, selectedProfile = null, connectionProfileCode = null, connectionProfileIsSelf = false) }
        viewModelScope.launch {
            val account = accountId ?: return@launch
            destinations.connection(account, code)?.let { preview ->
                mutableState.update { it.copy(selectedProfile = preview.person, connectionProfileCode = code, connectionProfileIsSelf = preview.isSelf) }
            }
            repository.connectionLinkPreview(code).fold(
                onSuccess = { preview ->
                    destinations.saveConnection(account, code, preview)
                    mutableState.update { it.copy(
                        connectionProfileLoading = false, destinationLoading = false,
                        selectedProfile = preview.person,
                        connectionProfileCode = code,
                        connectionProfileIsSelf = preview.isSelf,
                    ) }
                    analytics.record(AnalyticsEvent("social_profile_opened", mapOf(AnalyticsProperty.EntrySource to "connection_qr_code")))
                },
                onFailure = { error ->
                    if ((error as? SocialException)?.reason in setOf(SocialError.FORBIDDEN, SocialError.NOT_FOUND)) {
                        destinations.remove(account, "connection", code)
                        mutableState.update { it.copy(selectedProfile = null, connectionProfileCode = null) }
                    }
                    mutableState.update { it.copy(connectionProfileLoading = false) }
                    destinationFailure("connection_profile_load", error)
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
    fun trackGroupInvitePickerOpened() = analytics.record(AnalyticsEvent("feature_exposed", mapOf(
        AnalyticsProperty.Feature to "group_invite_picker",
    )))
    fun inviteToGroup(group:GroupSummary,members:List<SocialPerson>,idempotencyKey:String)=mutate("group_invitation_sent"){repository.inviteToGroup(group.id,members.map{it.id},idempotencyKey).getOrThrow();openGroup(group)}
    fun setGroupFocus(group:GroupSummary,mode:String,target:Int?,nextWeek:Boolean)=mutate("group_focus_changed"){repository.setGroupFocus(group.id,mode,target,nextWeek).getOrThrow();openGroup(group)}
    fun trackGroupActivityMapOpened() = analytics.record(AnalyticsEvent("feature_exposed", mapOf(AnalyticsProperty.Feature to "activity_event_location_picker")))

    fun trackGroupActivityLocation(source: String) = analytics.record(AnalyticsEvent("activity_event_location_selected", mapOf(AnalyticsProperty.SourceType to source)))
    fun createGroupActivity(group: GroupSummary, body: CreateEventBody, completed: (Boolean) -> Unit) = mutate("group_activity_created", feedback = completed) {
        repository.createEvent(body.copy(groupId = group.id)).getOrThrow()
        if (body.recurrence != null) analytics.record(AnalyticsEvent("activity_event_recurrence_configured", mapOf(AnalyticsProperty.SelectionType to "weekly", AnalyticsProperty.SourceType to "group_activity")))
        openGroup(group)
    }
    fun saveMembershipPolicy(group:GroupSummary,joinPolicy:String,approvalRequired:Boolean,memberInvitesAllowed:Boolean,completed:(Boolean)->Unit)=mutate("group_membership_policy_changed", feedback=completed, properties=mapOf(AnalyticsProperty.SourceType to joinPolicy, AnalyticsProperty.SelectionType to if(approvalRequired) "approval_required" else "direct", AnalyticsProperty.ChangeType to if(memberInvitesAllowed) "member_invites_on" else "member_invites_off")) {
        val updated=repository.updateGroupMembershipPolicy(group.id,joinPolicy,approvalRequired,memberInvitesAllowed).getOrThrow()
        mutableState.update { if(it.selectedGroupId==group.id) it.copy(selectedGroupDetail=updated) else it }
        refresh()
    }
    fun reviewMembership(group:GroupSummary,requestId:String,approve:Boolean,completed:(Boolean)->Unit)=mutate("group_membership_request_reviewed", feedback=completed, properties=mapOf(AnalyticsProperty.SourceType to if(approve) "approve" else "deny")) {
        val updated=repository.reviewGroupMembership(group.id,requestId,approve).getOrThrow()
        mutableState.update { if(it.selectedGroupId==group.id) it.copy(selectedGroupDetail=updated) else it }
        refresh()
    }
    fun updatePlannedEvent(event:SocialEvent,body:CreateEventBody,completed:(Boolean)->Unit)=mutate("activity_event_series_changed", feedback=completed, properties=mapOf(AnalyticsProperty.SelectionType to body.scope)) {
        val updated=repository.updateEvent(event.id,body).getOrThrow()
        mutableState.update { if(it.selectedEvent?.id==event.id) it.copy(selectedEvent=updated) else it }
        refresh()
    }
    fun cancelPlannedEvent(event: SocialEvent, scope: String, completed: (Boolean) -> Unit) {
        if (mutableState.value.eventCancelling) return
        val account = accountId ?: return
        mutableState.update { it.copy(eventCancelling = true) }
        viewModelScope.launch {
            try {
                val result = runCatching { repository.cancelEvent(event.id, scope).getOrThrow() }
                result.exceptionOrNull()?.let { if (it is CancellationException) throw it }
                val properties = mapOf(AnalyticsProperty.EntrySource to eventEntrySource, AnalyticsProperty.GroupRunEnabled to (event.group != null), AnalyticsProperty.Result to if (result.isSuccess) "success" else "failure")
                analytics.record(AnalyticsEvent("activity_event_cancellation_result", properties))
                if (event.seriesId != null) analytics.record(AnalyticsEvent("activity_event_series_changed", mapOf(AnalyticsProperty.SelectionType to scope, AnalyticsProperty.Result to if (result.isSuccess) "success" else "failure")))
                val updated = result.getOrElse { error ->
                    if (error is CancellationException) throw error
                    logGroupFailure("cancel_planned_event", error)
                    messages.emit(SocialMessage.EVENT_CANCELLATION_FAILED)
                    completed(false)
                    return@launch
                }
                destinations.recordCancellation(account, updated)
                try { repository.removeCancelledEvent(account, localeTag, event.id) }
                catch (error: Exception) {
                    if (error is CancellationException) throw error
                    logGroupFailure("cancel_event_home_cache", error)
                }
                mutableState.update { if (it.selectedEvent?.id == event.id) it.copy(selectedEvent = updated) else it }
                // Returning Group pages refresh the canonical list, including all edited
                // recurrence segments. A refresh failure must never undo cancellation or
                // keep this detail open after the server has accepted the mutation.
                refresh()
                completed(true)
            } finally {
                mutableState.update { it.copy(eventCancelling = false) }
            }
        }
    }
    fun setGroupArchived(group:GroupSummary,archived:Boolean)=mutate("group_lifecycle_changed"){repository.setGroupArchived(group.id,archived).getOrThrow().let{updated->mutableState.update{it.copy(selectedGroupDetail=updated)}};refresh()}
    fun renameGroup(group:GroupSummary,name:String)=mutate("group_renamed"){repository.renameGroup(group.id,name).getOrThrow().let{updated->mutableState.update{it.copy(selectedGroupDetail=updated)}};refresh()}
    fun saveGroupSettings(group:GroupSummary,name:String,city:String,resetWeekday:Int,timeZone:String,apply:String,muted:Boolean,applyChanged:Boolean,allowMembersToPlan:Boolean)=viewModelScope.launch {
        runCatching {
            var updated = group
            val detailsChanged = name.trim() != group.name || city.trim() != group.city.orEmpty()
            val memberActivityCreationChanged = allowMembersToPlan != group.memberActivityCreation
            if (detailsChanged || memberActivityCreationChanged) {
                val detailsUpdate = repository.updateGroupDetails(group.id, name, city, allowMembersToPlan.takeIf { memberActivityCreationChanged })
                if (memberActivityCreationChanged && detailsUpdate.isFailure) analytics.record(AnalyticsEvent("group_membership_policy_changed", mapOf(
                    AnalyticsProperty.SourceType to "group_settings",
                    AnalyticsProperty.SelectionType to if (allowMembersToPlan) "enabled" else "disabled",
                    AnalyticsProperty.ChangeType to "member_activity_creation",
                    AnalyticsProperty.Result to "failure",
                )))
                updated = detailsUpdate.getOrThrow()
                if (name.trim() != group.name) analytics.record(AnalyticsEvent("group_name_changed"))
                if (city.trim() != group.city.orEmpty()) analytics.record(AnalyticsEvent("group_location_changed"))
                if (memberActivityCreationChanged) {
                    analytics.record(AnalyticsEvent("group_membership_policy_changed", mapOf(
                        AnalyticsProperty.SourceType to "group_settings",
                        AnalyticsProperty.SelectionType to if (allowMembersToPlan) "enabled" else "disabled",
                        AnalyticsProperty.ChangeType to "member_activity_creation",
                        AnalyticsProperty.Result to "success",
                    )))
                }
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
    fun respondToInvitation(invitation:SocialInvitation,accept:Boolean,feedback:((Boolean)->Unit)?=null)=mutate("social_invitation_responded",feedback=feedback){repository.respondToInvitation(invitation,accept).getOrThrow();closeTarget();refresh()}
    private var eventEntrySource = "social_upcoming"
    private fun mutate(
        event: String,
        success: SocialMessage = SocialMessage.ACTION_COMPLETE,
        feedback: ((Boolean) -> Unit)? = null,
        failure: SocialMessage = SocialMessage.ACTION_FAILED,
        emitFailureMessage: Boolean = true,
        properties: Map<AnalyticsProperty, Any> = emptyMap(),
        block: suspend () -> Unit,
    ) = viewModelScope.launch {
        runCatching { block() }.onSuccess {
            feedback?.invoke(true)
            messages.emit(success)
            analytics.record(AnalyticsEvent(event, properties + (AnalyticsProperty.Result to "success")))
        }.onFailure { error ->
            if (error is CancellationException) throw error
            val socialError = error as? SocialException
            Log.w("SocialViewModel", "$event failed (type=${error.javaClass.simpleName}, status=${socialError?.httpStatus}, reason=${socialError?.reason})")
            feedback?.invoke(false)
            if (emitFailureMessage) messages.emit(failure)
            analytics.record(AnalyticsEvent(event, properties + (AnalyticsProperty.Result to "failure")))
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
