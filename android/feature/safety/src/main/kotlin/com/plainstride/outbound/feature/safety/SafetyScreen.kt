package com.plainstride.outbound.feature.safety

import androidx.compose.foundation.layout.*
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
import com.plainstride.outbound.core.designsystem.MapCoordinate
import com.plainstride.outbound.core.designsystem.PlainstrideRouteMap
import com.plainstride.outbound.feature.social.SocialAvatar
import com.plainstride.outbound.feature.social.SocialPerson

interface TrustedContactStore {
 suspend fun contacts():List<TrustedContact>
 suspend fun save(contact:TrustedContact)
 suspend fun remove(id:String)
 suspend fun migrateToServerBackedContacts()
 suspend fun pull(accountId:String)
 suspend fun push()
}
enum class NotificationPermissionState { UNKNOWN, GRANTED, DENIED, PERMANENTLY_DENIED }

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
