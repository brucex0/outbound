package com.plainstride.outbound.feature.community

import javax.inject.Inject
import dagger.hilt.android.qualifiers.ApplicationContext
import android.content.Context
import android.location.Geocoder
import java.util.Locale
import kotlinx.coroutines.flow.*
import com.plainstride.outbound.core.database.*
import com.plainstride.outbound.core.network.*
import com.plainstride.outbound.core.analytics.*

enum class RouteScope { DISCOVERY, MINE, NEARBY }
data class RouteLibrary(val routes: List<CommunityRoute> = emptyList(), val stale: Boolean = false)
class CommunityRouteRepository @Inject constructor(
 private val api: CommunityRoutesApi,
 private val tokens: AccessTokenProvider,
 private val cache: AccountCacheDao,
 private val analytics: ProductAnalytics,
 @ApplicationContext private val context: Context,
) {
 fun observe(accountId: String, locale: String, scope: RouteScope): Flow<RouteLibrary> = cache.observe(accountId, "routes", scope.name, locale).map { row -> row?.payloadJson?.let { runCatching { com.plainstride.outbound.core.network.PlainstrideJson.decodeFromString<RoutesResponse>(it) }.getOrNull() }?.let { RouteLibrary(it.routes, row.expiresAtEpochMs?.let { expiry -> expiry < System.currentTimeMillis() } == true) } ?: RouteLibrary() }
 suspend fun refresh(accountId: String, locale: String, scope: RouteScope, query: String = "", latitude: Double? = null, longitude: Double? = null): Result<Unit> {
  val trimmed = query.trim()
  val response = when (scope) {
   RouteScope.MINE -> authenticated { apiCall { api.mine(it) } }
   RouteScope.NEARBY -> if (latitude != null && longitude != null) authenticated { apiCall { api.nearby(it, latitude, longitude) } } else Result.failure(IllegalArgumentException("missing_location"))
   RouteScope.DISCOVERY -> {
    val named = authenticated { apiCall { api.search(it, trimmed) } }
    if (trimmed.isEmpty() || named.isFailure) named else {
     val place = if (Geocoder.isPresent()) runCatching {
      @Suppress("DEPRECATION")
      Geocoder(context, Locale.forLanguageTag(locale)).getFromLocationName(trimmed, 1)?.firstOrNull()
     }.getOrNull() else null
     val nearby = place?.let { location ->
      authenticated { apiCall { api.nearby(it, location.latitude, location.longitude) } }.getOrNull()?.routes.orEmpty()
     }.orEmpty()
     named.map { RoutesResponse((it.routes + nearby).distinctBy(CommunityRoute::id)) }
    }
   }
  }
  return response.onSuccess { result ->
   val now = System.currentTimeMillis()
   cache.upsert(AccountCacheEntity(accountId, "routes", scope.name, locale, PlainstrideJson.encodeToString(result), null, now, now + 300_000))
  }.map { Unit }.also { result ->
   analytics.record(AnalyticsEvent("route_library_refreshed", mapOf(
    AnalyticsProperty.Source to if (scope == RouteScope.DISCOVERY && trimmed.isNotEmpty()) "search" else scope.name.lowercase(),
    AnalyticsProperty.Result to if (result.isSuccess) "success" else "failure",
   )))
  }
 }
 suspend fun detail(id: String) = authenticated { apiCall { api.detail(it,id) } }
 suspend fun publish(activityId: String, name: String, description: String?) = authenticated { apiCall { api.publish(it,activityId,PublishRouteRequest(name,description)) } }
 suspend fun bookmark(id: String, add: Boolean) = authenticated { auth -> apiCall { if(add) api.bookmark(auth,id) else api.unbookmark(auth,id) } }.also { result->analytics.record(AnalyticsEvent("route_bookmark_changed",mapOf(AnalyticsProperty.Enabled to add,AnalyticsProperty.Result to if(result.isSuccess)"success" else "failure"))) }
 suspend fun remove(id: String) = authenticated { apiCall { api.remove(it,id) } }
 private suspend fun <T:Any> authenticated(call:suspend(String)->ApiResult<T>):Result<T>{ val token=tokens.validAccessToken()?:return Result.failure(IllegalStateException("signed_out")); return when(val result=call("Bearer $token")){ is ApiResult.Success->Result.success(result.value); is ApiResult.Failure->Result.failure(IllegalStateException(result.error.code.name)) } }
}
