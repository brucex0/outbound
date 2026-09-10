package com.plainstride.outbound.core.designsystem

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** Opaque map-level action shared by Today controls and the persistent assistant launcher. */
@Composable
fun PlainstrideFloatingAction(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    content: @Composable () -> Unit,
) {
    Surface(
        onClick = onClick,
        modifier = modifier,
        shape = CircleShape,
        color = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surface,
        tonalElevation = 8.dp,
        shadowElevation = 6.dp,
    ) {
        Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) { content() }
    }
}
