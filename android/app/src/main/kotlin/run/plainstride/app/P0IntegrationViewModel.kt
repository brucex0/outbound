package run.plainstride.app

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.firebase.messaging.FirebaseMessaging
import com.google.android.gms.tasks.Tasks
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.Instant
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import run.plainstride.core.data.ActivityRepository
import run.plainstride.feature.community.*
import run.plainstride.feature.health.*
import run.plainstride.feature.progress.*
import run.plainstride.feature.safety.*
import run.plainstride.app.notifications.PlainstrideMessagingService
import run.plainstride.feature.recording.*

data class P0IntegrationState(
    val routes: RouteLibrary = RouteLibrary(), val routeScope: RouteScope = RouteScope.DISCOVERY,
    val notifications: List<InboxNotification> = emptyList(), val health: HealthPermissionSnapshot? = null,
    val progress: ProgressScreenState = ProgressScreenState(ProgressStatsEngine.snapshot(emptyList()), emptyList()),
)

@HiltViewModel class P0IntegrationViewModel @Inject constructor(
    private val routes: CommunityRouteRepository, private val safety: LiveShareCoordinator,
    private val activities: ActivityRepository, private val health: HealthConnectRepository,
    @param:ApplicationContext private val context: Context,
) : ViewModel() {
    private val mutable = MutableStateFlow(P0IntegrationState()); val state = mutable.asStateFlow()
    private var accountId: String? = null; private var locale = "en"; private var routeObservation: Job? = null
    fun start(accountId:String,locale:String){if(this.accountId==accountId&&this.locale==locale)return;this.accountId=accountId;this.locale=locale;observeRoutes();viewModelScope.launch{activities.observePage(accountId,limit=200).collect{page->val items=page.activities.map{ProgressActivity(it.id,it.title,Instant.parse(it.startedAt),it.durationSecs,it.distanceM,it.elevationGainM,it.averageHeartRateBpm)};mutable.update{s->s.copy(progress=ProgressScreenState(ProgressStatsEngine.snapshot(items),emptyList()))}}};refreshRoutes();refreshInbox();refreshHealth();registerPush()}
    fun scope(value:RouteScope){mutable.update{it.copy(routeScope=value)};observeRoutes();refreshRoutes()}
    fun search(value:String){if(value.length==1||value.length%3==0)refreshRoutes(value)}
    fun refreshRoutes(query:String=""){val id=accountId?:return;viewModelScope.launch{routes.refresh(id,locale,mutable.value.routeScope,query)}}
    fun bookmark(route:CommunityRoute)=viewModelScope.launch{routes.bookmark(route.id,!route.isBookmarked);refreshRoutes()}
    fun refreshInbox()=viewModelScope.launch{safety.inbox().onSuccess{response->mutable.update{it.copy(notifications=response.notifications)};safety.markInboxRead()}}
    fun refreshHealth()=viewModelScope.launch{mutable.update{it.copy(health=health.permissionSnapshot())}}
    fun export(review:RecordedActivityReview)=viewModelScope.launch{val snapshot=review.snapshot;val start=snapshot.startedAtEpochMilliseconds?:return@launch;val end=snapshot.recordedAtEpochMilliseconds.takeIf{it>start}?:System.currentTimeMillis();health.write(HealthActivity(HealthSourceIdentity(context.packageName,snapshot.sessionId?:return@launch),when(snapshot.activityKind){ActivityKind.WALKING->HealthActivityType.WALK;ActivityKind.CYCLING->HealthActivityType.CYCLE;else->HealthActivityType.RUN},null,Instant.ofEpochMilli(start),Instant.ofEpochMilli(end),snapshot.distanceMeters,route=snapshot.track.map{HealthRoutePoint(Instant.ofEpochMilli(it.capturedAtEpochMilliseconds),it.latitude,it.longitude,it.altitudeMeters,it.horizontalAccuracyMeters,it.verticalAccuracyMeters)}))}
    private fun observeRoutes(){val id=accountId?:return;routeObservation?.cancel();routeObservation=viewModelScope.launch{routes.observe(id,locale,mutable.value.routeScope).collect{value->mutable.update{s->s.copy(routes=value)}}}}
    private fun registerPush()=viewModelScope.launch(Dispatchers.IO){val cached=context.getSharedPreferences(PlainstrideMessagingService.PREFERENCES,Context.MODE_PRIVATE).getString(PlainstrideMessagingService.TOKEN,null);val token=cached?:runCatching{Tasks.await(FirebaseMessaging.getInstance().token)}.getOrNull();if(token!=null)safety.registerToken(token,context.packageName,locale)}
}
