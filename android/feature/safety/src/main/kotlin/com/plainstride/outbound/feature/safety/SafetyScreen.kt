package com.plainstride.outbound.feature.safety

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.plainstride.outbound.core.designsystem.MapCoordinate
import com.plainstride.outbound.core.designsystem.PlainstrideRouteMap
import com.plainstride.outbound.feature.social.SocialAvatar
import com.plainstride.outbound.feature.social.SocialPerson

interface TrustedContactStore {
 suspend fun contacts():List<TrustedContact>
 suspend fun save(contact:TrustedContact)
 suspend fun remove(id:String)
 suspend fun sharesWithTrustedContactsByDefault(accountId:String):Boolean
 suspend fun setSharesWithTrustedContactsByDefault(accountId:String,enabled:Boolean)
 suspend fun migrateToServerBackedContacts()
 suspend fun pull(accountId:String)
 suspend fun push()
}
enum class NotificationPermissionState { UNKNOWN, GRANTED, DENIED, PERMANENTLY_DENIED }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TrustedContactsSettingsScreen(
    connections: List<SocialPerson>,
    trustedContacts: List<TrustedContact>,
    sharesWithTrustedContactsByDefault: Boolean,
    onTrustedChange: (SocialPerson, Boolean) -> Unit,
    onDefaultSharingChange: (Boolean) -> Unit,
    onBack: () -> Unit,
    onOpenConnections: () -> Unit,
) {
    val acceptedConnections = remember(connections) {
        connections.filter { it.relationship in setOf("accepted", "connected") }
            .distinctBy(SocialPerson::id)
            .sortedWith(
                compareByDescending<SocialPerson> { it.isActive }
                    .thenBy { it.displayName.substringBefore(' ').lowercase() }
                    .thenBy { it.displayName.lowercase() }
                    .thenBy(SocialPerson::id),
            )
    }
    val trustedIds = remember(trustedContacts) { trustedContacts.map(TrustedContact::id).toSet() }

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(stringResource(R.string.trusted_contacts_title), style = MaterialTheme.typography.titleMedium) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = stringResource(R.string.trusted_contacts_back))
                    }
                },
            )
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { insets ->
        LazyColumn(
            Modifier.fillMaxSize().padding(insets),
            contentPadding = PaddingValues(start = 16.dp, top = 12.dp, end = 16.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(28.dp),
                        color = MaterialTheme.colorScheme.surface,
                    ) {
                        Row(
                            Modifier.fillMaxWidth().clickable(enabled = trustedIds.isNotEmpty()) {
                                onDefaultSharingChange(!sharesWithTrustedContactsByDefault)
                            }.padding(start = 16.dp, top = 4.dp, end = 10.dp, bottom = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                stringResource(R.string.trusted_contacts_default_share),
                                Modifier.weight(1f),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            Switch(
                                checked = sharesWithTrustedContactsByDefault,
                                onCheckedChange = onDefaultSharingChange,
                                enabled = trustedIds.isNotEmpty(),
                            )
                        }
                    }
                    Text(
                        stringResource(R.string.trusted_contacts_default_share_detail),
                        Modifier.padding(horizontal = 12.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            item {
                Text(
                    stringResource(R.string.trusted_contacts_section),
                    Modifier.padding(start = 4.dp, top = 2.dp, bottom = 0.dp),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            if (acceptedConnections.isEmpty()) {
                item {
                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(22.dp),
                        color = MaterialTheme.colorScheme.surface,
                    ) {
                        Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(stringResource(R.string.trusted_contacts_no_connections), fontWeight = FontWeight.SemiBold)
                            Text(stringResource(R.string.trusted_contacts_no_connections_detail), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            TextButton(onClick = onOpenConnections) { Text(stringResource(R.string.trusted_contacts_open_connections)) }
                        }
                    }
                }
            } else {
                item {
                    Surface(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(22.dp),
                        color = MaterialTheme.colorScheme.surface,
                        tonalElevation = 1.dp,
                    ) {
                        Column {
                            acceptedConnections.forEachIndexed { index, person ->
                                val checked = person.id in trustedIds
                                Row(
                                    Modifier.fillMaxWidth().heightIn(min = 68.dp).clickable {
                                        onTrustedChange(person, !checked)
                                    }.padding(start = 16.dp, end = 10.dp, top = 6.dp, bottom = 6.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                        Text(person.displayName, style = MaterialTheme.typography.bodyLarge)
                                        person.username?.takeIf(String::isNotBlank)?.let {
                                            Text("@$it", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                    }
                                    Switch(checked = checked, onCheckedChange = { onTrustedChange(person, it) })
                                }
                                if (index < acceptedConnections.lastIndex) HorizontalDivider(Modifier.padding(horizontal = 14.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.55f))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable fun SafetySettingsScreen(contacts:List<TrustedContact>, permission:NotificationPermissionState,onRequestPermission:()->Unit,onOpenSettings:()->Unit,onAdd:()->Unit,onRemove:(TrustedContact)->Unit,onArm:()->Unit,activeShare:LiveShare?,groupRun:GroupRun?,onShare:(String)->Unit,onCreateGroup:()->Unit,onJoinGroup:(String)->Unit,onLeaveGroup:()->Unit){
 var invite by rememberSaveable { mutableStateOf("") }
 LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(12.dp)){
  item{Text(stringResource(R.string.safety_title),style=MaterialTheme.typography.headlineMedium,fontWeight=FontWeight.Bold)}
  item{Text(stringResource(R.string.safety_explanation))}
  if(permission!=NotificationPermissionState.GRANTED)item{ElevatedCard(Modifier.fillMaxWidth()){Column(Modifier.padding(16.dp)){Text(stringResource(R.string.safety_notification_title),fontWeight=FontWeight.SemiBold);Text(stringResource(R.string.safety_notification_body));Button(if(permission==NotificationPermissionState.PERMANENTLY_DENIED)onOpenSettings else onRequestPermission,Modifier.padding(top=8.dp)){Text(stringResource(if(permission==NotificationPermissionState.PERMANENTLY_DENIED)R.string.safety_settings else R.string.safety_allow))}}}}
  item{Row(verticalAlignment=Alignment.CenterVertically){Text(stringResource(R.string.safety_contacts),style=MaterialTheme.typography.titleLarge,modifier=Modifier.weight(1f));IconButton(onAdd){Icon(Icons.Outlined.PersonAdd,stringResource(R.string.safety_add_contact))}}}
  if(contacts.isEmpty())item{OutlinedCard(Modifier.fillMaxWidth()){Text(stringResource(R.string.safety_contacts_empty),Modifier.padding(16.dp))}}
  items(contacts,key=TrustedContact::id){contact->OutlinedCard(Modifier.fillMaxWidth()){Row(Modifier.padding(16.dp),verticalAlignment=Alignment.CenterVertically){Icon(Icons.Outlined.HealthAndSafety,null);Spacer(Modifier.width(12.dp));Column(Modifier.weight(1f)){Text(contact.displayName);if(contact.isDefault)Text(stringResource(R.string.safety_default_contact),style=MaterialTheme.typography.bodySmall)};IconButton({onRemove(contact)}){Icon(Icons.Outlined.Delete,stringResource(R.string.safety_remove_contact))}}}}
  item{Button(onArm,Modifier.fillMaxWidth(),enabled=contacts.isNotEmpty()){Text(stringResource(R.string.safety_arm))}}
  activeShare?.shareURL?.let{url->item{OutlinedButton({onShare(url)},Modifier.fillMaxWidth()){Icon(Icons.Outlined.Share,null);Spacer(Modifier.width(8.dp));Text(stringResource(R.string.safety_share_link))}}}
  item{Text(stringResource(R.string.safety_group_title),style=MaterialTheme.typography.titleLarge)}
  if(groupRun==null){item{OutlinedTextField(invite,{invite=it},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.safety_group_invite))});Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){Button(onCreateGroup,Modifier.weight(1f)){Text(stringResource(R.string.safety_group_create))};OutlinedButton({onJoinGroup(invite)},Modifier.weight(1f),enabled=invite.isNotBlank()){Text(stringResource(R.string.safety_group_join))}}}} else {
   val located=groupRun.participants.mapNotNull{it.lastLocation?.let{point->MapCoordinate(point.latitude,point.longitude)}}
   if(located.isNotEmpty())item{PlainstrideRouteMap(located,Modifier.fillMaxWidth().height(220.dp))}
   items(groupRun.participants,key=GroupRunParticipant::id){participant->ListItem(headlineContent={Text(participant.displayName)},supportingContent={Text(stringResource(R.string.safety_group_progress,participant.lastActivitySnapshot?.distanceM?.div(1000.0)?:0.0))},leadingContent={Icon(Icons.Outlined.Groups,null)})}
   item{Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){groupRun.inviteURL?.let{url->OutlinedButton({onShare(url)},Modifier.weight(1f)){Text(stringResource(R.string.safety_share_link))}};Button(onLeaveGroup,Modifier.weight(1f)){Text(stringResource(R.string.safety_group_leave))}}}
  }
  item{Text(stringResource(R.string.safety_disclaimer),style=MaterialTheme.typography.bodySmall)}
 }
}

@Composable
fun CheerInvitationPickerDialog(
    connections: List<SocialPerson>,
    trustedContacts: List<TrustedContact>,
    currentSelection: Set<String>,
    onDismiss: () -> Unit,
    onSetUpTrustedContacts: () -> Unit,
    onDone: (Set<String>) -> Unit,
) {
    val accepted = remember(connections) {
        connections.filter { it.relationship in setOf("accepted", "connected") }
            .distinctBy(SocialPerson::id)
            .sortedBy { it.displayName.lowercase() }
    }
    val trustedIds = remember(trustedContacts, accepted) {
        trustedContacts.map(TrustedContact::id).toSet().intersect(accepted.map(SocialPerson::id).toSet())
    }
    var selected by remember(currentSelection, trustedIds) {
        mutableStateOf(if (currentSelection.isNotEmpty()) currentSelection.intersect(accepted.map(SocialPerson::id).toSet()) else trustedIds)
    }
    val trusted = accepted.filter { it.id in trustedIds }
    val others = accepted.filterNot { it.id in trustedIds }
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            modifier = Modifier.fillMaxSize().padding(16.dp),
            shape = MaterialTheme.shapes.extraLarge,
            color = MaterialTheme.colorScheme.surface,
            tonalElevation = 6.dp,
        ) {
            Column(Modifier.fillMaxSize()) {
                Row(
                    Modifier.fillMaxWidth().padding(start = 20.dp, top = 12.dp, end = 8.dp, bottom = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(stringResource(R.string.cheer_picker_title), Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                    TextButton(onDismiss) { Text(stringResource(R.string.cheer_picker_cancel)) }
                    TextButton(onClick = { onDone(selected) }) { Text(stringResource(R.string.cheer_picker_done)) }
                }
                HorizontalDivider()
                LazyColumn(
                    Modifier.weight(1f),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    item { Text(stringResource(R.string.cheer_picker_trusted), Modifier.padding(start = 4.dp, top = 4.dp, bottom = 8.dp), style = MaterialTheme.typography.titleSmall) }
                    if (trusted.isEmpty()) {
                        item {
                            OutlinedCard(Modifier.fillMaxWidth()) {
                                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text(stringResource(R.string.cheer_picker_no_trusted), fontWeight = FontWeight.SemiBold)
                                    Text(stringResource(R.string.cheer_picker_trusted_hint), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    TextButton(onSetUpTrustedContacts) { Text(stringResource(R.string.cheer_picker_setup_trusted)) }
                                }
                            }
                        }
                    } else {
                        items(trusted, key = SocialPerson::id) { person -> CheerInvitationRow(person, person.id in selected) { selected = selected.toggle(person.id) } }
                    }
                    if (others.isNotEmpty()) {
                        item { Text(stringResource(R.string.cheer_picker_others), Modifier.padding(start = 4.dp, top = 16.dp, bottom = 8.dp), style = MaterialTheme.typography.titleSmall) }
                        items(others, key = SocialPerson::id) { person -> CheerInvitationRow(person, person.id in selected) { selected = selected.toggle(person.id) } }
                    }
                    item {
                        Text(
                            stringResource(R.string.cheer_picker_privacy),
                            Modifier.padding(horizontal = 4.dp, vertical = 16.dp),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CheerInvitationRow(person: SocialPerson, checked: Boolean, onToggle: () -> Unit) {
    Surface(onClick = onToggle, modifier = Modifier.fillMaxWidth(), color = MaterialTheme.colorScheme.surface) {
        Row(Modifier.padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            SocialAvatar(person)
            Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                Text(person.displayName, color = MaterialTheme.colorScheme.onSurface)
                person.username?.takeIf(String::isNotBlank)?.let { Text("@$it", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            }
            Checkbox(checked = checked, onCheckedChange = { onToggle() })
        }
    }
}

private fun Set<String>.toggle(id: String): Set<String> = if (id in this) this - id else this + id

@Composable
fun NotificationInbox(
    notifications: List<InboxNotification>,
    onOpen: (NotificationCenterItem) -> Unit,
) {
    val presentations = remember(notifications) { NotificationPresentationPolicy.items(notifications) }
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item { Text(stringResource(R.string.inbox_title), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold) }
        NotificationCenterSection.entries.forEach { section ->
            val sectionItems = presentations.filter { it.presentation.section == section }
            if (sectionItems.isNotEmpty()) {
                item("section:${section.name}") {
                    Text(
                        text = stringResource(
                            when (section) {
                                NotificationCenterSection.NEEDS_YOU -> R.string.inbox_needs_you
                                NotificationCenterSection.UPDATES -> R.string.inbox_updates
                                NotificationCenterSection.CHEERS_AND_MILESTONES -> R.string.inbox_cheers_milestones
                            },
                        ),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                }
                items(sectionItems, key = NotificationCenterItem::id) { item ->
                    OutlinedCard({ onOpen(item) }, Modifier.fillMaxWidth()) {
                        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.Top) {
                            Icon(
                                imageVector = when (section) {
                                    NotificationCenterSection.NEEDS_YOU -> Icons.Outlined.NotificationsActive
                                    NotificationCenterSection.UPDATES -> Icons.Outlined.Notifications
                                    NotificationCenterSection.CHEERS_AND_MILESTONES -> Icons.Outlined.FavoriteBorder
                                },
                                contentDescription = null,
                            )
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(item.primary.message, fontWeight = if (item.unread) FontWeight.SemiBold else FontWeight.Normal)
                                if (item.additionalCount > 0) {
                                    Text(
                                        stringResource(R.string.inbox_additional_count, item.additionalCount),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                            if (item.unread) Badge()
                        }
                    }
                }
            }
        }
        if (notifications.isEmpty()) item { Text(stringResource(R.string.inbox_empty), Modifier.padding(24.dp)) }
    }
}

@Composable
fun NotificationDetail(notification: InboxNotification?) {
    LazyColumn(
        Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Text(
                stringResource(R.string.inbox_detail_title),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
            )
        }
        item { Text(notification?.message.orEmpty(), style = MaterialTheme.typography.bodyLarge) }
    }
}

/** Pick a trusted contact from accepted in-app connections; nothing from the phone's contact book is used. */
@Composable
fun TrustedConnectionPickerDialog(
    connections: List<SocialPerson>,
    close: () -> Unit,
    confirm: (TrustedContact) -> Unit,
) {
    AlertDialog(
        onDismissRequest = close,
        title = { Text(stringResource(R.string.safety_add_contact)) },
        text = {
            if (connections.isEmpty()) {
                Text(stringResource(R.string.safety_contacts_empty))
            } else {
                LazyColumn {
                    items(connections, key = SocialPerson::id) { person ->
                        Row(
                            Modifier.fillMaxWidth().padding(vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            SocialAvatar(person)
                            Spacer(Modifier.width(12.dp))
                            Text(person.displayName, Modifier.weight(1f))
                            TextButton({ confirm(TrustedContact(person.id, person.displayName, "push", "", false)) }) {
                                Text(stringResource(R.string.safety_add_contact))
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(close) { Text(stringResource(android.R.string.cancel)) } },
    )
}
