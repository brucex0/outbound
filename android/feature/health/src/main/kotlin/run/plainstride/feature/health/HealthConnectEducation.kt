package run.plainstride.feature.health

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

data class HealthEducationAnalyticsEvent(val name: String, val result: String)

@Composable
fun HealthConnectEducation(
    permissions: HealthPermissionSnapshot,
    onRequestPermissions: (Set<String>) -> Unit,
    onOpenHealthConnect: () -> Unit,
    onContinueWithoutHealthConnect: () -> Unit,
    modifier: Modifier = Modifier,
    onAnalyticsEvent: (HealthEducationAnalyticsEvent) -> Unit = { _ -> },
) {
    LaunchedEffect(permissions.availability, permissions.state) {
        onAnalyticsEvent(
            HealthEducationAnalyticsEvent(
                "health_connect_education_viewed",
                "${permissions.availability.name.lowercase()}_${permissions.state.name.lowercase()}",
            ),
        )
    }
    Card(modifier.fillMaxWidth()) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(stringResource(R.string.health_connect_title), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Text(stringResource(R.string.health_connect_body))
            Text(stringResource(R.string.health_connect_privacy), style = MaterialTheme.typography.bodySmall)
            when (permissions.availability) {
                HealthConnectAvailability.AVAILABLE -> when (permissions.state) {
                    HealthPermissionState.GRANTED -> Text(stringResource(R.string.health_connect_connected), color = MaterialTheme.colorScheme.primary)
                    HealthPermissionState.PARTIAL -> {
                        Text(stringResource(R.string.health_connect_partial))
                        Button(onClick = {
                            onAnalyticsEvent(HealthEducationAnalyticsEvent("health_connect_permission_requested", "partial"))
                            onRequestPermissions(permissions.missingPermissions)
                        }) { Text(stringResource(R.string.health_connect_review_permissions)) }
                    }
                    HealthPermissionState.REVOKED -> PermissionAction(stringResource(R.string.health_connect_revoked), permissions.requestedPermissions, onRequestPermissions, onAnalyticsEvent)
                    else -> PermissionAction(stringResource(R.string.health_connect_permission_prompt), permissions.requestedPermissions, onRequestPermissions, onAnalyticsEvent)
                }
                HealthConnectAvailability.UPDATE_REQUIRED -> {
                    Text(stringResource(R.string.health_connect_update_required))
                    Button(onClick = onOpenHealthConnect) { Text(stringResource(R.string.health_connect_update)) }
                }
                HealthConnectAvailability.UNAVAILABLE -> Text(stringResource(R.string.health_connect_unavailable))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (permissions.availability == HealthConnectAvailability.AVAILABLE) {
                    OutlinedButton(onClick = onOpenHealthConnect) { Text(stringResource(R.string.health_connect_manage)) }
                }
                OutlinedButton(onClick = onContinueWithoutHealthConnect) { Text(stringResource(R.string.health_connect_not_now)) }
            }
        }
    }
}

@Composable
private fun PermissionAction(
    message: String,
    permissions: Set<String>,
    onRequestPermissions: (Set<String>) -> Unit,
    onAnalyticsEvent: (HealthEducationAnalyticsEvent) -> Unit,
) {
    Text(message)
    Button(onClick = {
        onAnalyticsEvent(HealthEducationAnalyticsEvent("health_connect_permission_requested", "all"))
        onRequestPermissions(permissions)
    }) { Text(stringResource(R.string.health_connect_allow)) }
}
