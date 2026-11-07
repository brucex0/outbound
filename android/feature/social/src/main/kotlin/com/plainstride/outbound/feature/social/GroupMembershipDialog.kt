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
    save: (String, Boolean, Boolean, (Boolean) -> Unit) -> Unit,
    review: (String, Boolean, (Boolean) -> Unit) -> Unit,
) {
    var allowed by rememberSaveable(group.id) { mutableStateOf(group.memberInvitesAllowed) }
    var required by rememberSaveable(group.id) { mutableStateOf(if (group.trustPolicy == "community") group.joinPolicy != "open" else group.memberInviteApprovalRequired) }
    var savedAllowed by rememberSaveable(group.id) { mutableStateOf(allowed) }
    var savedRequired by rememberSaveable(group.id) { mutableStateOf(required) }
    var saving by remember { mutableStateOf(false) }
    var reviewing by remember { mutableStateOf(emptySet<String>()) }
    val dirty = allowed != savedAllowed || required != savedRequired
    val active = group.lifecycle != "archived"
    Dialog(onDismissRequest = { if (!dirty && !saving) close() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Column {
                Row(Modifier.fillMaxWidth().padding(12.dp)) {
                    TextButton(close, enabled = !dirty && !saving) { Text(stringResource(R.string.social_done)) }
                    Text(stringResource(R.string.group_membership_settings), Modifier.weight(1f), style = MaterialTheme.typography.titleLarge)
                    if (group.currentUserRole == "owner") TextButton({
                        val draftRequired = required
                        val draftAllowed = allowed
                        val draftPolicy = if (group.trustPolicy == "community") if (draftRequired) "request" else "open" else "invite_only"
                        saving = true
                        save(draftPolicy, draftRequired, draftAllowed) { success ->
                            saving = false
                            if (success) { savedAllowed = draftAllowed; savedRequired = draftRequired }
                        }
                    }, enabled = dirty && !saving && active, modifier = Modifier.testTag("group.membership.save")) {
                        Text(stringResource(R.string.group_membership_save))
                    }
                }
                LazyColumn(Modifier.weight(1f).testTag("group.membership.list"), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (group.currentUserRole == "owner") {
                        item {
                            Row {
                                Text(stringResource(R.string.group_membership_allow_member_invites), Modifier.weight(1f))
                                Switch(allowed, { allowed = it }, enabled = !saving && active, modifier = Modifier.testTag("group.membership.member_invites_allowed"))
                            }
                            Row {
                                Text(stringResource(R.string.group_membership_require_approval), Modifier.weight(1f))
                                Switch(required, { required = it }, enabled = !saving && active, modifier = Modifier.testTag("group.membership.approval_required"))
                            }
                            Text(stringResource(if (group.trustPolicy == "community") R.string.group_membership_policy_help else R.string.group_membership_private_policy_help), style = MaterialTheme.typography.bodySmall)
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
