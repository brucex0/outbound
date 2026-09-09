package com.plainstride.outbound.analytics

import android.content.Context
import android.os.Bundle
import com.google.firebase.analytics.FirebaseAnalytics
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import com.plainstride.outbound.core.analytics.AnalyticsSink
import com.plainstride.outbound.core.analytics.SanitizedAnalyticsEvent

/** Receives only events already sanitized by ProductAnalytics. */
@Singleton
class FirebaseAnalyticsSink @Inject constructor(
    @param:ApplicationContext context: Context,
) : AnalyticsSink {
    private val firebase = runCatching { FirebaseAnalytics.getInstance(context) }.getOrNull()

    override fun setUserId(userId: String?) {
        firebase?.setAnalyticsCollectionEnabled(false)
        firebase?.setUserId(userId)
        if (userId != null) firebase?.setAnalyticsCollectionEnabled(true)
    }

    override fun record(event: SanitizedAnalyticsEvent) {
        val parameters = Bundle().apply {
            event.properties.forEach { (key, value) ->
                when (value) {
                    is String -> putString(key, value)
                    is Int -> putLong(key, value.toLong())
                    is Long -> putLong(key, value)
                    is Boolean -> putLong(key, if (value) 1 else 0)
                }
            }
        }
        firebase?.logEvent(event.name, parameters)
    }
}
