package com.plainstride.outbound

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.firebase.messaging.FirebaseMessaging
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.location.LocationServices
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.Instant
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import com.plainstride.outbound.core.data.ActivityRepository
import com.plainstride.outbound.feature.community.*
import com.plainstride.outbound.feature.health.*
import com.plainstride.outbound.feature.progress.*
import com.plainstride.outbound.feature.safety.*
import com.plainstride.outbound.notifications.PlainstrideMessagingService
import com.plainstride.outbound.feature.recording.*
import com.plainstride.outbound.feature.today.TodayRepository
import com.plainstride.outbound.feature.today.CachedResource
import com.plainstride.outbound.core.model.RunnerInsight
import com.plainstride.outbound.feature.social.CachedSocialHome
import com.plainstride.outbound.feature.social.RecognitionAward
import com.plainstride.outbound.feature.social.SocialPerson
import com.plainstride.outbound.feature.social.SocialRepository
import com.plainstride.outbound.core.network.PlannedWorkoutCompletionRequest
import com.plainstride.outbound.reminders.PlannedWorkoutReminderCoordinator
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics

data class P0IntegrationState(
    val routes: RouteLibrary = RouteLibrary(), val routeScope: RouteScope = RouteScope.DISCOVERY,
    val notifications: List<InboxNotification> = emptyList(),
    val progress: ProgressScreenState = ProgressScreenState(ProgressStatsEngine.snapshot(emptyList()), emptyList()),
    val completedToday: Boolean = false,
    val defaultGearId: String? = null,
    val publishableActivities: List<Pair<String,String>> = emptyList(),
    val pushEnabled: Boolean = true,
    val connections: List<SocialPerson> = emptyList(),
    val recognitions: List<RecognitionAward> = emptyList(),
    val insights: List<RunnerInsight> = emptyList(),
)

