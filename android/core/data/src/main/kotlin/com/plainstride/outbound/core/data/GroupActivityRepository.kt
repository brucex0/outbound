package com.plainstride.outbound.core.data

import android.content.Context
import android.util.Log
import com.plainstride.outbound.core.model.activity.GroupActivityDetail
import com.plainstride.outbound.core.network.*
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString

class GroupActivityRepository(
    context: Context, private val api: ActivitiesApiService,
    private val tokens: AccessTokenProvider, private val account: () -> String?,
) {
    @Serializable private data class Intent(val startedAt: String, val finishedWithoutRecording: Boolean = false)
    private val preferences = context.getSharedPreferences("group_activity_participation", Context.MODE_PRIVATE)
    private val mutex = Mutex()
    private fun read(id: String): Map<String, Intent> = try {
        preferences.getString(id, null)?.let { PlainstrideJson.decodeFromString<Map<String, Intent>>(it) } ?: emptyMap()
    } catch (error: Exception) { Log.e("PlainstrideGroups", "queue_decode type=${error.javaClass.simpleName}"); emptyMap() }
    private fun write(id: String, values: Map<String, Intent>) {
        if (!preferences.edit().putString(id, PlainstrideJson.encodeToString(values)).commit()) Log.e("PlainstrideGroups", "queue_write failed")
    }
    fun enqueueStart(eventId: String, startedAt: String = Instant.now().toString()) {
        val id = account() ?: return
        synchronized(this) { val values = read(id).toMutableMap(); values.putIfAbsent(eventId, Intent(startedAt)); write(id, values) }
    }
    fun enqueueDiscard(eventId: String) {
        val id = account() ?: return
        synchronized(this) { val values = read(id).toMutableMap(); values[eventId] = (values[eventId] ?: Intent(Instant.now().toString())).copy(finishedWithoutRecording = true); write(id, values) }
    }
    suspend fun flush() = mutex.withLock {
        val id = account() ?: return@withLock
        for ((event, intent) in synchronized(this) { read(id) }) {
            if (account() != id) return@withLock
            try {
                val token = tokens.validAccessToken() ?: return@withLock
                if (account() != id) return@withLock
                var response = api.startGroupActivity("Bearer $token", event, GroupActivityStartRequest(intent.startedAt))
                if (response.isSuccessful && intent.finishedWithoutRecording && account() == id) response = api.finishGroupActivityWithoutRecording("Bearer $token", event)
                if (!response.isSuccessful) Log.e("PlainstrideGroups", "participation_sync status=${response.code()}")
                if (response.isSuccessful || response.code() in setOf(403, 404, 410)) synchronized(this) {
                    val latest = read(id).toMutableMap()
                    if (latest[event] == intent) { latest.remove(event); write(id, latest) }
                }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (error: Exception) { Log.e("PlainstrideGroups", "participation_sync type=${error.javaClass.simpleName}") }
        }
    }
    suspend fun detail(eventId: String): GroupActivityDetail? {
        try {
            val token = tokens.validAccessToken() ?: return null
            val response = api.groupActivity("Bearer $token", eventId)
            val body = response.body()
            if (!response.isSuccessful || body == null) Log.e("PlainstrideGroups", "activity_detail status=${response.code()} body_present=${body != null}")
            return body
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) { Log.e("PlainstrideGroups", "activity_detail type=${error.javaClass.simpleName}"); return null }
    }
    fun currentAccountId() = account()
}
