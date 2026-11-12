package com.plainstride.outbound.feature.today

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.plainstride.outbound.core.network.PlanRecommendation

/** Local-fixture adapter. The app invokes this only through its DEBUG launch harness. */
@Composable
fun DebugPlanPicker(
    recommendations: List<PlanRecommendation>,
    mode: String,
    hasActivePlan: Boolean,
    onDismiss: () -> Unit,
) {
    var state by remember(mode, recommendations) {
        mutableStateOf(PlanPickerUiState(
            open = true,
            recommendations = if (mode in setOf("loading", "empty", "error")) emptyList() else recommendations,
            selected = recommendations.firstOrNull().takeIf { mode in setOf("detail", "replacing") },
            loading = mode == "loading" || mode == "refreshing",
            error = mode == "error",
            loadingError = mode == "error",
            replacing = mode == "replacing",
        ))
    }
    PlanPickerDialog(
        picker = state,
        hasActivePlan = hasActivePlan,
        onDismiss = onDismiss,
        onRetry = { state = PlanPickerUiState(open = true, recommendations = recommendations) },
        onSelect = { state = state.copy(selected = it) },
        // Simulate a successful selection without writing account or backend data.
        onUse = { _, _ -> onDismiss() },
        onBuild = onDismiss,
    )
}
