package run.plainstride.app.di

import android.content.Context
import android.content.Intent
import android.app.PendingIntent
import android.net.Uri
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.concurrent.atomic.AtomicReference
import javax.inject.Inject
import kotlinx.coroutines.CompletableDeferred
import net.openid.appauth.AuthorizationRequest
import net.openid.appauth.AuthorizationResponse
import net.openid.appauth.AuthorizationService
import net.openid.appauth.AuthorizationServiceConfiguration
import net.openid.appauth.ResponseTypeValues
import net.openid.appauth.TokenRequest
import run.plainstride.app.BuildConfig
import run.plainstride.core.music.*

class SpotifyOAuthClient @Inject constructor(@ApplicationContext private val context: Context) : SpotifyAuthorizationClient {
    override suspend fun authorize(): Result<SpotifyAuthorization> {
        if (BuildConfig.SPOTIFY_CLIENT_ID.isBlank()) return Result.failure(IllegalStateException("spotify_not_configured"))
        val deferred = CompletableDeferred<Intent>()
        pending.getAndSet(deferred)?.cancel()
        val config = AuthorizationServiceConfiguration(Uri.parse("https://accounts.spotify.com/authorize"), Uri.parse("https://accounts.spotify.com/api/token"))
        val request = AuthorizationRequest.Builder(config, BuildConfig.SPOTIFY_CLIENT_ID, ResponseTypeValues.CODE, Uri.parse(BuildConfig.SPOTIFY_REDIRECT_URI)).setScopes("user-modify-playback-state", "user-read-playback-state").build()
        val completion = PendingIntent.getActivity(context, 419, Intent(context, run.plainstride.app.MainActivity::class.java).setAction(CALLBACK), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        AuthorizationService(context).performAuthorizationRequest(request, completion)
        val response = AuthorizationResponse.fromIntent(deferred.await()) ?: return Result.failure(IllegalStateException("spotify_authorization_failed"))
        return exchange(response)
    }
    override suspend fun refresh(authorization: SpotifyAuthorization): Result<SpotifyAuthorization> {
        val refreshToken = authorization.refreshToken ?: return Result.failure(IllegalStateException("spotify_reauthorization_required"))
        val config = AuthorizationServiceConfiguration(Uri.parse("https://accounts.spotify.com/authorize"), Uri.parse("https://accounts.spotify.com/api/token"))
        val request = TokenRequest.Builder(config, BuildConfig.SPOTIFY_CLIENT_ID).setGrantType("refresh_token").setRefreshToken(refreshToken).setScope(authorization.scopes.joinToString(" ")).build()
        return exchange(request, refreshToken, authorization.scopes)
    }
    private suspend fun exchange(response: AuthorizationResponse): Result<SpotifyAuthorization> = kotlinx.coroutines.suspendCancellableCoroutine { continuation ->
        AuthorizationService(context).performTokenRequest(response.createTokenExchangeRequest()) { token, error ->
            val access = token?.accessToken
            if (access != null) continuation.resume(Result.success(SpotifyAuthorization(access, token.accessTokenExpirationTime ?: System.currentTimeMillis() + 3_600_000, token.refreshToken, token.scope.orEmpty().split(' ').filter(String::isNotBlank).toSet())), null)
            else continuation.resume(Result.failure(error ?: IllegalStateException("spotify_token_exchange_failed")), null)
        }
    }
    private suspend fun exchange(request: TokenRequest, fallbackRefreshToken: String, scopes: Set<String>): Result<SpotifyAuthorization> = kotlinx.coroutines.suspendCancellableCoroutine { continuation ->
        AuthorizationService(context).performTokenRequest(request) { token, error ->
            val access = token?.accessToken
            if (access != null) continuation.resume(Result.success(SpotifyAuthorization(access, token.accessTokenExpirationTime ?: System.currentTimeMillis() + 3_600_000, token.refreshToken ?: fallbackRefreshToken, token.scope?.split(' ')?.filter(String::isNotBlank)?.toSet() ?: scopes)), null)
            else continuation.resume(Result.failure(error ?: IllegalStateException("spotify_refresh_failed")), null)
        }
    }
    companion object { const val CALLBACK = "run.plainstride.spotify.CALLBACK"; private val pending = AtomicReference<CompletableDeferred<Intent>?>(null); fun complete(intent: Intent): Boolean = pending.getAndSet(null)?.let { it.complete(intent) } ?: false }
}

class SpotifyWebPlaybackTransport @Inject constructor(private val api: SpotifyWebApi) : SpotifyAppRemoteTransport {
    private var token: String? = null
    override val connected get() = token != null
    override suspend fun connect(accessToken: String) = Result.success(Unit).also { token = accessToken }
    override suspend fun disconnect() { token = null }
    override suspend fun play(uri: String) = call { api.play(auth(), SpotifyPlaybackBody(listOf(uri))) }
    override suspend fun pause() = call { api.pause(auth()) }
    override suspend fun resume() = call { api.play(auth(), SpotifyPlaybackBody(emptyList())) }
    override suspend fun skipNext() = call { api.next(auth()) }
    private fun auth() = "Bearer ${token ?: error("spotify_not_connected")}"
    private suspend fun call(block: suspend () -> retrofit2.Response<Unit>) = runCatching { check(block().isSuccessful) { "spotify_playback_failed" } }
}
