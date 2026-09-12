package com.plainstride.outbound.feature.social

import javax.inject.Inject
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import com.plainstride.outbound.core.database.AccountCacheDao
import com.plainstride.outbound.core.database.AccountCacheEntity
import com.plainstride.outbound.core.network.*

sealed interface CachedSocialHome {
    data object Empty : CachedSocialHome
    data class Available(val value: SocialHome, val stale: Boolean) : CachedSocialHome
}

interface SocialRepository {
    fun observeHome(accountId: String, localeTag: String): Flow<CachedSocialHome>
    suspend fun refresh(accountId: String, localeTag: String): Result<Unit>
    suspend fun loadFeed(cursor: String?): Result<SocialPage<SocialPost>>
    suspend fun loadConnections(cursor: String?): Result<SocialPage<SocialPerson>>
    suspend fun searchPeople(query: String): Result<List<SocialPerson>>
    suspend fun profile(id: String): Result<SocialPerson>
    suspend fun setCheer(postId: String, cheered: Boolean): Result<Unit>
    suspend fun connect(personId: String): Result<Unit>
    suspend fun accept(connectionId: String): Result<Unit>
    suspend fun removeConnection(connectionId: String): Result<Unit>
    suspend fun setGroupMembership(groupId: String, joined: Boolean): Result<Unit>
    suspend fun reportPost(postId: String, reason: ReportReason): Result<Unit>
    suspend fun deletePost(postId: String): Result<Unit>
    suspend fun block(personId: String): Result<Unit>
    suspend fun blockedAccounts(): Result<List<BlockedAccount>>
    suspend fun unblock(personId: String): Result<Unit>
    suspend fun connectionQr(): Result<ConnectionQrContent>
    suspend fun referralLink(): Result<ConnectionLink>
    suspend fun connectionLinkPreview(code: String): Result<ConnectionLinkPreview>
    suspend fun consumeConnectionLink(code: String): Result<ConnectionLinkResult>
    suspend fun circles(): Result<List<CircleSummary>>
    suspend fun circle(id: String): Result<CircleSummary>
    suspend fun cheerCircle(id: String, recipientId: String, preset: String): Result<Unit>
    suspend fun renameCircle(id:String,name:String):Result<CircleSummary>
    suspend fun setCircleCommitment(id:String,target:Int?,skipped:Boolean):Result<CircleSummary>
    suspend fun setPrimaryCircle(id:String):Result<CircleSummary>
    suspend fun muteCircle(id:String,muted:Boolean):Result<CircleSummary>
    suspend fun leaveCircle(id:String):Result<Unit>
    suspend fun removeCircleMember(id:String,userId:String):Result<CircleSummary>
    suspend fun awards(): Result<List<RecognitionAward>>
    suspend fun comments(postId:String):Result<List<SocialComment>>
    suspend fun addComment(postId:String,body:String):Result<SocialComment>
    suspend fun deleteComment(commentId:String):Result<Unit>
    suspend fun setEventRsvp(eventId:String,going:Boolean,attendanceMode:String="in_person"):Result<Unit>
    suspend fun inviteToEvent(eventId:String,personId:String?):Result<EventInvitation>
    suspend fun createCircle(name:String?,memberIds:List<String>,timeZone:String?=null):Result<CircleSummary>
    suspend fun inviteToCircle(circleId:String,memberIds:List<String>,idempotencyKey:String):Result<CircleSummary>
    suspend fun setCircleFocus(circleId:String,mode:String,target:Int?,applyNextWeek:Boolean):Result<CircleSummary>
    suspend fun setCircleArchived(circleId:String,archived:Boolean):Result<CircleSummary>
    suspend fun event(id:String):Result<SocialEvent>
    suspend fun createEvent(body:CreateEventBody):Result<SocialEvent>
    suspend fun eventResults(id:String):Result<ActivityEventResult>
    suspend fun linkActivity(eventId:String,activityId:String):Result<Unit>
    suspend fun markEventWithoutRecording(eventId:String):Result<Unit>
    suspend fun setWorkoutPresence(clientSessionId:String,active:Boolean):Result<Unit>
    suspend fun respondToInvitation(invitation:SocialInvitation,accept:Boolean):Result<Unit>
}

