package com.plainstride.outbound.connectivity

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.util.Log
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

    // Default-network callbacks are ordered on ConnectivityManager's callback thread.
    // Synchronous activeNetwork reads can still describe the previous default
    // during handover, leaving the UI stuck with that transient result.
    private var defaultNetwork: Network? = null
    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            defaultNetwork = network
            updateOffline(false)
        }

        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
            if (network == defaultNetwork) {
                updateOffline(!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET))
            }
        }

        override fun onLost(network: Network) {
            if (network == defaultNetwork) {
                defaultNetwork = null
                updateOffline(true)
            }
        }
    }

    init {
        // Seed before registering; subsequent state comes only from callbacks.
        val network = manager.activeNetwork
        val capabilities = network?.let(manager::getNetworkCapabilities)
        updateOffline(capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) != true)
        manager.registerDefaultNetworkCallback(callback)
    }

    private fun updateOffline(offline: Boolean) {
        if (mutableOffline.value != offline) {
            Log.d("PlainstrideConnectivity", "Default network connectivity changed: offline=$offline")
            mutableOffline.value = offline
        }
    }
}
