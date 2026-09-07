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
import run.plainstride.core.database.AccountCacheDao
import run.plainstride.core.database.PlainstrideDatabase
import run.plainstride.core.database.PlainstrideDatabaseFactory
import run.plainstride.core.data.ActivityMediaStore
import run.plainstride.core.data.ActivityRepository
import run.plainstride.core.data.OfflineFirstActivityRepository
import run.plainstride.core.data.ActivitySyncScheduler
import run.plainstride.app.sync.WorkManagerActivitySyncScheduler
import run.plainstride.core.model.AndroidMonotonicClock
import run.plainstride.core.model.AppEnvironment
import run.plainstride.core.model.EpochClock
import run.plainstride.core.model.FeatureFlags
import run.plainstride.core.model.MonotonicClock
import run.plainstride.core.model.StaticFeatureFlags
import run.plainstride.core.model.SystemEpochClock
import javax.inject.Singleton
import androidx.credentials.CredentialManager
import okhttp3.OkHttpClient
import run.plainstride.app.auth.GoogleServerClientId
import run.plainstride.core.auth.ApiSessionRefresher
import run.plainstride.core.auth.AuthRepository
import run.plainstride.core.auth.DefaultAuthRepository
import run.plainstride.core.auth.DefaultSessionCoordinator
import run.plainstride.core.auth.KeystoreSecureSessionStore
import run.plainstride.core.auth.SecureSessionStore
import run.plainstride.core.auth.SessionCoordinator
import run.plainstride.core.auth.SessionRefresher
import run.plainstride.core.network.AuthApiService
import run.plainstride.core.network.AccessTokenProvider
import run.plainstride.core.network.AccountApiService
import run.plainstride.core.network.PlanningApiService
import run.plainstride.core.network.ActivitiesApiService
import run.plainstride.core.network.createAccountApi
import run.plainstride.core.network.createAuthApi
import run.plainstride.core.network.createPlanningApi
import run.plainstride.core.network.createActivitiesApi
import com.google.android.gms.location.LocationServices
import run.plainstride.core.weather.DefaultWeatherRepository
import run.plainstride.core.weather.FusedWeatherLocationSource
import run.plainstride.core.weather.WeatherApiService
import run.plainstride.core.weather.WeatherLocationSource
import run.plainstride.core.weather.WeatherRepository
import run.plainstride.core.weather.createWeatherApi

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

    @Provides @Singleton fun database(@ApplicationContext context: Context): PlainstrideDatabase =
        PlainstrideDatabaseFactory.create(context)

    @Provides fun accountCacheDao(database: PlainstrideDatabase): AccountCacheDao =
        database.accountCacheDao()

    @Provides
    @Singleton
    fun analytics(): ProductAnalytics = ProductAnalytics(NoOpAnalyticsSink)

    @Provides @Singleton fun credentialManager(@ApplicationContext context: Context): CredentialManager =
        CredentialManager.create(context)

    @Provides @GoogleServerClientId fun googleServerClientId(): String = BuildConfig.GOOGLE_SERVER_CLIENT_ID

    @Provides @Singleton fun httpClient(): OkHttpClient = OkHttpClient.Builder()
        .retryOnConnectionFailure(true)
        .build()

    @Provides @Singleton fun authApi(client: OkHttpClient): AuthApiService =
        createAuthApi(BuildConfig.API_BASE_URL, client)

    @Provides @Singleton fun accountApi(client: OkHttpClient): AccountApiService =
        createAccountApi(BuildConfig.API_BASE_URL, client)

    @Provides @Singleton fun planningApi(client: OkHttpClient): PlanningApiService =
        createPlanningApi(BuildConfig.API_BASE_URL, client)

    @Provides @Singleton fun activitiesApi(client: OkHttpClient): ActivitiesApiService =
        createActivitiesApi(BuildConfig.API_BASE_URL, client)

    @Provides @Singleton fun activityMediaStore(@ApplicationContext context: Context): ActivityMediaStore =
        ActivityMediaStore(context)

    @Provides @Singleton fun activitySyncScheduler(@ApplicationContext context: Context): ActivitySyncScheduler =
        WorkManagerActivitySyncScheduler(context)

    @Provides @Singleton fun activityRepository(
        database: PlainstrideDatabase,
        api: ActivitiesApiService,
        accessTokens: AccessTokenProvider,
    ): ActivityRepository = OfflineFirstActivityRepository(database, api, accessTokens)

    @Provides @Singleton fun weatherApi(client: OkHttpClient): WeatherApiService =
        createWeatherApi(BuildConfig.API_BASE_URL, client)

    @Provides @Singleton fun weatherLocationSource(@ApplicationContext context: Context): WeatherLocationSource =
        FusedWeatherLocationSource(context, LocationServices.getFusedLocationProviderClient(context))

    @Provides @Singleton fun weatherRepository(
        locationSource: WeatherLocationSource,
        api: WeatherApiService,
        accessTokens: AccessTokenProvider,
        dataStore: DataStore<Preferences>,
        analytics: ProductAnalytics,
    ): WeatherRepository = DefaultWeatherRepository(locationSource, api, accessTokens, dataStore, analytics)

    @Provides @Singleton fun secureSessionStore(@ApplicationContext context: Context): SecureSessionStore =
        KeystoreSecureSessionStore(context)

    @Provides @Singleton fun sessionRefresher(api: AuthApiService): SessionRefresher = ApiSessionRefresher(api)

    @Provides @Singleton fun sessionCoordinator(
        store: SecureSessionStore,
        refresher: SessionRefresher,
        clock: EpochClock,
    ): SessionCoordinator = DefaultSessionCoordinator(store, refresher, clock)

    @Provides fun accessTokenProvider(sessions: SessionCoordinator): AccessTokenProvider =
        object : AccessTokenProvider {
            override suspend fun validAccessToken(): String? = sessions.validAccessToken()
        }

    @Provides @Singleton fun authRepository(api: AuthApiService, sessions: SessionCoordinator): AuthRepository =
        DefaultAuthRepository(api, sessions)

    @Provides
    fun epochClock(): EpochClock = SystemEpochClock

    @Provides
    fun monotonicClock(): MonotonicClock = AndroidMonotonicClock
}

private object NoOpAnalyticsSink : AnalyticsSink {
    override fun record(event: SanitizedAnalyticsEvent) = Unit
}
