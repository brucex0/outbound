package com.plainstride.outbound.feature.safety

import io.ably.lib.realtime.AblyRealtime
import io.ably.lib.realtime.ChannelBase
import io.ably.lib.types.ClientOptions
import kotlinx.coroutines.runBlocking

/** Authenticated Ably channel connection for one active session. The API key never reaches this class. */
internal class AblySessionTransport private constructor(
    private val realtime: AblyRealtime,
    private val channel: ChannelBase,
) : AutoCloseable {
    fun publishLocation(location: Map<String, Any?>) {
        runCatching { channel.publish("location", location) }
    }

    override fun close() {
        runCatching { channel.unsubscribe() }
        runCatching { realtime.close() }
    }

    companion object {
        fun connect(
            channelName: String,
            tokenProvider: suspend () -> RealtimeToken,
            onMessage: (String, String?, Any?) -> Unit,
        ): AblySessionTransport {
            val options = ClientOptions().apply {
                authCallback = { _ -> runBlocking { tokenProvider().token } }
            }
            val realtime = AblyRealtime(options)
            val channel = realtime.channels.get(channelName)
            channel.subscribe { message -> onMessage(message.name ?: "", message.clientId, message.data) }
            return AblySessionTransport(realtime, channel)
        }
    }
}
