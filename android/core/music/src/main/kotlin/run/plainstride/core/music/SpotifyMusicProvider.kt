package run.plainstride.core.music

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class SpotifyMusicProvider(
    private val remote: SpotifyAppRemoteTransport,
    private val authorizationClient: SpotifyAuthorizationClient,
    private val authorizationStore: SpotifyAuthorizationStore,
    private val persistence: MusicStateStore,
    private val lifecycleScope: CoroutineScope,
    private val nowEpochMs: () -> Long = System::currentTimeMillis,
) : MusicProvider {
    private val mutex = Mutex()
    private val mutableState = MutableStateFlow(MusicState())
    override val state = mutableState.asStateFlow()

    suspend fun restore() = mutex.withLock {
        mutableState.value = mutableState.value.copy(queue = persistence.loadQueue(), playback = persistence.loadPlayback().copy(isPlaying = false))
    }

    override suspend fun connect(): Result<Unit> = mutex.withLock {
        mutableState.value = mutableState.value.copy(connection = MusicConnectionState.Connecting, lastFailure = null)
        var authorization = authorizationStore.load()
        if (authorization == null) authorization = authorizationClient.authorize().getOrElse { return@withLock fail("authorization_failed", it) }
        if (authorization.expiresAtEpochMs <= nowEpochMs() + 60_000) {
            authorization = authorizationClient.refresh(authorization).getOrElse {
                authorizationStore.clear(); return@withLock fail("reauthorization_required", it, MusicConnectionState.ReauthorizationRequired)
            }
        }
        authorizationStore.save(authorization)
        remote.connect(authorization.accessToken).onSuccess {
            mutableState.value = mutableState.value.copy(connection = MusicConnectionState.Connected)
        }.onFailure { mutableState.value = mutableState.value.copy(connection = MusicConnectionState.Disconnected, lastFailure = "app_remote_unavailable") }
    }

    override suspend fun disconnect() = mutex.withLock {
        remote.disconnect()
        mutableState.value = mutableState.value.copy(connection = MusicConnectionState.Disconnected, playback = mutableState.value.playback.copy(isPlaying = false))
    }

    override suspend fun setQueue(queue: MusicQueue) = mutex.withLock {
        val safe = queue.copy(items = queue.items.distinctBy { it.uri }.take(200), currentIndex = queue.currentIndex.coerceIn(0, maxOf(0, queue.items.lastIndex)))
        persistence.saveQueue(safe); mutableState.value = mutableState.value.copy(queue = safe)
    }

    override suspend fun play(index: Int): Result<Unit> = mutex.withLock { execute(index) { remote.play(it.uri) } }
    override suspend fun pause(): Result<Unit> = mutex.withLock { control(remote::pause, false) }
    override suspend fun resume(): Result<Unit> = mutex.withLock { control(remote::resume, true) }
    override suspend fun skipNext(): Result<Unit> = mutex.withLock {
        val queue = mutableState.value.queue
        if (queue.items.isEmpty()) return@withLock Result.failure(IllegalStateException("queue_empty"))
        if (queue.currentIndex >= queue.items.lastIndex && !queue.repeat) {
            return@withLock control(remote::pause, false)
        }
        val next = if (queue.currentIndex < queue.items.lastIndex) queue.currentIndex + 1 else 0
        remote.skipNext().onSuccess { updatePlayback(next, true) }
    }
    override fun close() { lifecycleScope.launch { disconnect() } }

    private suspend fun execute(index: Int, action: suspend (MusicItem) -> Result<Unit>): Result<Unit> {
        val queue = mutableState.value.queue
        val item = queue.items.getOrNull(index) ?: return Result.failure(IndexOutOfBoundsException("queue_index"))
        return action(item).onSuccess { updatePlayback(index, true) }.onFailure(::remoteFailure)
    }
    private suspend fun control(action: suspend () -> Result<Unit>, playing: Boolean) = action().onSuccess {
        val playback = mutableState.value.playback.copy(isPlaying = playing, updatedAtEpochMs = nowEpochMs())
        persistence.savePlayback(playback); mutableState.value = mutableState.value.copy(playback = playback)
    }.onFailure(::remoteFailure)
    private suspend fun updatePlayback(index: Int, playing: Boolean) {
        val queue = mutableState.value.queue.copy(currentIndex = index)
        val playback = MusicPlaybackState(playing, queue.items[index], 0, nowEpochMs())
        persistence.saveQueue(queue); persistence.savePlayback(playback); mutableState.value = mutableState.value.copy(queue = queue, playback = playback)
    }
    private fun remoteFailure(error: Throwable) { mutableState.value = mutableState.value.copy(connection = MusicConnectionState.Disconnected, lastFailure = error.message ?: "spotify_remote_failed") }
    private fun fail(code: String, error: Throwable, connection: MusicConnectionState = MusicConnectionState.Disconnected): Result<Unit> {
        mutableState.value = mutableState.value.copy(connection = connection, lastFailure = code); return Result.failure(error)
    }
}