class OfflineFirstSocialRepository @Inject constructor(
    private val api: SocialApiService,
    private val accounts: AccountApiService,
    private val tokens: AccessTokenProvider,
    private val cache: AccountCacheDao,
) : SocialRepository {
    private val mutex = Mutex()

    override fun observeHome(accountId: String, localeTag: String) = cache.observe(accountId, NAMESPACE, HOME, localeTag).map { entity ->
        val value = entity?.payloadJson?.let { runCatching { PlainstrideJson.decodeFromString<SocialHome>(it) }.getOrNull() }
        if (value == null) CachedSocialHome.Empty else CachedSocialHome.Available(value, entity.expiresAtEpochMs?.let { it <= System.currentTimeMillis() } == true)
    }

    override suspend fun refresh(accountId: String, localeTag: String) = mutex.withLock {
        authenticated { auth -> coroutineScope {
            val home = async { apiCall { api.home(auth) } }
            val connections = async { apiCall { api.connections(auth, null) } }
            val circles = async { apiCall { api.circles(auth) } }
            val awards = async { apiCall { api.awards(auth) } }
            val circleInvitations = async { apiCall { api.circleInvitations(auth) } }
            when (val core = home.await()) {
                is ApiResult.Failure -> core
                is ApiResult.Success -> {
                    val circleResult = circles.await()
                    ApiResult.Success(core.value.copy(
                    connections = (connections.await() as? ApiResult.Success)?.value?.connections.orEmpty().map { it.person.copy(relationshipDetails = SocialRelationship(it.id, it.status, it.direction), relationship = it.status, isActive = it.isInActiveWorkout, connectionId = it.id, connectionDirection=it.direction) },
                    invitations = (core.value.invitations + (circleInvitations.await() as? ApiResult.Success)?.value?.invitations.orEmpty().map { SocialInvitation(it.id,"circle",it.circle.name,it.sender,it.circle.id) }).distinctBy(SocialInvitation::id),
                    recognitions = (awards.await() as? ApiResult.Success)?.value?.awards.orEmpty(),
                    circles = (circleResult as? ApiResult.Success)?.value?.let { response -> response.circles.map { circle -> circle.copy(primary = circle.id == response.primaryCircleId) }.sortedByDescending { it.primary } }.orEmpty(),
                )) }
            }
        } }.onSuccess { home ->
            val now = System.currentTimeMillis()
            cache.upsert(AccountCacheEntity(accountId, NAMESPACE, HOME, localeTag, PlainstrideJson.encodeToString(home), null, now, now + CACHE_TTL))
        }.map { Unit }
    }

    override suspend fun loadFeed(cursor: String?) = authenticated { apiCall { api.feed(it, cursor) } }.map { SocialPage(it.posts, it.nextCursor) }
    override suspend fun loadConnections(cursor: String?) = authenticated { apiCall { api.connections(it, cursor) } }.map { response -> SocialPage(response.connections.map { it.person.copy(relationshipDetails = SocialRelationship(it.id, it.status, it.direction), relationship = it.status, isActive = it.isInActiveWorkout, connectionId = it.id, connectionDirection=it.direction) }, response.nextCursor) }
    override suspend fun searchPeople(query: String) = authenticated { apiCall { api.search(it, query.trim()) } }.map { it.people }
    override suspend fun profile(id: String) = authenticated { apiCall { api.profile(it, id) } }.map { it.person.copy(recognitions = it.recognitions) }
    override suspend fun setCheer(postId: String, cheered: Boolean) = authenticated { auth -> apiCall { if (cheered) api.cheer(auth, postId) else api.removeCheer(auth, postId) } }
    override suspend fun connect(personId: String) = authenticated { apiCall { api.connect(it, IdBody(personId)) } }
    override suspend fun accept(connectionId: String) = authenticated { apiCall { api.accept(it, connectionId) } }
    override suspend fun removeConnection(connectionId: String) = authenticated { apiCall { api.removeConnection(it, connectionId) } }
    override suspend fun setGroupMembership(groupId: String, joined: Boolean) = authenticated { auth -> apiCall { if (joined) api.joinGroup(auth, groupId) else api.leaveGroup(auth, groupId) } }
    override suspend fun reportPost(postId: String, reason: ReportReason) = authenticated { apiCall { api.reportPost(it, ReportBody("post", postId, reason.wireValue)) } }
    override suspend fun deletePost(postId: String) = authenticated { apiCall { api.deletePost(it, postId) } }
    override suspend fun block(personId: String) = authenticated { apiCall { api.block(it, personId) } }
    override suspend fun blockedAccounts() = authenticated { apiCall { api.blocks(it) } }.map { it.blocks }
    override suspend fun unblock(personId: String) = authenticated { apiCall { api.unblock(it, personId) } }
    override suspend fun connectionQr() = authenticated { auth -> coroutineScope {
        val accountRequest = async { apiCall { accounts.currentAccount(auth) } }
        val linkRequest = async { apiCall { api.connectionLink(auth) } }
        when (val account = accountRequest.await()) {
            is ApiResult.Failure -> account
            is ApiResult.Success -> when (val link = linkRequest.await()) {
                is ApiResult.Failure -> link
                is ApiResult.Success -> ApiResult.Success(ConnectionQrContent(
                    owner = SocialPerson(
                        id = account.value.id,
                        displayName = account.value.displayName?.takeIf(String::isNotBlank)
                            ?: account.value.username?.takeIf(String::isNotBlank)
                            ?: "Plainstride",
                        username = account.value.username,
                        avatarUrl = account.value.avatarUrl,
                    ),
                    link = link.value,
                ))
            }
        }
    } }
    override suspend fun referralLink() = authenticated { apiCall { api.referralLink(it) } }
    override suspend fun connectionLinkPreview(code: String) = authenticated { apiCall { api.connectionLinkPreview(it, code) } }
        .map { preview -> preview.copy(person = preview.person.withRelationship()) }
    override suspend fun consumeConnectionLink(code: String) = authenticated { apiCall { api.consumeConnectionLink(it, code) } }
        .map { response -> response.copy(person = response.person.withRelationship(response.relationship)) }
    override suspend fun circles() = authenticated { apiCall { api.circles(it) } }.map { it.circles }
    override suspend fun circle(id: String) = authenticated { apiCall { api.circle(it, id) } }
    override suspend fun cheerCircle(id: String, recipientId: String, preset: String) = authenticated { apiCall { api.circleCheer(it, id, CheerBody(recipientId, preset)) } }
    override suspend fun renameCircle(id:String,name:String)=authenticated{apiCall{api.renameCircle(it,id,RenameCircleBody(name.trim()))}}
    override suspend fun setCircleCommitment(id:String,target:Int?,skipped:Boolean)=authenticated{apiCall{api.circleCommitment(it,id,CircleCommitmentBody(target,skipped))}}
    override suspend fun setPrimaryCircle(id:String)=authenticated{apiCall{api.primaryCircle(it,id)}}.map{it.circle}
    override suspend fun muteCircle(id:String,muted:Boolean)=authenticated{apiCall{api.muteCircle(it,id,CircleMuteBody(muted))}}
    override suspend fun leaveCircle(id:String)=authenticated{apiCall{api.leaveCircle(it,id)}}
    override suspend fun removeCircleMember(id:String,userId:String)=authenticated{apiCall{api.removeCircleMember(it,id,userId)}}
    override suspend fun awards() = authenticated { apiCall { api.awards(it) } }.map { it.awards }
    override suspend fun comments(postId:String)=authenticated{apiCall{api.comments(it,postId)}}.map{it.comments}
    override suspend fun addComment(postId:String,body:String):Result<SocialComment>{val clean=body.trim();if(clean.isEmpty()||clean.length>500)return Result.failure(SocialException(SocialError.INVALID_RESPONSE));return authenticated{apiCall{api.comment(it,postId,CommentBody(clean))}}}
    override suspend fun deleteComment(commentId:String)=authenticated{apiCall{api.deleteComment(it,commentId)}}
    override suspend fun setEventRsvp(eventId:String,going:Boolean,attendanceMode:String)=authenticated{auth->apiCall{if(going)api.rsvp(auth,eventId,AttendanceBody(attendanceMode))else api.leaveEvent(auth,eventId)}}
    override suspend fun inviteToEvent(eventId:String,personId:String?)=authenticated{apiCall{api.inviteEvent(it,eventId,EventInviteBody(personId))}}
    override suspend fun createCircle(name:String?,memberIds:List<String>,timeZone:String?)=authenticated{apiCall{api.createCircle(it,CreateCircleBody(name?.trim()?.takeIf(String::isNotEmpty),memberIds.distinct(),timeZone))}}
    override suspend fun inviteToCircle(circleId:String,memberIds:List<String>,idempotencyKey:String)=authenticated{apiCall{api.inviteCircle(it,circleId,CircleInviteBody(memberIds.distinct(),idempotencyKey))}}.map{it.circle}
    override suspend fun setCircleFocus(circleId:String,mode:String,target:Int?,applyNextWeek:Boolean)=authenticated{apiCall{api.focusCircle(it,circleId,CircleFocusBody(mode,target,if(applyNextWeek)"next_week" else "now"))}}
    override suspend fun setCircleArchived(circleId:String,archived:Boolean)=authenticated{auth->apiCall{if(archived)api.archiveCircle(auth,circleId)else api.reactivateCircle(auth,circleId)}}
    override suspend fun event(id:String)=authenticated{apiCall{api.event(it,id)}}
    override suspend fun createEvent(body:CreateEventBody)=authenticated{apiCall{api.createEvent(it,body)}}
    override suspend fun eventResults(id:String)=authenticated{apiCall{api.eventResults(it,id)}}
    override suspend fun linkActivity(eventId:String,activityId:String)=authenticated{apiCall{api.linkActivity(it,eventId,LinkActivityBody(activityId))}}
    override suspend fun markEventWithoutRecording(eventId:String)=authenticated{apiCall{api.noRecording(it,eventId)}}
    override suspend fun setWorkoutPresence(clientSessionId:String,active:Boolean)=authenticated{auth->apiCall{if(active)api.setPresence(auth,PresenceBody(clientSessionId))else api.clearPresence(auth,clientSessionId)}}
    override suspend fun respondToInvitation(invitation:SocialInvitation,accept:Boolean)=authenticated{auth->when{
        invitation.kind=="circle"&&accept->apiCall{api.acceptCircleInvitation(auth,invitation.id)}.map{Unit}
        invitation.kind=="circle"->apiCall{api.declineCircleInvitation(auth,invitation.id)}
        accept->apiCall{api.acceptEventInvitation(auth,invitation.id)}
        else->apiCall{api.declineEventInvitation(auth,invitation.id)}
    }}

    private suspend fun <T : Any> authenticated(call: suspend (String) -> ApiResult<T>): Result<T> {
        val token = tokens.validAccessToken() ?: return Result.failure(SocialException(SocialError.SIGNED_OUT))
        return when (val response = call("Bearer $token")) {
            is ApiResult.Success -> Result.success(response.value)
            is ApiResult.Failure -> Result.failure(SocialException(response.error.toSocialError()))
        }
    }

    private fun SocialPerson.withRelationship(value: SocialRelationship? = relationshipDetails) = copy(
        relationshipDetails = value,
        relationship = value?.status ?: "none",
        connectionId = value?.id,
        connectionDirection = value?.direction,
    )

    private companion object { const val NAMESPACE = "social.home"; const val HOME = "current"; const val CACHE_TTL = 5 * 60_000L }
}

private fun ApiFailure.toSocialError() = when (code) {
    ApiErrorCode.Unauthenticated -> SocialError.SIGNED_OUT
    ApiErrorCode.NetworkUnavailable -> SocialError.OFFLINE
    ApiErrorCode.Forbidden -> SocialError.FORBIDDEN
    ApiErrorCode.NotFound -> SocialError.NOT_FOUND
    ApiErrorCode.Conflict -> SocialError.CONFLICT
    ApiErrorCode.RateLimited -> SocialError.RATE_LIMITED
    ApiErrorCode.ServerUnavailable -> SocialError.SERVER
    ApiErrorCode.InvalidRequest, ApiErrorCode.InvalidResponse -> SocialError.INVALID_RESPONSE
    ApiErrorCode.Cancelled, ApiErrorCode.Unknown -> SocialError.UNEXPECTED
}
