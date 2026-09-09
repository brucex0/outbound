package com.plainstride.outbound.di

import android.content.Context
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStoreFile
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import com.plainstride.outbound.BuildConfig
import com.plainstride.outbound.core.analytics.AnalyticsSink
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.analytics.SanitizedAnalyticsEvent
import com.plainstride.outbound.core.database.DataStoreDurableStateStore
import com.plainstride.outbound.core.database.DurableStateStore
import com.plainstride.outbound.core.database.AccountCacheDao
import com.plainstride.outbound.core.database.AccountDatabaseOperations
import com.plainstride.outbound.core.database.PlainstrideDatabase
import com.plainstride.outbound.core.database.PlainstrideDatabaseFactory
import com.plainstride.outbound.core.data.ActivityMediaStore
import com.plainstride.outbound.core.data.ActivityRepository
import com.plainstride.outbound.core.data.OfflineFirstActivityRepository
import com.plainstride.outbound.core.data.ActivitySyncScheduler
import com.plainstride.outbound.sync.WorkManagerActivitySyncScheduler
import com.plainstride.outbound.core.model.AndroidMonotonicClock
import com.plainstride.outbound.core.model.AppEnvironment
import com.plainstride.outbound.core.model.EpochClock
import com.plainstride.outbound.core.model.FeatureFlags
import com.plainstride.outbound.core.model.MonotonicClock
import com.plainstride.outbound.core.model.StaticFeatureFlags
import com.plainstride.outbound.core.model.SystemEpochClock
import javax.inject.Singleton
import androidx.credentials.CredentialManager
import okhttp3.OkHttpClient
import com.plainstride.outbound.feature.livecoach.network.LiveCoachApi
import com.plainstride.outbound.feature.livecoach.network.createLiveCoachApi
import com.plainstride.outbound.auth.GoogleServerClientId
import com.plainstride.outbound.core.auth.ApiSessionRefresher
import com.plainstride.outbound.core.auth.AuthRepository
import com.plainstride.outbound.core.auth.DefaultAuthRepository
import com.plainstride.outbound.core.auth.DefaultSessionCoordinator
import com.plainstride.outbound.core.auth.KeystoreSecureSessionStore
import com.plainstride.outbound.core.auth.SecureSessionStore
import com.plainstride.outbound.core.auth.SessionCoordinator
import com.plainstride.outbound.core.auth.SessionRefresher
import com.plainstride.outbound.core.network.AuthApiService
import com.plainstride.outbound.core.network.AccessTokenProvider
import com.plainstride.outbound.core.network.AccountApiService
import com.plainstride.outbound.core.network.PlanningApiService
import com.plainstride.outbound.core.network.ActivitiesApiService
import com.plainstride.outbound.core.network.createAccountApi
import com.plainstride.outbound.core.network.createAuthApi
import com.plainstride.outbound.core.network.createPlanningApi
import com.plainstride.outbound.core.network.createActivitiesApi
import com.google.android.gms.location.LocationServices
import com.plainstride.outbound.core.weather.DefaultWeatherRepository
import com.plainstride.outbound.core.weather.FusedWeatherLocationSource
import com.plainstride.outbound.core.weather.WeatherApiService
import com.plainstride.outbound.core.weather.WeatherLocationSource
import com.plainstride.outbound.core.weather.WeatherRepository
import com.plainstride.outbound.core.weather.createWeatherApi
import com.plainstride.outbound.core.assistant.CompanionApi
import com.plainstride.outbound.core.assistant.CompanionRepository
import com.plainstride.outbound.core.assistant.OfflineFirstCompanionRepository
import com.plainstride.outbound.core.assistant.createCompanionApi
import com.plainstride.outbound.core.music.*
import com.plainstride.outbound.feature.social.SocialApiService
import com.plainstride.outbound.feature.social.createSocialApi
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import com.plainstride.outbound.feature.community.CommunityRoutesApi
import com.plainstride.outbound.feature.community.createCommunityRoutesApi
import com.plainstride.outbound.feature.safety.SafetyApi
import com.plainstride.outbound.feature.safety.createSafetyApi
import com.plainstride.outbound.analytics.FirebaseAnalyticsSink
import com.plainstride.outbound.gear.PersistentGearRepository
import com.plainstride.outbound.feature.progress.GearRepository

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

    @Provides @Singleton fun accountDatabaseOperations(database: PlainstrideDatabase) = AccountDatabaseOperations(database)

    @Provides fun accountCacheDao(database: PlainstrideDatabase): AccountCacheDao =
        database.accountCacheDao()

    @Provides
    @Singleton
    fun analytics(sink: FirebaseAnalyticsSink): ProductAnalytics = ProductAnalytics(sink)

    @Provides @Singleton fun credentialManager(@ApplicationContext context: Context): CredentialManager =
        CredentialManager.create(context)

    @Provides @GoogleServerClientId fun googleServerClientId(): String = BuildConfig.GOOGLE_SERVER_CLIENT_ID

    @Provides @Singleton fun httpClient(): OkHttpClient {
        Log.i(NETWORK_TAG, "Configuring API client: baseUrl=${BuildConfig.API_BASE_URL}")
        return OkHttpClient.Builder()
            .retryOnConnectionFailure(true)
            .addInterceptor { chain ->
                val request = chain.request()
                val route = "${request.url.scheme}://${request.url.host}${request.url.encodedPath}"
                val startedAt = System.nanoTime()
                Log.d(NETWORK_TAG, "--> ${request.method} $route")
                try {
                    chain.proceed(request).also { response ->
                        val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000
                        val requestId = response.header("x-request-id") ?: "none"
                        Log.d(NETWORK_TAG, "<-- ${response.code} ${request.method} $route (${elapsedMs}ms) requestId=$requestId")
                    }
                } catch (error: Exception) {
                    val elapsedMs = (System.nanoTime() - startedAt) / 1_000_000
                    Log.e(
                        NETWORK_TAG,
                        "<-- FAILED ${request.method} $route (${elapsedMs}ms) ${error.javaClass.simpleName}: ${error.message}",
                    )
                    throw error
                }
            }
            .build()
    }

    @Provides @Singleton fun authApi(client: OkHttpClient): AuthApiService =
        createAuthApi(BuildConfig.API_BASE_URL, client)

    @Provides @Singleton fun accountApi(client: OkHttpClient): AccountApiService =
        createAccountApi(BuildConfig.API_BASE_URL, client)

    @Provides @Singleton fun planningApi(client: OkHttpClient): PlanningApiService =
        createPlanningApi(BuildConfig.API_BASE_URL, client)

    @Provides @Singleton fun activitiesApi(client: OkHttpClient): ActivitiesApiService =
        createActivitiesApi(BuildConfig.API_BASE_URL, client)

    @Provides @Singleton fun liveCoachApi(client: OkHttpClient): LiveCoachApi =
        createLiveCoachApi(BuildConfig.API_BASE_URL, client)

    @Provides @Singleton fun socialApi(client: OkHttpClient): SocialApiService = createSocialApi(BuildConfig.API_BASE_URL, client)
    @Provides @Singleton fun communityRoutesApi(client: OkHttpClient): CommunityRoutesApi = createCommunityRoutesApi(BuildConfig.API_BASE_URL, client)
    @Provides @Singleton fun safetyApi(client: OkHttpClient): SafetyApi = createSafetyApi(BuildConfig.API_BASE_URL, client)
    @Provides @Singleton fun companionApi(client: OkHttpClient): CompanionApi = createCompanionApi(BuildConfig.API_BASE_URL, client)
    @Provides @Singleton fun companionRepository(api: CompanionApi, tokens: AccessTokenProvider, cache: AccountCacheDao): CompanionRepository = OfflineFirstCompanionRepository(api, tokens, cache)
    @Provides @Singleton fun spotifyAuthorizationStore(@ApplicationContext context: Context): SpotifyAuthorizationStore = SpotifySecureAuthorizationStore(context)
    @Provides @Singleton fun spotifyAuthorizationClient(client: SpotifyOAuthClient): SpotifyAuthorizationClient = client
    @Provides @Singleton fun spotifyRemote(transport: SpotifyWebPlaybackTransport): SpotifyAppRemoteTransport = transport
    @Provides @Singleton fun musicStateStore(dataStore: DataStore<Preferences>) = MusicStateStore(dataStore)
    @Provides @Singleton fun spotifyWebApi(client: OkHttpClient): SpotifyWebApi = createSpotifyWebApi(client)
    @Provides @Singleton fun spotifyCatalog(api: SpotifyWebApi, store: SpotifyAuthorizationStore) = SpotifyCatalog(api, store)
    @Provides @Singleton fun musicScope(): CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    @Provides @Singleton fun musicProvider(remote: SpotifyAppRemoteTransport, client: SpotifyAuthorizationClient, store: SpotifyAuthorizationStore, state: MusicStateStore, scope: CoroutineScope): MusicProvider = SpotifyMusicProvider(remote, client, store, state, scope)
    @Provides @Singleton fun gearRepository(repository: PersistentGearRepository): GearRepository = repository

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

private const val NETWORK_TAG = "PlainstrideNetwork"
