package com.plainstride.outbound.feature.activity

/** Bar length is relative speed, not min/max contrast: near-equal paces stay near-equal. */
internal fun splitPaceFraction(pace: Double, fastest: Double): Double {
    if (!pace.isFinite() || !fastest.isFinite() || pace <= 0 || fastest <= 0) return .85
    return (fastest / pace).coerceIn(0.0, 1.0)
}
