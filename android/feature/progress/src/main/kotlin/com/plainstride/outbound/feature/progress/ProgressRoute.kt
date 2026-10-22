package com.plainstride.outbound.feature.progress

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect

@Composable fun ProgressRoute(state:ProgressScreenState,onAnalyticsEvent:(ProgressAnalyticsEvent)->Unit={},onRefresh:()->Unit={}){
    LaunchedEffect(Unit) { onRefresh() }
    ProgressScreen(
        state,
        onAnalyticsEvent = onAnalyticsEvent,
        onRefresh = onRefresh,
    )
}
