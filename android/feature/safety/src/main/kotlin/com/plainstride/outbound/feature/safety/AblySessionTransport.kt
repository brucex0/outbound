package com.plainstride.outbound.feature.safety

import io.ably.lib.realtime.AblyRealtime
import io.ably.lib.realtime.ChannelBase
import io.ably.lib.realtime.ChannelState
import io.ably.lib.rest.Auth
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
            onChannelAttached: () -> Unit = {},
        ): AblySessionTransport {
            val options = ClientOptions().apply {
                autoConnect = true
                useTokenAuth = true
                authCallback = { _ ->
                    val issued = runBlocking { tokenProvider() }
                    require(issued.channel == channelName) { "Realtime token channel mismatch" }
                    Auth.TokenDetails(issued.token).apply {
                        expires = issued.expiresAt
                        clientId = issued.clientId
                    }
                }
            }
            val realtime = AblyRealtime(options)
            val channel = realtime.channels.get(channelName)
            channel.on(ChannelState.attached) { onChannelAttached() }
            channel.subscribe { message -> onMessage(message.name ?: "", message.clientId, message.data) }
            realtime.connect()
            return AblySessionTransport(realtime, channel)
        }
    }
}
