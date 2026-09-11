package com.plainstride.outbound.core.designsystem

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.unit.dp

enum class PlainstrideFloatingActionStyle { Hero, Accent }

/** Opaque map-level action shared by Today controls and the persistent assistant launcher. */
@Composable
fun PlainstrideFloatingAction(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    style: PlainstrideFloatingActionStyle = PlainstrideFloatingActionStyle.Hero,
    content: @Composable () -> Unit,
) {
    val theme = LocalPlainstrideThemeColors.current
    val accentStyle = style == PlainstrideFloatingActionStyle.Accent
    val background = if (accentStyle) {
        Brush.linearGradient(
            listOf(
                lerp(theme.accent, Color.White, 0.10f),
                theme.accent,
                lerp(theme.accent, Color.Black, 0.08f),
            ),
        )
    } else {
        Brush.linearGradient(theme.heroGradient)
    }
    val foreground = if (accentStyle) Color.White else theme.heroForeground
    Surface(
        onClick = onClick,
        modifier = modifier,
        shape = CircleShape,
        color = Color.Transparent,
        contentColor = foreground,
        tonalElevation = 8.dp,
        shadowElevation = if (accentStyle) 10.dp else 6.dp,
    ) {
        Box(
            Modifier
                .size(48.dp)
                .background(background)
                .then(
                    if (accentStyle) {
                        Modifier.border(0.8.dp, Color.White.copy(alpha = 0.22f), CircleShape)
                    } else {
                        Modifier
                    },
                ),
            contentAlignment = Alignment.Center,
        ) { content() }
    }
}
