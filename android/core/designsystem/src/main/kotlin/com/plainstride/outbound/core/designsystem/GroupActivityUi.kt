package com.plainstride.outbound.core.designsystem

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Groups
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.model.activity.*

@Composable fun GroupActivityAttributionRow(attribution: GroupActivityAttribution?, activityType: String, modifier: Modifier = Modifier, onOpen: (String) -> Unit = {}) {
    val eventId = attribution?.id
    Column(modifier.then(if (eventId != null) Modifier.clickable(onClick = { onOpen(eventId) }) else Modifier), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Outlined.Groups, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
            Text(attribution?.groupName?.let { stringResource(R.string.group_activity_named, it) } ?: stringResource(R.string.group_activity_label), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
        }
        attribution?.title?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
        val people = attribution?.participants.orEmpty()
        if (people.isNotEmpty()) {
            val names = people.take(2).joinToString(", ") { it.person.displayName } + if (people.size > 2) " +${people.size - 2}" else ""
            val phrase = if (people.any { it.attendanceMode != "in_person" }) R.string.group_activity_joined_with else when (activityType.lowercase()) {
                "running", "trail_running" -> R.string.group_activity_ran_with
                "walking" -> R.string.group_activity_walked_with
                "hiking" -> R.string.group_activity_hiked_with
                "cycling" -> R.string.group_activity_rode_with
                "swimming" -> R.string.group_activity_swam_with
                else -> R.string.group_activity_worked_out_with
            }
            Text(stringResource(phrase, names), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable fun groupParticipantStatus(participant: GroupActivityParticipant): String = stringResource(when {
    participant.outcome in setOf("completed", "no_recording") -> R.string.group_activity_finished
    participant.isRecording -> R.string.group_activity_recording
    participant.startedAt != null -> R.string.group_activity_started
    else -> R.string.group_activity_not_started
})

@Composable fun GroupActivityPresencePanel(title: String, participants: List<GroupActivityParticipant>, sharing: Boolean, busy: Boolean, onToggle: () -> Unit, modifier: Modifier = Modifier, avatar: (@Composable (GroupActivityPerson) -> Unit)? = null) {
    var expanded by rememberSaveable(title) { mutableStateOf(false) }
    Surface(modifier, shape = MaterialTheme.shapes.large, tonalElevation = 4.dp) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Column(Modifier.fillMaxWidth().clickable { expanded = !expanded }) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) { Icon(Icons.Outlined.Groups, null, Modifier.size(20.dp)); Text(title, Modifier.weight(1f), style = MaterialTheme.typography.titleSmall); Icon(if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore, stringResource(if (expanded) R.string.group_activity_collapse else R.string.group_activity_expand)) }
                Text(stringResource(R.string.group_activity_counts, participants.count { it.status == "going" }, participants.count { it.startedAt != null }, participants.count { it.outcome in setOf("completed", "no_recording") }), style = MaterialTheme.typography.bodySmall)
            }
            if (expanded) {
                Column(Modifier.heightIn(max = 180.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    participants.forEach { participant -> Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (avatar != null) avatar(participant.person) else Surface(shape = MaterialTheme.shapes.extraLarge, color = MaterialTheme.colorScheme.primaryContainer) { Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) { Text(participant.person.displayName.split(" ").take(2).mapNotNull { it.firstOrNull() }.joinToString("")) } }
                        Text(participant.person.displayName, Modifier.weight(1f), style = MaterialTheme.typography.bodySmall)
                        Text(groupParticipantStatus(participant), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    } }
                }
                TextButton(onClick = onToggle, enabled = !busy) { Text(stringResource(if (sharing) R.string.group_activity_stop_sharing else R.string.group_activity_share)) }
            }
        }
    }
}
