package com.plainstride.outbound.feature.social

import android.util.Log
import com.plainstride.outbound.core.database.AccountCacheDao
import com.plainstride.outbound.core.database.AccountCacheEntity
import com.plainstride.outbound.core.network.PlainstrideJson
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.distinctUntilChanged
import javax.inject.Inject
import javax.inject.Singleton

/** Identity-addressed, account-scoped snapshots; a page never needs its caller's selection state. */
@Singleton
class SocialDestinationCache @Inject constructor(private val cache: AccountCacheDao) {
    private val cancelledEvents = mutableMapOf<String, MutableSet<String>>()
    suspend fun event(account: String, id: String) = read<SocialEvent>(account, "event", id)
    suspend fun group(account: String, id: String, invitation: String?) = read<GroupSummary>(account, "group", groupKey(id, invitation))
    fun observeGroup(account: String, id: String) = cache.observe(account, namespace("group"), groupKey(id, null), "und").distinctUntilChanged().map { row ->
        row?.let { decodeGroup(it.payloadJson) }
    }.catch { error ->
        if (error is CancellationException) throw error
        Log.w("PlainstrideSocial", "group_cache_observe failed type=${error.javaClass.simpleName}")
        emit(null)
    }
    suspend fun post(account: String, id: String) = read<SocialPost>(account, "post", id)
    suspend fun invitation(account: String, id: String) = read<SocialInvitation>(account, "invitation", id)
    suspend fun saveEvent(account: String, value: SocialEvent) = write(account, "event", value.id, PlainstrideJson.encodeToString(value))
    suspend fun saveGroup(account: String, value: GroupSummary, invitation: String?): GroupSummary {
        val visible = value.copy(upcomingActivities = value.upcomingActivities.filterNot { it.id in cancelledEvents[account].orEmpty() || it.status == "cancelled" })
        write(account, "group", groupKey(value.id, invitation), PlainstrideJson.encodeToString(visible))
        if (invitation != null && !visible.invitationPreview) write(account, "group", groupKey(value.id, null), PlainstrideJson.encodeToString(visible))
        return visible
    }
    /** Reconcile every cached invitation-context copy before returning to its owning Group page. */
    suspend fun recordCancellation(account: String, event: SocialEvent) {
        cancelledEvents.getOrPut(account) { mutableSetOf() }.add(event.id)
        saveEvent(account, event)
        try {
            cache.entries(account, namespace("group")).forEach { row ->
                val group = decodeGroup(row.payloadJson) ?: return@forEach
                if (group.upcomingActivities.any { it.id == event.id }) {
                    val updated = group.copy(upcomingActivities = group.upcomingActivities.filterNot { it.id == event.id || it.status == "cancelled" })
                    cache.upsert(row.copy(payloadJson = PlainstrideJson.encodeToString(updated), updatedAtEpochMs = System.currentTimeMillis()))
                }
            }
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            Log.w("PlainstrideSocial", "cancel_event_group_cache failed type=${error.javaClass.simpleName}")
        }
    }
    private fun decodeGroup(payload: String): GroupSummary? = try { PlainstrideJson.decodeFromString<GroupSummary>(payload) }
    catch (error: Exception) {
        Log.w("PlainstrideSocial", "group_cache_decode failed type=${error.javaClass.simpleName}")
        null
    }
    suspend fun savePost(account: String, value: SocialPost) = write(account, "post", value.id, PlainstrideJson.encodeToString(value))
    suspend fun saveInvitation(account: String, value: SocialInvitation) = write(account, "invitation", value.id, PlainstrideJson.encodeToString(value))
    suspend fun connection(account: String, code: String) = read<ConnectionLinkPreview>(account, "connection", code)
    suspend fun saveConnection(account: String, code: String, value: ConnectionLinkPreview) = write(account, "connection", code, PlainstrideJson.encodeToString(value))
    suspend fun remove(account: String, kind: String, id: String) = cache.delete(account, namespace(kind), id, "und")
    suspend fun removeGroup(account: String, id: String, invitation: String?) {
        try {
            cache.delete(account, namespace("group"), groupKey(id, invitation), "und")
            cache.delete(account, namespace("group"), groupKey(id, null), "und")
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            // The server decision is canonical. A cache failure must not turn
            // successful withdrawal into a failed network action or a crash.
            Log.w("PlainstrideSocial", "group_cache_remove failed type=${error.javaClass.simpleName}")
        }
    }
    private fun namespace(kind: String) = if (kind in setOf("group", "event", "invitation")) "social.detail.$kind.v2" else "social.detail.$kind"
    private fun groupKey(id: String, invitation: String?) = "$id:${invitation.orEmpty()}"
    private suspend inline fun <reified T> read(account: String, kind: String, id: String): T? = try {
        cache.get(account, namespace(kind), id, "und")?.let { PlainstrideJson.decodeFromString<T>(it.payloadJson) }
    } catch (error: Exception) {
        if (error is CancellationException) throw error
        Log.w("PlainstrideSocial", "${kind}_cache_read failed type=${error.javaClass.simpleName}")
        null
    }
    private suspend fun write(account: String, kind: String, id: String, payload: String) {
        try { cache.upsert(AccountCacheEntity(account, namespace(kind), id, "und", payload, null, System.currentTimeMillis(), null)) }
        catch (error: Exception) {
            if (error is CancellationException) throw error
            Log.w("PlainstrideSocial", "${kind}_cache_write failed type=${error.javaClass.simpleName}")
        }
    }
}
