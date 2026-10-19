package com.plainstride.outbound.core.data

import com.plainstride.outbound.core.model.activity.ActivityElevationMetadata
import com.plainstride.outbound.core.model.activity.SavedActivity
import com.plainstride.outbound.core.model.activity.TerrainElevationSampling
import com.plainstride.outbound.core.network.ActivitiesApiService
import com.plainstride.outbound.core.network.TerrainElevationPoint
import com.plainstride.outbound.core.network.TerrainElevationRequest

internal class TerrainElevationCorrectionException(val category: String, val httpStatus: Int? = null) :
    Exception(category)

internal class TerrainElevationCorrector(private val api: ActivitiesApiService) {
    suspend fun correct(activity: SavedActivity, authorization: String): SavedActivity {
        val sampled = TerrainElevationSampling.sample(activity.track)
        val points = sampled.points
        val response = api.correctTerrainElevation(authorization, TerrainElevationRequest(points.map {
            TerrainElevationPoint(it.latitude, it.longitude, it.startsNewSegment)
        }))
        if (!response.isSuccessful) {
            response.errorBody()?.close()
            throw TerrainElevationCorrectionException("http_error", response.code())
        }
        val body = response.body() ?: throw TerrainElevationCorrectionException("invalid_response")
        if (body.algorithmVersion != TerrainElevationSampling.ALGORITHM_VERSION) {
            throw TerrainElevationCorrectionException("unsupported_algorithm")
        }
        if (body.elevationsMeters.size != points.size || !body.elevationGainMeters.isFinite() || body.elevationGainMeters < 0
            || body.elevationsMeters.any { !it.isFinite() } || !body.approximateResolutionMeters.isFinite() || body.approximateResolutionMeters < 0) {
            throw TerrainElevationCorrectionException("invalid_response")
        }
        return activity.copy(
            elevationGainM = body.elevationGainMeters,
            elevationMetadata = ActivityElevationMetadata(
                body.algorithmVersion, body.attribution.provider, body.attribution.text, body.attribution.url, body.attribution.modified,
            ),
            // Preserve original map geometry, timestamps, pause boundaries, and split timing.
            track = activity.track.mapIndexed { index, point ->
                val position = sampled.positions[index]
                point.copy(
                    altitude = body.elevationsMeters[position.lower] * (1 - position.fraction)
                        + body.elevationsMeters[position.upper] * position.fraction,
                    verticalAccuracy = maxOf(1.0, body.approximateResolutionMeters),
                )
            },
        )
    }
}
