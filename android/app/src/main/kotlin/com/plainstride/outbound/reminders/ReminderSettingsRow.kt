package com.plainstride.outbound.reminders

import android.app.TimePickerDialog
import androidx.compose.material3.ListItem
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.foundation.clickable
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import com.plainstride.outbound.R

@Composable
fun ReminderSettingsRow(viewModel: ReminderViewModel, debugToolsEnabled: Boolean = false) {
    val context = LocalContext.current
    val enabled by viewModel.enabled.collectAsStateWithLifecycle()
    val time by viewModel.time.collectAsStateWithLifecycle()
    val formatted = LocalTime.of(time.first, time.second).format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT))
    Column {
        ListItem(
            headlineContent = { Text(stringResource(R.string.reminder_setting)) },
            supportingContent = { Text(stringResource(R.string.reminder_setting_body, formatted)) },
            trailingContent = { Switch(enabled, viewModel::setEnabled) },
            modifier = Modifier.clickable {
                TimePickerDialog(context, { _, hour, minute -> viewModel.setTime(hour, minute) }, time.first, time.second, false).show()
            },
        )
        if (debugToolsEnabled) TextButton(onClick = viewModel::sendDebugTest) {
            Text(stringResource(R.string.reminder_debug_test))
        }
    }
}
