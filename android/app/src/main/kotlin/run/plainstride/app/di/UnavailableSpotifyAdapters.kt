package run.plainstride.app.di

import run.plainstride.core.music.SpotifyAppRemoteTransport
import run.plainstride.core.music.SpotifyAuthorization
import run.plainstride.core.music.SpotifyAuthorizationClient

/** Release-safe boundary until Spotify OAuth/App Remote credentials and SDK are supplied. */
class UnavailableSpotifyAuthorizationClient : SpotifyAuthorizationClient {
    override suspend fun authorize(): Result<SpotifyAuthorization> = Result.failure(IllegalStateException("spotify_not_configured"))
    override suspend fun refresh(authorization: SpotifyAuthorization): Result<SpotifyAuthorization> = Result.failure(IllegalStateException("spotify_not_configured"))
}

class UnavailableSpotifyAppRemoteTransport : SpotifyAppRemoteTransport {
    override val connected = false
    override suspend fun connect(accessToken: String) = Result.failure<Unit>(IllegalStateException("spotify_app_remote_unavailable"))
    override suspend fun disconnect() = Unit
    override suspend fun play(uri: String) = unavailable()
    override suspend fun pause() = unavailable()
    override suspend fun resume() = unavailable()
    override suspend fun skipNext() = unavailable()
    private fun unavailable() = Result.failure<Unit>(IllegalStateException("spotify_app_remote_unavailable"))
}
