package run.plainstride.core.music

import kotlinx.serialization.Serializable

enum class MusicConnectionState { Disconnected, Connecting, Connected, ReauthorizationRequired, Unavailable }
@Serializable data class MusicItem(val uri: String, val title: String, val subtitle: String = "", val artworkUrl: String? = null)
@Serializable data class MusicQueue(val items: List<MusicItem> = emptyList(), val currentIndex: Int = 0, val shuffle: Boolean = false, val repeat: Boolean = true)
@Serializable data class MusicPlaybackState(val isPlaying: Boolean = false, val current: MusicItem? = null, val positionMs: Long = 0, val updatedAtEpochMs: Long = 0)
data class MusicState(val connection: MusicConnectionState = MusicConnectionState.Disconnected, val queue: MusicQueue = MusicQueue(), val playback: MusicPlaybackState = MusicPlaybackState(), val lastFailure: String? = null)

data class SpotifyAuthorization(val accessToken: String, val expiresAtEpochMs: Long, val refreshToken: String? = null, val scopes: Set<String> = emptySet())
interface SpotifyAuthorizationStore { suspend fun load(): SpotifyAuthorization?; suspend fun save(value: SpotifyAuthorization); suspend fun clear() }
interface SpotifyAuthorizationClient { suspend fun authorize(): Result<SpotifyAuthorization>; suspend fun refresh(authorization: SpotifyAuthorization): Result<SpotifyAuthorization> }

/** Adapter boundary for Spotify's proprietary App Remote SDK. */
interface SpotifyAppRemoteTransport {
    val connected: Boolean
    suspend fun connect(accessToken: String): Result<Unit>
    suspend fun disconnect()
    suspend fun play(uri: String): Result<Unit>
    suspend fun pause(): Result<Unit>
    suspend fun resume(): Result<Unit>
    suspend fun skipNext(): Result<Unit>
}

interface MusicProvider : AutoCloseable {
    val state: kotlinx.coroutines.flow.StateFlow<MusicState>
    suspend fun connect(): Result<Unit>
    suspend fun disconnect()
    suspend fun setQueue(queue: MusicQueue)
    suspend fun play(index: Int = 0): Result<Unit>
    suspend fun pause(): Result<Unit>
    suspend fun resume(): Result<Unit>
    suspend fun skipNext(): Result<Unit>
}
