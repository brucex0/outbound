package com.plainstride.outbound.core.data

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable data class AccountStretchEntry(val movementID: String, val seconds: Int)
@Serializable data class AccountLaunchPreference(
    val preferredGoalModeRawValue: String? = null,
    val goalModeStartHistory: List<String> = emptyList(),
    val distanceMeters: Double? = null,
    val timeSeconds: Int? = null,
    val calories: Int? = null,
)
@Serializable data class AccountConfigurationValue(
    val selection: String? = null,
    val launch: AccountLaunchPreference? = null,
    val entries: List<AccountStretchEntry>? = null,
)
@Serializable data class AccountConfigurationRecord(val key: String, val revision: Int, val value: AccountConfigurationValue? = null)
@Serializable data class AccountConfigurationResponse(val records: List<AccountConfigurationRecord>)
@Serializable data class AccountConfigurationMutation(val key: String, val expectedRevision: Int, val value: AccountConfigurationValue?)
@Serializable data class AccountConfigurationMutationResponse(val record: AccountConfigurationRecord)

/** Shared by recording, stretching and Today. All values and pending writes belong to one account. */
object AccountConfigurationStore {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; explicitNulls = false }
    @Serializable private data class Cache(
        val records: Map<String, AccountConfigurationRecord> = emptyMap(),
        val pending: Map<String, AccountConfigurationRecord> = emptyMap(),
    )
    private var preferences: SharedPreferences? = null
    private var cache = Cache()
    @Volatile var accountId: String? = null
        private set
    private val mutableChanges = MutableStateFlow(0L)
    val changes = mutableChanges.asStateFlow()
    private val mutableRequests = MutableStateFlow(0L)
    val requests = mutableRequests.asStateFlow()
    @Synchronized fun activate(context: Context, id: String?) {
        val next = context.getSharedPreferences("account_configuration_v1_" + (id ?: "guest"), Context.MODE_PRIVATE)
        if (preferences != null && accountId == id) return
        accountId = id
        preferences = next
        cache = try { next.getString("cache", null)?.let { json.decodeFromString<Cache>(it) } ?: Cache() }
        catch (error: Exception) { Log.e("AccountConfiguration", "cache_decode type=${error.javaClass.simpleName}"); Cache() }
        mutableChanges.value += 1
    }
    @Synchronized fun record(key: String): AccountConfigurationRecord? = cache.pending[key] ?: cache.records[key]
    @Synchronized fun set(key: String, value: AccountConfigurationValue?): Boolean {
        val old = record(key)
        if (old != null && old.value == value) return true
        return save(cache.copy(pending = cache.pending + (key to AccountConfigurationRecord(key, old?.revision ?: 0, value)))).also { if (it) mutableRequests.value += 1 }
    }
    @Synchronized fun pending(id: String): List<AccountConfigurationRecord> = if (accountId == id) cache.pending.values.toList() else emptyList()
    @Synchronized fun merge(id: String, records: List<AccountConfigurationRecord>) {
        if (accountId == id) save(cache.copy(records = records.associateBy { it.key }))
    }
    @Synchronized fun accepted(id: String, sent: AccountConfigurationRecord, accepted: AccountConfigurationRecord) {
        if (accountId != id) return
        val pending = cache.pending.toMutableMap()
        if (pending[sent.key] == sent) pending.remove(sent.key)
        else pending[sent.key]?.let { pending[sent.key] = it.copy(revision = accepted.revision) }
        save(cache.copy(records = cache.records + (sent.key to accepted), pending = pending))
    }
    private fun save(next: Cache): Boolean {
        val preferences = preferences ?: return false
        val success = preferences.edit().putString("cache", json.encodeToString(next)).commit()
        if (success) { cache = next; mutableChanges.value += 1 }
        else Log.e("AccountConfiguration", "cache_write failed")
        return success
    }
}
