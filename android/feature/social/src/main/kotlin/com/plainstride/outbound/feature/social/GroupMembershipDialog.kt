package com.plainstride.outbound.feature.social

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

@Composable
fun GroupMembershipDialog(
    group: GroupSummary,
    close: () -> Unit,
    save: (String, Boolean, (Boolean) -> Unit) -> Unit,
    review: (String, Boolean, (Boolean) -> Unit) -> Unit,
) {
    var policy by rememberSaveable(group.id) { mutableStateOf(group.joinPolicy ?: "invite_only") }
    var required by rememberSaveable(group.id) { mutableStateOf(group.memberInviteApprovalRequired) }
    var savedPolicy by rememberSaveable(group.id) { mutableStateOf(policy) }
    var savedRequired by rememberSaveable(group.id) { mutableStateOf(required) }
    var saving by remember { mutableStateOf(false) }
    var reviewing by remember { mutableStateOf(emptySet<String>()) }
    val dirty = policy != savedPolicy || required != savedRequired
    val active = group.lifecycle != "archived"
    Dialog(onDismissRequest = { if (!dirty && !saving) close() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Column {
                Row(Modifier.fillMaxWidth().padding(12.dp)) {
                    TextButton(close, enabled = !saving) { Text(stringResource(R.string.social_done)) }
                    Text(stringResource(R.string.group_membership_settings), Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
                    if (group.currentUserRole == "owner") TextButton({
                        val draftPolicy = policy
                        val draftRequired = required
                        saving = true
                        save(draftPolicy, draftRequired) { success ->
                            saving = false
                            if (success) { savedPolicy = draftPolicy; savedRequired = draftRequired }
                        }
                    }, enabled = dirty && !saving && active, modifier = Modifier.testTag("group.membership.save")) {
                        Text(stringResource(R.string.group_membership_save))
                    }
                }
                LazyColumn(Modifier.weight(1f).testTag("group.membership.list"), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (group.currentUserRole == "owner") {
                        if (group.trustPolicy == "community") item {
                            Text(stringResource(R.string.group_membership_join_policy), style = MaterialTheme.typography.titleMedium)
                            listOf("open" to R.string.group_membership_open, "request" to R.string.group_membership_request, "invite_only" to R.string.group_membership_invite_only).forEach { (value, label) ->
                                Row {
                                    RadioButton(selected = policy == value, onClick = { policy = value }, enabled = !saving && active, modifier = Modifier.testTag("group.membership.policy.$value"))
                                    Text(stringResource(label), Modifier.padding(top = 14.dp))
                                }
                            }
                        }
                        item {
                            Row {
                                Text(stringResource(R.string.group_membership_invite_approval), Modifier.weight(1f))
                                Switch(required, { required = it }, enabled = !saving && active, modifier = Modifier.testTag("group.membership.approval_required"))
                            }
                            Text(stringResource(R.string.group_membership_policy_help), style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    item { Text(stringResource(R.string.group_membership_requests), style = MaterialTheme.typography.titleMedium) }
                    if (group.joinRequests.isEmpty()) item { Text(stringResource(R.string.group_membership_empty)) }
                    items(group.joinRequests, key = GroupJoinRequest::id) { request ->
                        ElevatedCard {
                            Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(request.requester.displayName, style = MaterialTheme.typography.titleMedium)
                                request.inviter?.let { Text(stringResource(R.string.group_membership_inviter, it.displayName)) }
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Button({
                                        reviewing = reviewing + request.id
                                        review(request.id, true) { reviewing = reviewing - request.id }
                                    }, enabled = request.id !in reviewing && active, modifier = Modifier.testTag("group.request.approve.${request.id}")) { Text(stringResource(R.string.group_membership_approve)) }
                                    OutlinedButton({
                                        reviewing = reviewing + request.id
                                        review(request.id, false) { reviewing = reviewing - request.id }
                                    }, enabled = request.id !in reviewing && active, modifier = Modifier.testTag("group.request.deny.${request.id}")) { Text(stringResource(R.string.group_membership_deny)) }
                                }
                            }
                        }
                    }
                    if (group.pendingRequestCount > group.joinRequests.size) item { Text(stringResource(R.string.group_membership_more)) }
                }
            }
        }
    }
}
