package run.plainstride.app

import android.app.Application
import android.content.Context
import androidx.datastore.preferences.preferencesDataStore
import run.plainstride.core.analytics.AnalyticsSink
import run.plainstride.core.analytics.ProductAnalytics
import run.plainstride.core.analytics.SanitizedAnalyticsEvent
import run.plainstride.core.model.AppEnvironment
import run.plainstride.core.model.FeatureFlags
import run.plainstride.core.model.StaticFeatureFlags
import run.plainstride.core.model.SystemClock
import run.plainstride.core.database.DataStoreDurableStateStore
import run.plainstride.core.database.DurableStateStore

private val Context.foundationDataStore by preferencesDataStore(name = "plainstride_foundation")

class PlainstrideApplication : Application() {
    val container: AppContainer by lazy {
        DefaultAppContainer(
            environment = if (BuildConfig.DEBUG) {
                AppEnvironment.Development
            } else {
                AppEnvironment.Production
            },
            featureFlags = StaticFeatureFlags(
                debugIdentityEnabled = BuildConfig.DEBUG_IDENTITY_ENABLED,
            ),
            durableStateStore = DataStoreDurableStateStore(foundationDataStore),
        )
    }
}

interface AppContainer {
    val environment: AppEnvironment
    val featureFlags: FeatureFlags
    val analytics: ProductAnalytics
    val durableStateStore: DurableStateStore
}

private class DefaultAppContainer(
    override val environment: AppEnvironment,
    override val featureFlags: FeatureFlags,
    override val durableStateStore: DurableStateStore,
) : AppContainer {
    override val analytics = ProductAnalytics(NoOpAnalyticsSink)

    init {
        check(BuildConfig.DEBUG || !featureFlags.debugIdentityEnabled) {
            "Debug identities must never be enabled in a release build."
        }
        SystemClock.nowEpochMilliseconds()
    }
}

private object NoOpAnalyticsSink : AnalyticsSink {
    override fun record(event: SanitizedAnalyticsEvent) = Unit
}
