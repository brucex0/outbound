package run.plainstride.core.music

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import retrofit2.http.GET
import retrofit2.http.Body
import retrofit2.http.PUT
import retrofit2.http.POST
import retrofit2.http.Header
import retrofit2.http.Query

@Serializable data class SpotifyImageDto(val url: String)
@Serializable data class SpotifyArtistDto(val name: String)
@Serializable data class SpotifyAlbumDto(val name: String, val images: List<SpotifyImageDto> = emptyList())
@Serializable data class SpotifyTrackDto(val uri: String, val name: String, val artists: List<SpotifyArtistDto> = emptyList(), val album: SpotifyAlbumDto? = null)
@Serializable data class SpotifyTrackPageDto(val items: List<SpotifyTrackDto> = emptyList())
@Serializable data class SpotifySearchResponseDto(val tracks: SpotifyTrackPageDto? = null)

interface SpotifyWebApi {
    @GET("v1/search") suspend fun search(@Header("Authorization") authorization: String, @Query("q") query: String, @Query("type") type: String = "track", @Query("limit") limit: Int = 20): Response<SpotifySearchResponseDto>
    @PUT("v1/me/player/play") suspend fun play(@Header("Authorization") authorization: String, @Body body: SpotifyPlaybackBody): Response<Unit>
    @PUT("v1/me/player/pause") suspend fun pause(@Header("Authorization") authorization: String): Response<Unit>
    @POST("v1/me/player/next") suspend fun next(@Header("Authorization") authorization: String): Response<Unit>
}
@Serializable data class SpotifyPlaybackBody(val uris: List<String>)

internal val SpotifyJson = kotlinx.serialization.json.Json { ignoreUnknownKeys = true; explicitNulls = false }
fun createSpotifyWebApi(client: OkHttpClient): SpotifyWebApi = Retrofit.Builder().baseUrl("https://api.spotify.com/").client(client).addConverterFactory(SpotifyJson.asConverterFactory("application/json".toMediaType())).build().create(SpotifyWebApi::class.java)

class SpotifyCatalog(private val api: SpotifyWebApi, private val authorizations: SpotifyAuthorizationStore) {
    suspend fun search(query: String): Result<List<MusicItem>> = runCatching {
        val token = authorizations.load()?.takeIf { it.expiresAtEpochMs > System.currentTimeMillis() } ?: error("reauthorization_required")
        val response = api.search("Bearer ${token.accessToken}", query.trim().take(100))
        check(response.isSuccessful)
        response.body()?.tracks?.items.orEmpty().map { MusicItem(it.uri, it.name, it.artists.joinToString { artist -> artist.name }, it.album?.images?.firstOrNull()?.url) }
    }
}
