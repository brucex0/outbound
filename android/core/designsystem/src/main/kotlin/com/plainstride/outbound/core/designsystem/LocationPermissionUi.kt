package com.plainstride.outbound.core.designsystem

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocationOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

@Composable
fun LocationEnableChip(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val accessibilityLabel = stringResource(R.string.location_chip_accessibility)
    Surface(
        onClick = onClick,
        modifier = modifier
            .heightIn(min = 34.dp)
            .semantics {
                contentDescription = accessibilityLabel
            },
        shape = CircleShape,
        color = MaterialTheme.colorScheme.primary,
        contentColor = MaterialTheme.colorScheme.onPrimary,
        shadowElevation = 4.dp,
    ) {
        Row(
            Modifier.padding(horizontal = 14.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Default.LocationOff, contentDescription = null, modifier = Modifier.size(15.dp))
            Text(stringResource(R.string.location_chip_label), style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
fun LocationPermissionEducationDialog(
    onEnable: () -> Unit,
    onClose: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text(stringResource(R.string.location_permission_title)) },
        text = { Text(stringResource(R.string.location_permission_message)) },
        confirmButton = {
            TextButton(onClick = onEnable) {
                Text(stringResource(R.string.location_permission_enable))
            }
        },
        dismissButton = {
            TextButton(onClick = onClose) {
                Text(stringResource(R.string.location_permission_close))
            }
        },
    )
}
