package run.plainstride.core.weather

import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.Query
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import run.plainstride.core.network.PlainstrideJson

interface WeatherApiService {
    @GET("v1/weather/current")
    suspend fun current(
        @Header("Authorization") authorization: String,
        @Header("Accept-Language") locale: String,
        @Query("latitude") latitude: Double,
        @Query("longitude") longitude: Double,
        @Query("altitudeMeters") altitudeMeters: Int?,
        @Query("force") force: Boolean? = null,
    ): Response<RunningWeatherSnapshot>
}

fun createWeatherApi(baseUrl: String, client: OkHttpClient): WeatherApiService = Retrofit.Builder()
    .baseUrl(if (baseUrl.endsWith('/')) baseUrl else "$baseUrl/")
    .client(client)
    .addConverterFactory(PlainstrideJson.asConverterFactory("application/json".toMediaType()))
    .build()
    .create(WeatherApiService::class.java)
