package com.plainstride.outbound

import android.util.Log
import androidx.compose.runtime.*
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.plainstride.outbound.core.database.AccountCacheDao
import com.plainstride.outbound.core.database.AccountCacheEntity
import com.plainstride.outbound.core.network.PlainstrideJson
import com.plainstride.outbound.feature.safety.*
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class NotificationDestinationViewModel @Inject constructor(
    private val cache: AccountCacheDao,
    private val live: LiveShareCoordinator,
    private val analytics: com.plainstride.outbound.core.analytics.ProductAnalytics,
) : ViewModel() {
    private val mutable = MutableStateFlow<InboxNotification?>(null)
    val notification = mutable.asStateFlow()
    private val mutableLoading = MutableStateFlow(true)
    val loading = mutableLoading.asStateFlow()
    fun load(account: String, id: String) = viewModelScope.launch {
        mutableLoading.value = true
        try {
            mutable.value = cache.get(account, "inbox.detail", id, "und")?.let {
                PlainstrideJson.decodeFromString<InboxNotification>(it.payloadJson)
            }
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            Log.w("PlainstrideInbox", "notification_cache_read failed type=${error.javaClass.simpleName}")
        }
        live.inbox().onSuccess { response ->
            mutable.value = response.notifications.firstOrNull { it.id == id }
            try {
                val value = mutable.value
                if (value == null) cache.delete(account, "inbox.detail", id, "und")
                else cache.upsert(AccountCacheEntity(account, "inbox.detail", id, "und", PlainstrideJson.encodeToString(value), null, System.currentTimeMillis(), null))
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                Log.w("PlainstrideInbox", "notification_cache_write failed type=${error.javaClass.simpleName}")
            }
        }.onFailure { error ->
            if (error is CancellationException) throw error
            Log.w("PlainstrideInbox", "notification_load failed type=${error.javaClass.simpleName}")
        }
        analytics.record(com.plainstride.outbound.core.analytics.AnalyticsEvent("notification_detail_loaded", mapOf(
            com.plainstride.outbound.core.analytics.AnalyticsProperty.Result to if(mutable.value!=null) "success" else "failure",
        )))
        mutableLoading.value = false
    }
}

@Composable
fun NotificationDestination(accountId: String, id: String, onBack: () -> Unit, viewModel: NotificationDestinationViewModel = hiltViewModel()) {
    val notification by viewModel.notification.collectAsStateWithLifecycle()
    val loading by viewModel.loading.collectAsStateWithLifecycle()
    LaunchedEffect(accountId, id) { viewModel.load(accountId, id) }
    Column(Modifier.fillMaxSize()) {
        IconButton(onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(com.plainstride.outbound.feature.social.R.string.social_back)) }
        Box(Modifier.weight(1f)) {
            if (notification != null) NotificationDetail(notification)
            else Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center) {
                if (loading) CircularProgressIndicator()
                else {
                    Text(stringResource(com.plainstride.outbound.feature.social.R.string.social_destination_unavailable))
                    TextButton({ viewModel.load(accountId, id) }) { Text(stringResource(com.plainstride.outbound.feature.social.R.string.social_destination_retry)) }
                }
            }
        }
    }
}
