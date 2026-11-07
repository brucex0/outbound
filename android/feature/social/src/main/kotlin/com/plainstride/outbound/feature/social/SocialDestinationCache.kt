package com.plainstride.outbound.feature.social

import android.util.Log
import com.plainstride.outbound.core.database.AccountCacheDao
import com.plainstride.outbound.core.database.AccountCacheEntity
import com.plainstride.outbound.core.network.PlainstrideJson
import kotlinx.coroutines.CancellationException
import javax.inject.Inject

/** Identity-addressed, account-scoped snapshots; a page never needs its caller's selection state. */
class SocialDestinationCache @Inject constructor(private val cache: AccountCacheDao) {
    suspend fun event(account: String, id: String) = read<SocialEvent>(account, "event", id)
    suspend fun group(account: String, id: String, invitation: String?) = read<GroupSummary>(account, "group", groupKey(id, invitation))
    suspend fun post(account: String, id: String) = read<SocialPost>(account, "post", id)
    suspend fun invitation(account: String, id: String) = read<SocialInvitation>(account, "invitation", id)
    suspend fun saveEvent(account: String, value: SocialEvent) = write(account, "event", value.id, PlainstrideJson.encodeToString(value))
    suspend fun saveGroup(account: String, value: GroupSummary, invitation: String?) = write(account, "group", groupKey(value.id, invitation), PlainstrideJson.encodeToString(value))
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
