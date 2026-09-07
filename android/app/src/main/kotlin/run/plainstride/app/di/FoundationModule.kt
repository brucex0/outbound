package run.plainstride.app.di

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStoreFile
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import run.plainstride.app.BuildConfig
import run.plainstride.core.analytics.AnalyticsSink
import run.plainstride.core.analytics.ProductAnalytics
import run.plainstride.core.analytics.SanitizedAnalyticsEvent
import run.plainstride.core.database.DataStoreDurableStateStore
import run.plainstride.core.database.DurableStateStore
import run.plainstride.core.model.AndroidMonotonicClock
import run.plainstride.core.model.AppEnvironment
import run.plainstride.core.model.EpochClock
import run.plainstride.core.model.FeatureFlags
import run.plainstride.core.model.MonotonicClock
import run.plainstride.core.model.StaticFeatureFlags
import run.plainstride.core.model.SystemEpochClock
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object FoundationModule {
    @Provides
    @Singleton
    fun environment(): AppEnvironment =
        if (BuildConfig.DEBUG) AppEnvironment.Development else AppEnvironment.Production

    @Provides
    @Singleton
    fun featureFlags(): FeatureFlags = StaticFeatureFlags(
        debugIdentityEnabled = BuildConfig.DEBUG_IDENTITY_ENABLED,
    ).also { flags ->
        check(BuildConfig.DEBUG || !flags.debugIdentityEnabled) {
            "Debug identities must never be enabled in a release build."
        }
    }

    @Provides
    @Singleton
    fun foundationDataStore(@ApplicationContext context: Context): DataStore<Preferences> =
        PreferenceDataStoreFactory.create {
            context.preferencesDataStoreFile("plainstride_foundation")
        }

    @Provides
    @Singleton
    fun durableStateStore(dataStore: DataStore<Preferences>): DurableStateStore =
        DataStoreDurableStateStore(dataStore)

    @Provides
    @Singleton
    fun analytics(): ProductAnalytics = ProductAnalytics(NoOpAnalyticsSink)

    @Provides
    fun epochClock(): EpochClock = SystemEpochClock

    @Provides
    fun monotonicClock(): MonotonicClock = AndroidMonotonicClock
}

private object NoOpAnalyticsSink : AnalyticsSink {
    override fun record(event: SanitizedAnalyticsEvent) = Unit
}
