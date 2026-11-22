package com.plainstride.outbound.feature.community

import kotlinx.serialization.*
import kotlinx.serialization.json.JsonObject
import retrofit2.Response
import retrofit2.http.*
import okhttp3.OkHttpClient
import okhttp3.MediaType.Companion.toMediaType
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import com.plainstride.outbound.core.network.PlainstrideJson

@Serializable data class RouteOwner(val id: String, val displayName: String, val username: String? = null, val avatarUrl: String? = null)
@Serializable enum class CommunityRouteSource { COMMUNITY, IMPORTED }
@Serializable data class CommunityRoute(
 val id: String, val name: String, val description: String? = null, val activityType: String, val distanceM: Double,
 val elevationGainM: Double? = null, val routeShape: String, val bookmarkCount: Int = 0, val completionCount: Int = 0,
 val isOwner: Boolean = false, val isBookmarked: Boolean = false, val owner: RouteOwner, val geometry: JsonObject? = null, val source: CommunityRouteSource = CommunityRouteSource.COMMUNITY,
)
@Serializable data class RoutesResponse(val routes: List<CommunityRoute> = emptyList())
@Serializable data class PublishRouteRequest(val name: String, val description: String? = null)

@Serializable data class GeneratedRouteCoordinate(val latitude: Double, val longitude: Double, val altitude: Double? = null)
@Serializable data class GenerateRouteRequest(val start: GeneratedRouteCoordinate, val via: GeneratedRouteCoordinate? = null, val targetDistanceM: Double, val activityType: String, val preference: String, val variationSeed: Int)
@Serializable data class GeneratedRouteCandidate(val id: String, val points: List<GeneratedRouteCoordinate>, val distanceM: Double, val elevationGainM: Double? = null, val attribution: String, val requestedStart: GeneratedRouteCoordinate, val snappedStart: GeneratedRouteCoordinate)
@Serializable data class GenerateRoutesResponse(val candidates: List<GeneratedRouteCandidate> = emptyList(), val toleranceFraction: Double = .1)
interface CommunityRoutesApi {
 @POST("v1/routes/generate") suspend fun generate(@Header("Authorization") auth: String, @Body request: GenerateRouteRequest): Response<GenerateRoutesResponse>
 @GET("v1/routes/nearby") suspend fun nearby(@Header("Authorization") auth: String, @Query("latitude") latitude: Double, @Query("longitude") longitude: Double, @Query("radiusKm") radiusKm: Int = 25): Response<RoutesResponse>
 @GET("v1/routes/search") suspend fun search(@Header("Authorization") auth: String, @Query("q") query: String): Response<RoutesResponse>
 @GET("v1/routes/mine") suspend fun mine(@Header("Authorization") auth: String): Response<RoutesResponse>
 @GET("v1/routes/{id}") suspend fun detail(@Header("Authorization") auth: String, @Path("id") id: String): Response<CommunityRoute>
 @POST("v1/routes/from-activity/{id}") suspend fun publish(@Header("Authorization") auth: String, @Path("id") activityId: String, @Body body: PublishRouteRequest): Response<CommunityRoute>
 @PUT("v1/routes/{id}/bookmark") suspend fun bookmark(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
 @DELETE("v1/routes/{id}/bookmark") suspend fun unbookmark(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
 @DELETE("v1/routes/{id}") suspend fun remove(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
}
fun createCommunityRoutesApi(baseUrl:String,client:OkHttpClient):CommunityRoutesApi=Retrofit.Builder().baseUrl(if(baseUrl.endsWith('/'))baseUrl else "$baseUrl/").client(client).addConverterFactory(PlainstrideJson.asConverterFactory("application/json".toMediaType())).build().create(CommunityRoutesApi::class.java)
