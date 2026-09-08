package com.plainstride.outbound.core.model.activity

import kotlinx.serialization.Serializable

@Serializable enum class SessionOwner { PHONE, WATCH }
@Serializable enum class SessionPhase { IDLE, ACTIVE, PAUSED, FINISHED }
@Serializable enum class SessionProtocolCommand { START, PAUSE, RESUME, FINISH, CLAIM_OWNER, RELEASE_OWNER }
@Serializable data class SessionCommandEnvelope(val commandId: String, val sessionId: String, val owner: SessionOwner, val command: SessionProtocolCommand, val revision: Long, val sentAtEpochMs: Long)
@Serializable data class WearTrackPoint(val timestampEpochMs: Long, val latitude: Double, val longitude: Double, val altitudeMeters: Double? = null)
@Serializable data class WearTrackChunk(val sessionId: String, val index: Int, val points: List<WearTrackPoint>)
@Serializable data class SessionStateEnvelope(val sessionId: String, val owner: SessionOwner, val phase: SessionPhase, val revision: Long, val startedAtEpochMs: Long, val elapsedSeconds: Long, val distanceMeters: Double, val heartRateBpm: Double? = null, val updatedAtEpochMs: Long, val handledCommandIds: List<String> = emptyList(), val track: List<WearTrackPoint> = emptyList(), val trackChunkCount: Int = 0)
