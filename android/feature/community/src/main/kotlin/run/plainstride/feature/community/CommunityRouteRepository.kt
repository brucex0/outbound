package run.plainstride.feature.community

import javax.inject.Inject
import kotlinx.coroutines.flow.*
import run.plainstride.core.database.*
import run.plainstride.core.network.*
import run.plainstride.core.analytics.*

enum class RouteScope { DISCOVERY, MINE, NEARBY }
data class RouteLibrary(val routes: List<CommunityRoute> = emptyList(), val stale: Boolean = false)
class CommunityRouteRepository @Inject constructor(private val api: CommunityRoutesApi, private val tokens: AccessTokenProvider, private val cache: AccountCacheDao, private val analytics: ProductAnalytics) {
 fun observe(accountId: String, locale: String, scope: RouteScope): Flow<RouteLibrary> = cache.observe(accountId, "routes", scope.name, locale).map { row -> row?.payloadJson?.let { runCatching { run.plainstride.core.network.PlainstrideJson.decodeFromString<RoutesResponse>(it) }.getOrNull() }?.let { RouteLibrary(it.routes, row.expiresAtEpochMs?.let { expiry -> expiry < System.currentTimeMillis() } == true) } ?: RouteLibrary() }
 suspend fun refresh(accountId: String, locale: String, scope: RouteScope, query: String = "", latitude: Double? = null, longitude: Double? = null): Result<Unit> = authenticated { auth -> when (scope) { RouteScope.MINE -> apiCall { api.mine(auth) }; RouteScope.DISCOVERY -> apiCall { api.search(auth, query.trim()) }; RouteScope.NEARBY -> if (latitude != null && longitude != null) apiCall { api.nearby(auth, latitude, longitude) } else ApiResult.Failure(ApiFailure(ApiErrorCode.InvalidRequest, false)) } }.onSuccess { response -> val now=System.currentTimeMillis(); cache.upsert(AccountCacheEntity(accountId,"routes",scope.name,locale,PlainstrideJson.encodeToString(response),null,now,now+300_000)) }.map { Unit }.also { result->analytics.record(AnalyticsEvent("route_library_refreshed",mapOf(AnalyticsProperty.Source to scope.name.lowercase(),AnalyticsProperty.Result to if(result.isSuccess)"success" else "failure"))) }
 suspend fun detail(id: String) = authenticated { apiCall { api.detail(it,id) } }
 suspend fun publish(activityId: String, name: String, description: String?) = authenticated { apiCall { api.publish(it,activityId,PublishRouteRequest(name,description)) } }
 suspend fun bookmark(id: String, add: Boolean) = authenticated { auth -> apiCall { if(add) api.bookmark(auth,id) else api.unbookmark(auth,id) } }.also { result->analytics.record(AnalyticsEvent("route_bookmark_changed",mapOf(AnalyticsProperty.Enabled to add,AnalyticsProperty.Result to if(result.isSuccess)"success" else "failure"))) }
 suspend fun remove(id: String) = authenticated { apiCall { api.remove(it,id) } }
 private suspend fun <T:Any> authenticated(call:suspend(String)->ApiResult<T>):Result<T>{ val token=tokens.validAccessToken()?:return Result.failure(IllegalStateException("signed_out")); return when(val result=call("Bearer $token")){ is ApiResult.Success->Result.success(result.value); is ApiResult.Failure->Result.failure(IllegalStateException(result.error.code.name)) } }
}
