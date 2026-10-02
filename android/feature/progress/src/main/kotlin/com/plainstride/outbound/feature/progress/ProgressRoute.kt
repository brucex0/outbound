package com.plainstride.outbound.feature.progress

import androidx.compose.runtime.Composable

@Composable fun ProgressRoute(state:ProgressScreenState,onAnalyticsEvent:(ProgressAnalyticsEvent)->Unit={}){
    ProgressScreen(
        state,
        onAnalyticsEvent = onAnalyticsEvent,
    )
}
