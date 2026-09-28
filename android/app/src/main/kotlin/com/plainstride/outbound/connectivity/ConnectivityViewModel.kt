package com.plainstride.outbound.connectivity

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.plainstride.outbound.core.data.ActivityRepository
import com.plainstride.outbound.core.data.ActivitySyncScheduler
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class ConnectivityUiState(
    val isOffline: Boolean = false,
    val pendingSyncCount: Int = 0,
)

@HiltViewModel
class ConnectivityViewModel @Inject constructor(
    monitor: NetworkConnectivityMonitor,
    private val activities: ActivityRepository,
    private val syncScheduler: ActivitySyncScheduler,
) : ViewModel() {
    private val mutableState = MutableStateFlow(ConnectivityUiState())
    val state = mutableState.asStateFlow()
    private var accountId: String? = null
    private var pendingSyncJob: Job? = null

    init {
        viewModelScope.launch {
            var wasOffline = false
            monitor.isOffline.collect { isOffline ->
                mutableState.update { it.copy(isOffline = isOffline) }
                if (wasOffline && !isOffline) accountId?.let(syncScheduler::schedule)
                wasOffline = isOffline
            }
        }
    }

    fun start(accountId: String) {
        if (this.accountId == accountId) return
        this.accountId = accountId
        pendingSyncJob?.cancel()
        mutableState.update { it.copy(pendingSyncCount = 0) }
        pendingSyncJob = viewModelScope.launch {
            activities.observePendingSyncCount(accountId).collectLatest { count ->
                mutableState.update { it.copy(pendingSyncCount = count) }
            }
        }
    }
}
