package run.plainstride.feature.community

import kotlinx.serialization.*
import kotlinx.serialization.json.JsonObject
import retrofit2.Response
import retrofit2.http.*

@Serializable data class RouteOwner(val id: String, val displayName: String, val username: String? = null, val avatarUrl: String? = null)
@Serializable data class CommunityRoute(
 val id: String, val name: String, val description: String? = null, val activityType: String, val distanceM: Double,
 val elevationGainM: Double? = null, val routeShape: String, val bookmarkCount: Int = 0, val completionCount: Int = 0,
 val isOwner: Boolean = false, val isBookmarked: Boolean = false, val owner: RouteOwner, val geometry: JsonObject? = null,
)
@Serializable data class RoutesResponse(val routes: List<CommunityRoute> = emptyList())
@Serializable data class PublishRouteRequest(val name: String, val description: String? = null)

interface CommunityRoutesApi {
 @GET("v1/routes/nearby") suspend fun nearby(@Header("Authorization") auth: String, @Query("latitude") latitude: Double, @Query("longitude") longitude: Double, @Query("radiusKm") radiusKm: Int = 25): Response<RoutesResponse>
 @GET("v1/routes/search") suspend fun search(@Header("Authorization") auth: String, @Query("q") query: String): Response<RoutesResponse>
 @GET("v1/routes/mine") suspend fun mine(@Header("Authorization") auth: String): Response<RoutesResponse>
 @GET("v1/routes/{id}") suspend fun detail(@Header("Authorization") auth: String, @Path("id") id: String): Response<CommunityRoute>
 @POST("v1/routes/from-activity/{id}") suspend fun publish(@Header("Authorization") auth: String, @Path("id") activityId: String, @Body body: PublishRouteRequest): Response<CommunityRoute>
 @PUT("v1/routes/{id}/bookmark") suspend fun bookmark(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
 @DELETE("v1/routes/{id}/bookmark") suspend fun unbookmark(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
 @DELETE("v1/routes/{id}") suspend fun remove(@Header("Authorization") auth: String, @Path("id") id: String): Response<Unit>
}
