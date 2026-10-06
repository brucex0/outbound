package com.plainstride.outbound.feature.safety

import io.ably.lib.realtime.AblyRealtime
import io.ably.lib.realtime.ChannelBase
import io.ably.lib.realtime.ChannelState
import io.ably.lib.realtime.ConnectionState
import io.ably.lib.rest.Auth
import io.ably.lib.types.ClientOptions
import io.ably.lib.types.Callback
import io.ably.lib.types.ErrorInfo
import io.ably.lib.types.PublishResult
import android.util.Log
import kotlinx.coroutines.runBlocking

/** Authenticated Ably channel connection for one active session. The API key never reaches this class. */
internal class AblySessionTransport private constructor(
    private val realtime: AblyRealtime,
    private val channel: ChannelBase,
    private val channelKind: String,
) : AutoCloseable {
    fun publishLocation(location: Map<String, Any?>) {
        logDebug("publish_location_requested channel=$channelKind")
        runCatching {
            channel.publish("location", location, object : Callback<PublishResult> {
                override fun onSuccess(result: PublishResult) {
                    logDebug("publish_location_acknowledged channel=$channelKind")
                }

                override fun onError(reason: ErrorInfo) {
                    logError("publish_location_failed channel=$channelKind status=${reason.statusCode} code=${reason.code}")
                }
            })
        }.onFailure { failure ->
            logError("publish_location_enqueue_failed channel=$channelKind error=${failure.javaClass.simpleName}")
        }
    }

    override fun close() {
        runCatching { channel.unsubscribe() }
            .onFailure { logError("unsubscribe_failed channel=$channelKind error=${it.javaClass.simpleName}") }
        runCatching { realtime.close() }
            .onFailure { logError("connection_close_failed channel=$channelKind error=${it.javaClass.simpleName}") }
        logDebug("transport_closed channel=$channelKind")
    }

    companion object {
        fun connect(
            channelName: String,
            tokenProvider: suspend () -> RealtimeToken,
            onMessage: (String, String?, Any?) -> Unit,
            onChannelAttached: () -> Unit = {},
        ): AblySessionTransport {
            val channelKind = channelKind(channelName)
            logDebug("connect_requested channel=$channelKind")
            val options = ClientOptions().apply {
                autoConnect = true
                useTokenAuth = true
                authCallback = { _ ->
                    logDebug("token_request_started channel=$channelKind")
                    val issued = try {
                        runBlocking { tokenProvider() }
                    } catch (failure: Throwable) {
                        logError("token_request_failed channel=$channelKind error=${failure.javaClass.simpleName}")
                        throw failure
                    }
                    logDebug("token_received channel=$channelKind channel_matches=${issued.channel == channelName} expires_in_future=${issued.expiresAt > System.currentTimeMillis()}")
                    require(issued.channel == channelName) { "Realtime token channel mismatch" }
                    Auth.TokenDetails(issued.token).apply {
                        expires = issued.expiresAt
                        clientId = issued.clientId
                    }
                }
            }
            val realtime = AblyRealtime(options)
            ConnectionState.values().forEach { state ->
                realtime.connection.on(state) { change ->
                    val reason = change.reason
                    val status = reason?.statusCode ?: 0
                    val code = reason?.code ?: 0
                    val message = "connection_state channel=$channelKind previous=${change.previous} current=${change.current} status=$status code=$code retry_in_ms=${change.retryIn}"
                    if (change.current == ConnectionState.failed || change.current == ConnectionState.suspended) logError(message)
                    else logDebug(message)
                }
            }
            val channel = realtime.channels.get(channelName)
            ChannelState.values().forEach { state ->
                channel.on(state) { change ->
                    val reason = change.reason
                    val status = reason?.statusCode ?: 0
                    val code = reason?.code ?: 0
                    val message = "channel_state channel=$channelKind previous=${change.previous} current=${change.current} status=$status code=$code resumed=${change.resumed}"
                    if (change.current == ChannelState.failed || change.current == ChannelState.suspended) logError(message)
                    else logDebug(message)
                }
            }
            channel.on(ChannelState.attached) {
                logDebug("channel_attached channel=$channelKind")
                runCatching { onChannelAttached() }
                    .onFailure { logError("channel_attached_callback_failed channel=$channelKind error=${it.javaClass.simpleName}") }
            }
            channel.subscribe { message ->
                val name = message.name ?: ""
                logDebug("message_received channel=$channelKind event=$name")
                runCatching { onMessage(name, message.clientId, message.data) }
                    .onFailure { logError("message_handler_failed channel=$channelKind event=$name error=${it.javaClass.simpleName}") }
            }
            realtime.connect()
            logDebug("connect_call_completed channel=$channelKind")
            return AblySessionTransport(realtime, channel, channelKind)
        }

        private const val TAG = "PlainstrideRealtime"

        private fun channelKind(channelName: String): String = when {
            channelName.startsWith("plainstride:live_share:") -> "live_share"
            channelName.startsWith("plainstride:group_run:") -> "group_run"
            else -> "other"
        }

        private fun logDebug(message: String) {
            if (BuildConfig.DEBUG) Log.d(TAG, message)
        }

        private fun logError(message: String) {
            if (BuildConfig.DEBUG) Log.e(TAG, message)
        }
    }
}
