package com.plainstride.outbound.core.network

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonElement
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query

@Serializable
data class ActivityRoutePointDto(
    val timestamp: String,
    val latitude: Double,
    val longitude: Double,
    val altitude: Double? = null,
    val verticalAccuracy: Double? = null,
    val startsNewSegment: Boolean = false,
)

@Serializable data class ActivityRouteDto(val points: List<ActivityRoutePointDto>, val visibility: String = "private")
@Serializable data class ActivityReflectionDto(val title: String, val body: String, val highlight: String, val progressNote: String? = null)

@Serializable
data class ActivityUploadRequest(
    val clientActivityId: String,
    val syncSource: String = "android-local-store",
    val type: String,
    val title: String,
    val startedAt: String,
    val endedAt: String,
    val durationSecs: Int,
    val distanceM: Double,
    val elevationM: Double? = null,
    val avgPace: Double? = null,
    val avgHeartRate: Int? = null,
    val energyKilocalories: Int? = null,
    val activityEventId: String? = null,
    val followedRouteId: String? = null,
    val followedRouteCompleted: Boolean? = null,
    val route: ActivityRouteDto? = null,
    val splits: JsonElement? = null,
    val reflection: ActivityReflectionDto? = null,
    val clientData: JsonObject,
    val clientUpdatedAt: String,
)

@Serializable
data class ActivityUploadResponse(
    val id: String,
    val clientActivityId: String? = null,
    val status: String,
    val uploadedAt: String? = null,
    val serverUpdatedAt: String? = null,
)

@Serializable
data class RemoteActivityPhotoDto(
    val id: String,
    val clientPhotoId: String? = null,
    val takenAt: String,
    val paceAtShot: Double? = null,
    val hrAtShot: Int? = null,
    val distAtShot: Double? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val captureContext: String? = null,
    val byteSize: Long? = null,
    val sha256: String? = null,
    val updatedAt: String? = null,
)

@Serializable
data class RemoteActivityDto(
    val id: String,
    val clientActivityId: String? = null,
    val clientData: JsonObject? = null,
    val clientUpdatedAt: String? = null,
    val deletedAt: String? = null,
    val createdAt: String,
    val updatedAt: String,
    val photos: List<RemoteActivityPhotoDto> = emptyList(),
)

@Serializable data class ActivityListResponse(val activities: List<RemoteActivityDto>, val hasMore: Boolean)
@Serializable data class ActivityDeleteResponse(val status: String, val id: String? = null, val deletedAt: String? = null)

interface ActivitiesApiService {
    @GET("v1/activities")
    suspend fun activities(
        @Header("Authorization") authorization: String,
        @Query("limit") limit: Int,
        @Query("offset") offset: Int,
    ): Response<ActivityListResponse>

    @POST("v1/activities")
    suspend fun upload(
        @Header("Authorization") authorization: String,
        @Body body: ActivityUploadRequest,
    ): Response<ActivityUploadResponse>

    @DELETE("v1/activities/{id}")
    suspend fun delete(
        @Header("Authorization") authorization: String,
        @Path("id") clientOrServerActivityId: String,
    ): Response<ActivityDeleteResponse>
}

fun createActivitiesApi(baseUrl: String, client: OkHttpClient): ActivitiesApiService = Retrofit.Builder()
    .baseUrl(if (baseUrl.endsWith('/')) baseUrl else "$baseUrl/")
    .client(client)
    .addConverterFactory(PlainstrideJson.asConverterFactory("application/json".toMediaType()))
    .build()
    .create(ActivitiesApiService::class.java)
