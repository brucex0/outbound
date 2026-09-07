package run.plainstride.wear

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.util.UUID
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import run.plainstride.core.model.activity.*

class WearSessionGatewayImpl(private val context: Context) : WearSessionGateway {
    override suspend fun send(command: WearSessionCommand) {
        val state = WearSessionStateStore.state.value
        val wire = SessionCommandEnvelope(UUID.randomUUID().toString(), state?.sessionId ?: UUID.randomUUID().toString(), SessionOwner.WATCH, SessionProtocolCommand.valueOf(command.name.uppercase()), (state?.revision ?: 0) + 1, System.currentTimeMillis())
        if (command == WearSessionCommand.Start) ExerciseService.start(context, wire) else ExerciseService.command(context, wire)
        val bytes = Json.encodeToString(wire).encodeToByteArray()
        Wearable.getNodeClient(context).connectedNodes.await().forEach { Wearable.getMessageClient(context).sendMessage(it.id, COMMAND_PATH, bytes).await() }
    }
    companion object {
        const val COMMAND_PATH = "/plainstride/session/command"; const val STATE_PATH = "/plainstride/session/state"; const val TRACK_PATH = "/plainstride/session/track"; const val STATE_DATA_KEY = "state"; const val TRACK_DATA_KEY = "track"
        suspend fun publish(context: Context, state: SessionStateEnvelope) {
            val request = PutDataMapRequest.create(STATE_PATH).apply { dataMap.putString(STATE_DATA_KEY, Json.encodeToString(state)); dataMap.putLong("revision", state.revision) }.asPutDataRequest().setUrgent()
            Wearable.getDataClient(context).putDataItem(request).await()
        }
        suspend fun publishTrack(context: Context, chunk: WearTrackChunk) {
            val request = PutDataMapRequest.create("$TRACK_PATH/${chunk.sessionId}/${chunk.index}").apply { dataMap.putString(TRACK_DATA_KEY, Json.encodeToString(chunk)) }.asPutDataRequest().setUrgent()
            Wearable.getDataClient(context).putDataItem(request).await()
        }
    }
}

object WearSessionStateStore {
    val state = kotlinx.coroutines.flow.MutableStateFlow<SessionStateEnvelope?>(null)
    fun accept(bytes: ByteArray) = acceptJson(bytes.decodeToString())
    fun acceptJson(value: String) { runCatching { Json.decodeFromString<SessionStateEnvelope>(value) }.getOrNull()?.let { incoming -> if (incoming.revision > (state.value?.revision ?: -1)) state.value = incoming } }
}
