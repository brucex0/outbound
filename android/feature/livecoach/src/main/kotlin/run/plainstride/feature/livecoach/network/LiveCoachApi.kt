package run.plainstride.feature.livecoach.network

import okhttp3.OkHttpClient
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.Streaming
import run.plainstride.core.network.PlainstrideJson
import okhttp3.MediaType.Companion.toMediaType

interface LiveCoachApi {
    @GET("v1/live-coach/config") suspend fun config(@Header("Authorization") authorization: String): Response<LiveCoachConfig>
    @GET("v1/live-coach/catalog") suspend fun catalog(@Header("Authorization") authorization: String, @Query("locale") locale: String): Response<LiveCoachCatalog>
    @POST("v1/live-coach/sessions") suspend fun create(@Header("Authorization") authorization: String, @Body request: CreateSessionRequest): Response<CreateSessionResponse>
    @POST("v1/live-coach/sessions/{id}/cues") suspend fun cue(@Header("Authorization") authorization: String, @Path("id") id: String, @Body request: CueRequest): Response<CueEnvelope>
    @Streaming @POST("v1/live-coach/sessions/{id}/cues/stream") suspend fun stream(@Header("Authorization") authorization: String, @Path("id") id: String, @Body request: CueRequest): Response<ResponseBody>
    @POST("v1/live-coach/sessions/{id}/cues/cached") suspend fun recordCached(@Header("Authorization") authorization: String, @Path("id") id: String, @Body request: CueRequest): Response<Ack>
    @POST("v1/live-coach/sessions/{id}/end") suspend fun end(@Header("Authorization") authorization: String, @Path("id") id: String, @Body request: EndSessionRequest): Response<Ack>
}

fun createLiveCoachApi(baseUrl: String, client: OkHttpClient): LiveCoachApi = Retrofit.Builder()
    .baseUrl(if (baseUrl.endsWith('/')) baseUrl else "$baseUrl/")
    .client(client)
    .addConverterFactory(PlainstrideJson.asConverterFactory("application/json".toMediaType()))
    .build().create(LiveCoachApi::class.java)
