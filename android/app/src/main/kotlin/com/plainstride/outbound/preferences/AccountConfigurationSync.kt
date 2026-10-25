package com.plainstride.outbound.preferences

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.util.Log
import com.plainstride.outbound.core.auth.SessionCoordinator
import com.plainstride.outbound.core.auth.SessionState
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.data.*
import com.plainstride.outbound.core.network.AccountApiService
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.sync.Mutex
import kotlinx.serialization.json.*

@Singleton
class AccountConfigurationSync @Inject constructor(
    @ApplicationContext private val context: Context,
    private val sessions: SessionCoordinator,
    private val api: AccountApiService,
    private val analytics: ProductAnalytics,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val mutex = Mutex()
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; explicitNulls = false }
    fun start() {
        AccountConfigurationStore.activate(context, null)
        scope.launch {
            sessions.state.collectLatest { state ->
                val id = when (state) {
                    is SessionState.SignedIn -> state.accountId
                    is SessionState.Refreshing -> state.accountId
                    SessionState.Loading -> return@collectLatest
                    SessionState.SignedOut -> null
                }
                if (sessions.state.value != state) return@collectLatest
                AccountConfigurationStore.activate(context, id)
                refresh()
            }
        }
        scope.launch {
            AccountConfigurationStore.requests.collectLatest {
                delay(600)
                if (AccountConfigurationStore.accountId?.let { AccountConfigurationStore.pending(it).isNotEmpty() } == true) refresh()
            }
        }
        context.getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) { refresh() }
        })
    }
    fun refresh() { scope.launch { synchronize() } }
    private fun isCurrent(id: String): Boolean {
        val sessionId = when (val state = sessions.state.value) {
            is SessionState.SignedIn -> state.accountId
            is SessionState.Refreshing -> state.accountId
            else -> null
        }
        return AccountConfigurationStore.accountId == id && sessionId == id
    }
    private fun trackResult(result: String) {
        analytics.record(AnalyticsEvent("preference_changed", mapOf(
            AnalyticsProperty.ChangeType to "account_configuration_sync",
            AnalyticsProperty.SelectionType to result,
        )))
    }
    private suspend fun synchronize() {
        if (!mutex.tryLock()) return
        try {
            val id = AccountConfigurationStore.accountId ?: return
            if (!isCurrent(id)) return
            val token = sessions.validAccessToken() ?: return
            if (!isCurrent(id)) return
            val response = api.configuration("Bearer $token")
            if (!response.isSuccessful) { Log.w("AccountConfiguration", "fetch status=${response.code()}"); trackResult("failed"); return }
            val remote = json.decodeFromJsonElement<AccountConfigurationResponse>(response.body() ?: error("missing configuration body"))
            if (!isCurrent(id)) return
            AccountConfigurationStore.merge(id, remote.records)
            for (change in AccountConfigurationStore.pending(id)) {
                if (!isCurrent(id)) return
                // Explicit null is required for reset; omit null members within values.
                val body = buildJsonObject {
                    put("key", change.key); put("expectedRevision", change.revision)
                    put("value", change.value?.let { json.encodeToJsonElement(it) } ?: JsonNull)
                }
                val result = api.updateConfiguration("Bearer $token", body)
                if (!result.isSuccessful && result.code() != 409) {
                    Log.w("AccountConfiguration", "patch status=${result.code()}"); trackResult("failed"); return
                }
                val payload = if (result.code() == 409) {
                    Log.i("AccountConfiguration", "patch conflict status=409 server_value_retained")
                    json.parseToJsonElement(result.errorBody()?.string() ?: error("missing conflict body"))
                } else result.body() ?: error("missing mutation body")
                val accepted = json.decodeFromJsonElement<AccountConfigurationMutationResponse>(payload).record
                if (!isCurrent(id)) return
                AccountConfigurationStore.accepted(id, change, accepted)
                trackResult(if (result.code() == 409) "conflict" else "saved")
            }
            if (AccountConfigurationStore.pending(id).isNotEmpty()) scope.launch { delay(1_000); refresh() }
        } catch (error: CancellationException) { throw error }
        catch (error: Exception) {
            Log.e("AccountConfiguration", "sync_failed type=${error.javaClass.simpleName}")
            trackResult("failed")
        } finally { mutex.unlock() }
    }
}
