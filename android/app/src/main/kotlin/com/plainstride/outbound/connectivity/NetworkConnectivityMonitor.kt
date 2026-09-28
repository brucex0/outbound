package com.plainstride.outbound.connectivity

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

@Singleton
class NetworkConnectivityMonitor @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val manager = context.getSystemService(ConnectivityManager::class.java)
    private val mutableOffline = MutableStateFlow(false)
    val isOffline: StateFlow<Boolean> = mutableOffline.asStateFlow()

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = refresh()
        override fun onLost(network: Network) = refresh()
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = refresh()
    }

    init {
        refresh()
        manager.registerNetworkCallback(
            NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(),
            callback,
        )
    }

    private fun refresh() {
        val network = manager.activeNetwork
        val capabilities = network?.let(manager::getNetworkCapabilities)
        mutableOffline.value = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) != true
    }
}