@HiltViewModel class P0IntegrationViewModel @Inject constructor(
    private val routes: CommunityRouteRepository, private val safety: LiveShareCoordinator,
    private val activities: ActivityRepository,
    private val today: TodayRepository,
    private val social: SocialRepository,
    private val gear: GearRepository,
    private val reminderCoordinator: PlannedWorkoutReminderCoordinator,
    private val analytics: ProductAnalytics,
    @param:ApplicationContext private val context: Context,
) : ViewModel() {
    private val mutable = MutableStateFlow(P0IntegrationState(pushEnabled=context.getSharedPreferences(PlainstrideMessagingService.PREFERENCES,Context.MODE_PRIVATE).getBoolean(PUSH_ENABLED,true))); val state = mutable.asStateFlow()
    private var accountId: String? = null; private var locale = "en"; private var routeObservation: Job? = null
    fun start(accountId: String, locale: String) {
        if (this.accountId == accountId && this.locale == locale) return
        this.accountId = accountId
        this.locale = locale
        observeRoutes()
        reminderCoordinator.observe(viewModelScope, accountId, locale)
        viewModelScope.launch {
            gear.configure(accountId)
            mutable.update { it.copy(defaultGearId = gear.collection().defaultShoe?.id?.toString()) }
        }
        viewModelScope.launch {
            activities.observePage(accountId, limit = 200).collect { page ->
                val items = page.activities.map { ProgressActivity(it.id, it.title, Instant.parse(it.startedAt), it.durationSecs, it.distanceM, it.elevationGainM, it.averageHeartRateBpm) }
                mutable.update { state -> state.copy(
                    progress = ProgressScreenState(ProgressStatsEngine.snapshot(items), emptyList()),
                    publishableActivities = page.activities.filter { it.track.size > 1 }.take(20).map { it.id to it.title },
                ) }
            }
        }
        viewModelScope.launch {
            today.observePersonalization(accountId, locale).collect { resource ->
                val snapshot = when (resource) {
                    is CachedResource.Available -> resource.value
                    is CachedResource.Failed -> resource.cachedValue
                    CachedResource.Loading -> null
                }
                snapshot?.let { value -> mutable.update { it.copy(insights = value.insights) } }
            }
        }
        viewModelScope.launch {
            launch {
                social.observeHome(accountId, locale).collect { cached ->
                    if (cached is CachedSocialHome.Available) mutable.update { state -> state.copy(
                        connections = cached.value.connections.filter { it.relationship in setOf("accepted", "connected") },
                        recognitions = cached.value.recognitions,
                    ) }
                }
            }
            social.refresh(accountId, locale)
        }
        refreshRoutes()
        refreshInbox()
        registerPush()
    }
    fun scope(value:RouteScope){mutable.update{it.copy(routeScope=value)};observeRoutes();refreshRoutes()}
    fun search(value:String){if(value.length==1||value.length%3==0)refreshRoutes(value)}
    fun refreshRoutes(query:String=""){val id=accountId?:return;viewModelScope.launch(Dispatchers.IO){
        val location=if(mutable.value.routeScope==RouteScope.NEARBY&&(
            context.checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION)==android.content.pm.PackageManager.PERMISSION_GRANTED ||
            context.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION)==android.content.pm.PackageManager.PERMISSION_GRANTED
        ))runCatching{Tasks.await(LocationServices.getFusedLocationProviderClient(context).lastLocation)}.getOrNull() else null
        fun coarse(value:Double?)=value?.let{kotlin.math.round(it*100.0)/100.0}
        routes.refresh(id,locale,mutable.value.routeScope,query,coarse(location?.latitude),coarse(location?.longitude))
    }}
    fun bookmark(route:CommunityRoute)=viewModelScope.launch{routes.bookmark(route.id,!route.isBookmarked);refreshRoutes()}
    fun publishRoute(activityId:String,name:String,description:String?)=viewModelScope.launch{routes.publish(activityId,name,description).onSuccess{refreshRoutes()}}
    fun refreshInbox()=viewModelScope.launch{safety.inbox().onSuccess{response->mutable.update{it.copy(notifications=response.notifications)}}}
    fun openInbox() {
        val readAt = Instant.now().toString()
        mutable.update { state -> state.copy(notifications = state.notifications.map { notification ->
            if (notification.readAt == null) notification.copy(readAt = readAt) else notification
        }) }
        analytics.record(AnalyticsEvent("notification_inbox_opened"))
        viewModelScope.launch { safety.markInboxRead() }
    }
    fun completePlannedWorkout(launch: RecordingLaunchConfiguration, review: RecordedActivityReview) { val id=accountId?:return; val workoutId=launch.plannedWorkoutId?:return; viewModelScope.launch { today.completeWorkout(id,locale,workoutId,PlannedWorkoutCompletionRequest(completedAt=Instant.now().toString(),durationSeconds=review.snapshot.elapsedSeconds.toInt(),distanceMeters=review.snapshot.distanceMeters,completionQuality=review.reflection.name.lowercase())) } }
    private fun observeRoutes(){val id=accountId?:return;routeObservation?.cancel();routeObservation=viewModelScope.launch{routes.observe(id,locale,mutable.value.routeScope).collect{value->mutable.update{s->s.copy(routes=value)}}}}
    private fun registerPush()=viewModelScope.launch(Dispatchers.IO){val preferences=context.getSharedPreferences(PlainstrideMessagingService.PREFERENCES,Context.MODE_PRIVATE);if(!preferences.getBoolean(PUSH_ENABLED,true))return@launch;val cached=preferences.getString(PlainstrideMessagingService.TOKEN,null);val token=cached?:runCatching{Tasks.await(FirebaseMessaging.getInstance().token)}.getOrNull();if(token!=null)safety.registerToken(token,context.packageName,locale)}
    fun setPushEnabled(enabled:Boolean)=viewModelScope.launch(Dispatchers.IO){val preferences=context.getSharedPreferences(PlainstrideMessagingService.PREFERENCES,Context.MODE_PRIVATE);preferences.edit().putBoolean(PUSH_ENABLED,enabled).apply();mutable.update{it.copy(pushEnabled=enabled)};val token=preferences.getString(PlainstrideMessagingService.TOKEN,null)?:return@launch;if(enabled)safety.registerToken(token,context.packageName,locale)else safety.unregisterToken(token)}
    fun trackAssistantOpened(destination: String) = analytics.record(AnalyticsEvent("assistant_launcher_opened", mapOf(
        AnalyticsProperty.Destination to destination,
        AnalyticsProperty.EntrySource to "persistent_launcher",
    )))
    fun trackRouteImport(success: Boolean) = analytics.record(AnalyticsEvent("route_imported", mapOf(
        AnalyticsProperty.Result to if (success) "success" else "failure",
        AnalyticsProperty.Source to "document_picker",
    )))
    private companion object{const val PUSH_ENABLED="push_enabled"}
}
