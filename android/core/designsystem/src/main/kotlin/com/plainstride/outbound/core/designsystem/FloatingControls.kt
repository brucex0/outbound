package com.plainstride.outbound.core.designsystem

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/** Opaque map-level action shared by Today controls and the persistent assistant launcher. */
@Composable
fun PlainstrideFloatingAction(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    content: @Composable () -> Unit,
) {
    val theme = LocalPlainstrideThemeColors.current
    Surface(
        onClick = onClick,
        modifier = modifier,
        shape = CircleShape,
        color = Color.Transparent,
        contentColor = theme.heroForeground,
        tonalElevation = 8.dp,
        shadowElevation = 6.dp,
    ) {
        Box(
            Modifier.size(48.dp).background(Brush.linearGradient(theme.heroGradient)),
            contentAlignment = Alignment.Center,
        ) { content() }
    }
}
