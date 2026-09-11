package com.plainstride.outbound.subscriptions

import android.content.Context
import android.util.Log
import com.plainstride.outbound.BuildConfig
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.interfaces.ReceiveCustomerInfoCallback
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.logInWith
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

@Singleton
class RevenueCatCoordinator @Inject constructor(
    @param:ApplicationContext private val context: Context,
) : UpdatedCustomerInfoListener {
    private val mutableReady = MutableStateFlow(false)
    val ready: StateFlow<Boolean> = mutableReady
    private val mutableHasProEntitlement = MutableStateFlow(false)
    val hasProEntitlement: StateFlow<Boolean> = mutableHasProEntitlement
    private var configuredUserId: String? = null

    fun activate(userId: String?) {
        if (userId.isNullOrBlank() || BuildConfig.REVENUECAT_PUBLIC_SDK_KEY.isBlank()) {
            mutableReady.value = false
            mutableHasProEntitlement.value = false
            return
        }
        if (configuredUserId == null) {
            runCatching {
                if (BuildConfig.DEBUG) Purchases.logLevel = LogLevel.DEBUG
                Purchases.configure(
                    PurchasesConfiguration.Builder(context, BuildConfig.REVENUECAT_PUBLIC_SDK_KEY)
                        .appUserID(userId)
                        .build(),
                )
                Purchases.sharedInstance.updatedCustomerInfoListener = this
                configuredUserId = userId
                mutableReady.value = true
                refreshCustomerInfo()
            }.onFailure {
                mutableReady.value = false
                Log.w(TAG, "RevenueCat configuration failed: type=${it::class.simpleName}")
            }
            return
        }
        if (configuredUserId == userId) {
            mutableReady.value = true
            refreshCustomerInfo()
            return
        }
        mutableReady.value = false
        mutableHasProEntitlement.value = false
        Purchases.sharedInstance.logInWith(
            appUserID = userId,
            onError = {
                Log.w(TAG, "RevenueCat identity switch failed: code=${it.code}")
            },
            onSuccess = { customerInfo, _ ->
                configuredUserId = userId
                onReceived(customerInfo)
                mutableReady.value = true
            },
        )
    }

    override fun onReceived(customerInfo: CustomerInfo) {
        mutableHasProEntitlement.value = customerInfo.entitlements[PRO_ENTITLEMENT]?.isActive == true
    }

    private fun refreshCustomerInfo() {
        Purchases.sharedInstance.getCustomerInfo(object : ReceiveCustomerInfoCallback {
            override fun onReceived(customerInfo: CustomerInfo) = this@RevenueCatCoordinator.onReceived(customerInfo)

            override fun onError(error: PurchasesError) {
                Log.w(TAG, "RevenueCat customer info refresh failed: code=${error.code}")
            }
        })
    }

    private companion object {
        const val TAG = "PlainstridePurchases"
        const val PRO_ENTITLEMENT = "plainstride_pro"
    }
}
