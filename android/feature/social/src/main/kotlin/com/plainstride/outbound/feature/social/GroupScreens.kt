package com.plainstride.outbound.feature.social

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.foundation.lazy.LazyListScope

@Composable fun GroupCreateScreen(connections:List<SocialPerson>,close:()->Unit,selectTemplate:(String)->Unit,create:(String,String?,String?,List<SocialPerson>,(Boolean)->Unit)->Unit)=Dialog(onDismissRequest=close){
 var template by rememberSaveable{mutableStateOf<String?>(null)};var creating by rememberSaveable{mutableStateOf(false)}
 var name by rememberSaveable{mutableStateOf("")};var city by rememberSaveable{mutableStateOf("")};var selected by remember{mutableStateOf(setOf<String>())}
 Surface(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.background){
  if(template==null) GroupTemplateChooser(close){selectTemplate(it);template=it} else Column {
   Row(Modifier.padding(16.dp),verticalAlignment=Alignment.CenterVertically){IconButton(close){Icon(Icons.Outlined.Close,stringResource(R.string.social_done))};Text(stringResource(R.string.group_create_title),Modifier.weight(1f),style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold)}
   LazyColumn(Modifier.weight(1f),contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(12.dp)){
    item{GroupCreationHero(template!!)}
    if(template=="motivation"){
     item{Text(stringResource(R.string.group_create_people),style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.SemiBold);Text(stringResource(R.string.group_create_selected,selected.size),style=MaterialTheme.typography.bodySmall)}
     items(connections,key=SocialPerson::id){person->val checked=person.id in selected;Card(onClick={selected=if(checked)selected-person.id else selected+person.id}){Row(Modifier.fillMaxWidth().padding(12.dp),verticalAlignment=Alignment.CenterVertically){SocialAvatar(person);Spacer(Modifier.width(12.dp));Text(person.displayName,Modifier.weight(1f));Checkbox(checked,{selected=if(checked)selected-person.id else selected+person.id})}}}
    }
    item{OutlinedTextField(name,{name=it.take(80)},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.group_create_name))},supportingText={Text(if(template=="activities")stringResource(R.string.group_create_community_name_help) else stringResource(R.string.group_create_name_help))})}
    if(template=="activities") item{OutlinedTextField(city,{city=it.take(120)},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.group_create_city))},singleLine=true)}
    if(template=="activities") item{Text(stringResource(R.string.social_groups_create_community_access),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
   }
   Button({if(!creating){creating=true;create(template!!,name.trim().ifEmpty{null},city.trim().ifEmpty{null},connections.filter{it.id in selected}){created->creating=false;if(created)close()}}},Modifier.fillMaxWidth().padding(16.dp).heightIn(min=50.dp),enabled=!creating&&(template=="activities"&&name.isNotBlank()||template=="motivation"&&selected.isNotEmpty())){if(creating)CircularProgressIndicator(Modifier.size(20.dp),strokeWidth=2.dp)else Text(stringResource(R.string.group_create_action))}
  }
 }
}

@Composable private fun GroupTemplateChooser(close:()->Unit,choose:(String)->Unit){
 Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
  Row(verticalAlignment=Alignment.CenterVertically){IconButton(close){Icon(Icons.Outlined.Close,stringResource(R.string.social_done))};Text(stringResource(R.string.social_groups_create_choose_title),Modifier.weight(1f),style=MaterialTheme.typography.headlineSmall,fontWeight=FontWeight.Bold)}
  Text(stringResource(R.string.social_groups_create_choose_detail),color=MaterialTheme.colorScheme.onSurfaceVariant)
  GroupTemplateCard(R.string.social_groups_template_private_title,R.string.social_groups_template_private_detail,false){choose("motivation")}
  GroupTemplateCard(R.string.social_groups_template_community_title,R.string.social_groups_template_community_detail,true){choose("activities")}
 }
}

@Composable private fun GroupTemplateCard(title:Int,detail:Int,isCommunity:Boolean,onClick:()->Unit){
 ElevatedCard(onClick=onClick){Row(Modifier.fillMaxWidth().padding(18.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(14.dp)){
  Surface(Modifier.size(44.dp),shape=androidx.compose.foundation.shape.CircleShape,color=MaterialTheme.colorScheme.primary.copy(alpha=.12f)){Box(contentAlignment=Alignment.Center){GroupTypeIcon(isCommunity,Modifier.size(25.dp),MaterialTheme.colorScheme.primary)}}
  Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(4.dp)){Text(stringResource(title),style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.SemiBold);Text(stringResource(detail),style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)}
  Icon(Icons.Outlined.ChevronRight,null,tint=MaterialTheme.colorScheme.onSurfaceVariant)
 }}
}

@Composable private fun GroupCreationHero(template:String){
 ElevatedCard{Row(Modifier.fillMaxWidth().padding(20.dp),verticalAlignment=Alignment.Top,horizontalArrangement=Arrangement.spacedBy(14.dp)){
  Surface(Modifier.size(52.dp),shape=androidx.compose.foundation.shape.CircleShape,color=MaterialTheme.colorScheme.primary.copy(alpha=.12f)){Box(contentAlignment=Alignment.Center){GroupTypeIcon(template=="activities",Modifier.size(30.dp),MaterialTheme.colorScheme.primary)}}
  Column(verticalArrangement=Arrangement.spacedBy(7.dp)){Text(if(template=="activities")stringResource(R.string.social_groups_create_community_hero_title) else stringResource(R.string.social_groups_create_private_hero_title),style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold);Text(if(template=="activities")stringResource(R.string.social_groups_create_community_hero_detail) else stringResource(R.string.social_groups_create_private_hero_detail),style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)}
 }}
}

@Composable fun GroupTypeIcon(isCommunity:Boolean,modifier:Modifier=Modifier,tint:Color=MaterialTheme.colorScheme.primary){
 if(isCommunity) Icon(Icons.Filled.Groups,contentDescription=null,modifier=modifier,tint=tint) else GroupMarkIcon(modifier,tint)
}

@Composable fun GroupMarkIcon(modifier:Modifier=Modifier,tint:Color=MaterialTheme.colorScheme.primary){
 androidx.compose.foundation.Canvas(modifier){
  val scale=minOf(size.width,size.height)/19f;val center=Offset(size.width/2f,size.height/2f)
  drawCircle(tint,7.2f*scale,center,style=Stroke(1.7f*scale))
  listOf(-1f,1f).forEach{side->
   val head=Offset(center.x+side*1.55f*scale,center.y-1.55f*scale);drawCircle(tint,1.45f*scale,head)
   val left=center.x+(side*1.75f-2.1f)*scale;val top=center.y+(.4f)*scale
   rotate(side*10f,pivot=Offset(center.x+side*1.75f*scale,center.y+1.65f*scale)){drawRoundRect(tint,topLeft=Offset(left,top),size=Size(4.2f*scale,2.5f*scale),cornerRadius=androidx.compose.ui.geometry.CornerRadius(1.25f*scale))}
  }
 }
}

@Composable
fun GroupDetailScreen(
    group: GroupSummary,
    close: () -> Unit,
    cheer: (String, String) -> Unit,
    focus: (String, Int?, Boolean) -> Unit,
    archive: () -> Unit,
    invite: () -> Unit,
    saveSettings: (String, String, Int, String, String, Boolean, Boolean) -> Unit,
    commitment: (Int?, Boolean) -> Unit,
    leave: () -> Unit,
    remove: (String) -> Unit,
    cancelInvitation: (String) -> Unit,
    changeRole: (String, String) -> Unit,
    transferOwnership: (String) -> Unit,
    trackMembersOpened: (Int) -> Unit,
    planActivity: () -> Unit,
    requestJoin: () -> Unit,
    openActivity: (String) -> Unit,
    publishNotice: (String?, String, Boolean) -> Unit,
    markNoticesRead: () -> Unit,
) {
    var settings by rememberSaveable { mutableStateOf(false) }
    var focusOpen by rememberSaveable { mutableStateOf(false) }
    var showMembers by rememberSaveable { mutableStateOf(false) }
    var showNoticeComposer by rememberSaveable { mutableStateOf(false) }
    var noticeTitle by rememberSaveable { mutableStateOf("") }
    var noticeBody by rememberSaveable { mutableStateOf("") }
    var pinNotice by rememberSaveable { mutableStateOf(false) }
    var pendingRemoval by remember { mutableStateOf<GroupMember?>(null) }
    val orderedMembers = remember(group.members) {
        group.members.withIndex()
            .sortedWith(compareBy<IndexedValue<GroupMember>> {
                when (it.value.role) { "owner" -> 0; "admin" -> 1; else -> 2 }
            }.thenBy { it.index })
            .map { it.value }
    }
    val canManage = group.currentUserRole in setOf("owner", "admin") && group.lifecycle != "archived"
    val canInviteMore = canManage && group.memberCount + group.invitations.count { it.status == "pending" } < group.memberLimit
    fun memberCanBeRemoved(member: GroupMember) = canManage && !member.isCurrentUser && member.role != "owner" &&
        (group.currentUserRole == "owner" || member.role == "member")

    val context = LocalContext.current
    val isCommunity = group.trustPolicy == "community"
    val isMember = group.currentUserRole != null || orderedMembers.any { it.isCurrentUser }
    val dateFormatter = remember(context) { java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT, context.resources.configuration.locales[0]) }

    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(close) { Icon(Icons.Outlined.ArrowBack, stringResource(R.string.social_done)) }
                Text(group.name, Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 1)
                if (group.currentUserRole in setOf("owner", "admin")) IconButton({ settings = true }) { Icon(Icons.Outlined.Settings, stringResource(R.string.group_manage)) }
            }
            LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                item {
                    ElevatedCard {
                        Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(stringResource(if (isCommunity) R.string.group_community_badge else R.string.group_private_badge), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                if (group.featured) Text(stringResource(R.string.group_featured_badge), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                                if (group.organizationVerificationState == "verified") Text(stringResource(R.string.group_verified_badge), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                            }
                            Text(group.description ?: stringResource(R.string.group_detail_inspiration), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            if (isCommunity && !group.city.isNullOrBlank()) {
                                Text(group.city, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Text(stringResource(R.string.social_members, group.memberCount), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                if (isCommunity) {
                    if (group.currentUserRole == null && !isMember && group.joinPolicy != "invite_only") item {
                        Button(requestJoin, Modifier.fillMaxWidth(), enabled = group.joinPolicy != "request" || group.pendingRequest?.status != "pending") {
                            Text(stringResource(when {
                                group.joinPolicy == "request" && group.pendingRequest?.status == "pending" -> R.string.group_request_pending
                                group.joinPolicy == "request" -> R.string.group_request_to_join
                                else -> R.string.group_open_join
                            }))
                        }
                    }
                    if (!group.description.isNullOrBlank()) item {
                        ElevatedCard { Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(stringResource(R.string.group_about), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                            Text(group.description, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(when (group.joinPolicy) { "request" -> stringResource(R.string.group_request_to_join); "open" -> stringResource(R.string.group_open_join); else -> stringResource(R.string.group_invite_only) }, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                        } }
                    }
                    if (group.notices.isNotEmpty()) item {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(stringResource(R.string.group_notices_heading), Modifier.weight(1f), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                if (group.unreadNoticeCount > 0) Text(stringResource(R.string.group_unread), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                            }
                            group.notices.forEach { notice -> ElevatedCard {
                                Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    Row(verticalAlignment = Alignment.CenterVertically) { if (notice.pinned) Icon(Icons.Outlined.PushPin, null, Modifier.size(16.dp)); Text(notice.title ?: stringResource(R.string.group_notice_update), Modifier.weight(1f), fontWeight = FontWeight.SemiBold); notice.publishedAt?.let { raw -> Text(runCatching { dateFormatter.format(java.util.Date.from(java.time.OffsetDateTime.parse(raw).toInstant())) }.getOrDefault(""), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant) } }
                                    Text(notice.body)
                                }
                            } }
                            if (group.unreadNoticeCount > 0 && isMember) TextButton(markNoticesRead) { Text(stringResource(R.string.group_mark_notices_read)) }
                        }
                    }
                    upcomingActivityItems(group, dateFormatter, openActivity)
                    if (isMember) memberSection(group, orderedMembers, canInviteMore, invite, showMembers = { showMembers = true; trackMembersOpened(group.memberCount.takeIf { it > 0 } ?: group.members.size) })
                    if (canManage && group.capabilities.notices) item { OutlinedButton({ showNoticeComposer = true }, Modifier.fillMaxWidth()) { Text(stringResource(R.string.group_post_update)) } }
                    item { Button(planActivity, Modifier.fillMaxWidth()) { Text(stringResource(R.string.group_plan_activity)) } }
                } else {
                    upcomingActivityItems(group, dateFormatter, openActivity)
                    item { privateFocusCard(group, focusOpen = { focusOpen = true }) }
                    memberSection(group, orderedMembers, canInviteMore, invite, showMembers = { showMembers = true; trackMembersOpened(group.memberCount.takeIf { it > 0 } ?: group.members.size) })
                    if (group.invitations.isNotEmpty()) items(group.invitations.filter { it.status == "pending" }, key = GroupInvitationSnapshot::id) { invitation ->
                        ElevatedCard { Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            SocialAvatar(invitation.recipient ?: SocialPerson(id = invitation.id, displayName = stringResource(R.string.group_invited_person)))
                            Text(invitation.recipient?.displayName ?: stringResource(R.string.group_invited_person), Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
                            Text(stringResource(R.string.group_invited_status), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        } }
                    }
                    item { Button(planActivity, Modifier.fillMaxWidth()) { Text(stringResource(R.string.group_plan_activity)) } }
                    if (group.recentMoments.isNotEmpty()) item { momentsCard(group, dateFormatter) }
                    group.history?.takeIf { it.isNotEmpty() }?.let { history -> item { historyCard(history) } }
                }
            }
        }
    }
    if (focusOpen) GroupFocusDialog(group, { focusOpen = false }, focus, commitment)
    if (settings) GroupSettingsDialog(
        group = group,
        close = { settings = false },
        save = saveSettings,
        invite = invite,
        openFocus = { focusOpen = true },
        archive = archive,
        leave = leave,
        remove = remove,
        cancelInvitation = cancelInvitation,
        changeRole = changeRole,
        transferOwnership = transferOwnership,
    )
    if (showNoticeComposer) AlertDialog(
        onDismissRequest = { showNoticeComposer = false },
        title = { Text(stringResource(R.string.group_post_update)) },
        text = { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedTextField(noticeTitle, { noticeTitle = it.take(120) }, label = { Text(stringResource(R.string.group_notice_title)) }, singleLine = true)
            OutlinedTextField(noticeBody, { noticeBody = it.take(1000) }, label = { Text(stringResource(R.string.group_notice_body)) }, minLines = 3)
            Row(verticalAlignment = Alignment.CenterVertically) { Checkbox(pinNotice, { pinNotice = it }); Text(stringResource(R.string.group_notice_pin)) }
        } },
        confirmButton = { TextButton(onClick = { publishNotice(noticeTitle, noticeBody, pinNotice); noticeTitle = ""; noticeBody = ""; pinNotice = false; showNoticeComposer = false }, enabled = noticeBody.isNotBlank()) { Text(stringResource(R.string.social_done)) } },
        dismissButton = { TextButton({ showNoticeComposer = false }) { Text(stringResource(R.string.social_cancel)) } },
    )
    if (showMembers) {
        Dialog(onDismissRequest = { showMembers = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                Column {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        IconButton({ showMembers = false }) { Icon(Icons.Outlined.ArrowBack, stringResource(R.string.social_done)) }
                        Text(stringResource(R.string.group_members_manage), Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                        if (canInviteMore) IconButton(invite) { Icon(Icons.Outlined.PersonAdd, stringResource(R.string.group_invite_connections)) }
                    }
                    LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        items(orderedMembers, key = { it.person.id }) { member ->
                            ElevatedCard {
                                Column(Modifier.padding(14.dp)) {
                                    Row(verticalAlignment = Alignment.CenterVertically) {
                                        SocialAvatar(member.person)
                                        Spacer(Modifier.width(12.dp))
                                        Column(Modifier.weight(1f)) {
                                            Text(member.person.displayName, fontWeight = FontWeight.SemiBold)
                                            Text(
                                                if (group.trustPolicy == "community") member.role.replaceFirstChar { it.uppercase() }
                                                else when {
                                                    member.skipped -> stringResource(R.string.group_skipping)
                                                    member.target != null -> stringResource(R.string.group_member_progress, member.completed, member.target!!)
                                                    else -> stringResource(R.string.group_contributed, member.completed)
                                                },
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                        }
                                        if (group.trustPolicy != "community" && !member.isCurrentUser) {
                                            IconButton({ cheer(member.person.id, "encouragement") }) { Icon(Icons.Outlined.FavoriteBorder, stringResource(R.string.social_cheer)) }
                                        }
                                        if (memberCanBeRemoved(member)) {
                                            IconButton({ pendingRemoval = member }) {
                                                Icon(Icons.Outlined.RemoveCircleOutline, stringResource(R.string.group_member_remove_action))
                                            }
                                        }
                                    }
                                    if (group.trustPolicy != "community") {
                                        member.recentActivity?.let { activity ->
                                            Text(activity.title ?: activity.type, Modifier.padding(top = 8.dp))
                                            Text(listOfNotNull(activity.durationSecs?.let { "${it / 60} min" }, activity.distanceM?.let { "%.2f km".format(it / 1000) }).joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    pendingRemoval?.let { member ->
        AlertDialog(
            onDismissRequest = { pendingRemoval = null },
            title = { Text(stringResource(R.string.group_member_remove_confirm_title)) },
            text = { Text(stringResource(R.string.group_remove_member, member.person.displayName)) },
            confirmButton = { TextButton({ remove(member.person.id); pendingRemoval = null }) { Text(stringResource(R.string.group_member_remove_action)) } },
            dismissButton = { TextButton({ pendingRemoval = null }) { Text(stringResource(R.string.social_cancel)) } },
        )
    }
}

private fun LazyListScope.upcomingActivityItems(group: GroupSummary, dateFormat: java.text.DateFormat, openActivity: (String) -> Unit) {
    if (group.upcomingActivities.isNotEmpty()) item {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.group_up_next), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
            group.upcomingActivities.forEach { activity ->
                ElevatedCard(onClick = { openActivity(activity.id) }) {
                    Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Surface(Modifier.size(42.dp), shape = androidx.compose.foundation.shape.CircleShape, color = MaterialTheme.colorScheme.primary.copy(alpha = .12f)) {
                            Box(contentAlignment = Alignment.Center) { Icon(Icons.Outlined.Event, null, tint = MaterialTheme.colorScheme.primary) }
                        }
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(activity.title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, maxLines = 1)
                            val date = runCatching { dateFormat.format(java.util.Date.from(java.time.OffsetDateTime.parse(activity.startsAt).toInstant())) }.getOrDefault(activity.startsAt)
                            Text(listOfNotNull(date, activity.locationName?.takeIf(String::isNotBlank), stringResource(R.string.group_going_count, activity.attendeeCount)).joinToString(" · "), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
                        }
                        Icon(Icons.Outlined.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

private fun LazyListScope.memberSection(group: GroupSummary, members: List<GroupMember>, canInviteMore: Boolean, invite: () -> Unit, showMembers: () -> Unit) {
    item {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.group_members_heading), Modifier.weight(1f), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (canInviteMore) IconButton(invite) { Icon(Icons.Outlined.PersonAdd, stringResource(R.string.group_invite_connections)) }
            }
            ElevatedCard {
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        members.take(3).forEach { member ->
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                SocialAvatar(member.person)
                                Text(member.person.displayName.trim().split(Regex("\\s+")).firstOrNull().orEmpty(), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium, maxLines = 1)
                            }
                        }
                    }
                    TextButton(showMembers) { Text(stringResource(R.string.group_members_more_action)) }
                }
            }
        }
    }
}

@Composable private fun privateFocusCard(group: GroupSummary, focusOpen: () -> Unit) {
    val isOwner = group.currentUserRole == "owner"
    val commitment = group.members.firstOrNull { it.isCurrentUser }?.target
    ElevatedCard {
        Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.group_weekly_theme), Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                if (isOwner || (group.week.focusConfigured && group.focusMode in setOf("theme", "personal_targets"))) {
                    TextButton(focusOpen) { Text(stringResource(if (!group.week.focusConfigured) R.string.group_focus_choose else R.string.group_edit)) }
                }
            }
            when {
                !group.week.focusConfigured -> Text(stringResource(if (isOwner) R.string.group_theme_unconfigured_owner else R.string.group_theme_unconfigured_member), color = MaterialTheme.colorScheme.onSurfaceVariant)
                group.week.themeTitle != null -> {
                    Text(group.week.themeTitle, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                    group.week.themeNote?.takeIf(String::isNotBlank)?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    Text(stringResource(R.string.group_theme_activity_count, group.completed), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    commitment?.let { Text(stringResource(R.string.group_commitment_progress, group.members.firstOrNull { m -> m.isCurrentUser }?.completed ?: 0, it), fontWeight = FontWeight.SemiBold) }
                }
                group.focusMode == "none" -> Text(stringResource(R.string.group_focus_none_detail), color = MaterialTheme.colorScheme.onSurfaceVariant)
                group.target != null -> {
                    LinearProgressIndicator({ (group.completed.toFloat() / (group.target ?: 1)).coerceIn(0f, 1f) }, Modifier.fillMaxWidth())
                    Text(stringResource(R.string.social_group_progress, group.completed, group.target!!), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                else -> Text(stringResource(R.string.group_no_numeric_focus), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            val next = group.upcomingFocus
            if (next.focusConfigured && (next.themeKey != group.week.themeKey || next.themeTitle != group.week.themeTitle) && !next.themeTitle.isNullOrBlank()) {
                HorizontalDivider()
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(R.string.group_next_week), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(next.themeTitle, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                    next.themeNote?.takeIf(String::isNotBlank)?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
            }
        }
    }
}

@Composable private fun momentsCard(group: GroupSummary, dateFormat: java.text.DateFormat) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.group_recent_moments), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        ElevatedCard { Column(Modifier.padding(horizontal = 14.dp)) {
            group.recentMoments.forEach { moment ->
                Row(Modifier.fillMaxWidth().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(if (moment.type == "cheer") Icons.Outlined.Favorite else Icons.Outlined.AutoAwesome, null, tint = MaterialTheme.colorScheme.primary)
                    Text(moment.title ?: stringResource(if (moment.type == "cheer") R.string.group_moment_cheer else R.string.group_moment_activity), Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                    Text(runCatching { dateFormat.format(java.util.Date.from(java.time.OffsetDateTime.parse(moment.createdAt).toInstant())) }.getOrDefault(""), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        } }
    }
}

@Composable private fun historyCard(history: List<GroupWeekHistory>) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.group_history_heading), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        ElevatedCard { Column(Modifier.padding(horizontal = 14.dp)) {
            history.take(6).forEach { week ->
                Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(runCatching { java.time.OffsetDateTime.parse(week.startsAt).toLocalDate().toString() }.getOrDefault(week.startsAt))
                        week.themeTitle?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                    Text(stringResource(if (week.state == "completed") R.string.group_completed else R.string.group_week_recorded), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        } }
    }
}

@Composable fun GroupActivityComposer(close:()->Unit, create:(String,String?)->Unit) {
 var title by rememberSaveable { mutableStateOf("") }; var location by rememberSaveable { mutableStateOf("") }
 AlertDialog(onDismissRequest=close,title={Text(stringResource(R.string.group_plan_activity))},text={Column(verticalArrangement=Arrangement.spacedBy(10.dp)){OutlinedTextField(title,{title=it.take(80)},label={Text(stringResource(R.string.group_activity_title))},singleLine=true);OutlinedTextField(location,{location=it.take(120)},label={Text(stringResource(R.string.group_activity_location))},singleLine=true);Text(stringResource(R.string.group_activity_timing),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}},confirmButton={TextButton({create(title.trim(),location.trim().takeIf{it.isNotEmpty()})}){Text(stringResource(R.string.social_done))}},dismissButton={TextButton(close){Text(stringResource(R.string.social_cancel))}})
}

@Composable private fun GroupFocusDialog(group:GroupSummary,close:()->Unit,focus:(String,Int?,Boolean)->Unit,commitment:(Int?,Boolean)->Unit){var mode by remember{mutableStateOf(group.focusMode)};var target by remember{mutableIntStateOf(group.target?:3)};var next by remember{mutableStateOf(false)};AlertDialog(onDismissRequest=close,title={Text(stringResource(R.string.group_weekly_focus))},text={Column{listOf("personal_targets" to R.string.group_focus_personal,"shared_target" to R.string.group_focus_shared,"none" to R.string.group_focus_none).forEach{(value,label)->Row(verticalAlignment=Alignment.CenterVertically){RadioButton(mode==value,{mode=value});Text(stringResource(label))}};if(mode!="none")Row(verticalAlignment=Alignment.CenterVertically){IconButton({target=(target-1).coerceAtLeast(1)}){Icon(Icons.Outlined.Remove,null)};Text(target.toString());IconButton({target=(target+1).coerceAtMost(14)}){Icon(Icons.Outlined.Add,null)}};Row(verticalAlignment=Alignment.CenterVertically){Checkbox(next,{next=it});Text(stringResource(R.string.group_apply_next_week))};if(mode=="personal_targets")TextButton({commitment(null,true);close()}){Text(stringResource(R.string.group_skip_week))}}},confirmButton={TextButton({if(mode=="personal_targets")commitment(target,false) else focus(mode,target.takeIf{mode=="shared_target"},next);close()}){Text(stringResource(R.string.social_done))}},dismissButton={TextButton(close){Text(stringResource(R.string.social_decline))}})}

@Composable private fun GroupSettingsDialog(
    group: GroupSummary,
    close: () -> Unit,
    save: (String, String, Int, String, String, Boolean, Boolean) -> Unit,
    invite: () -> Unit,
    openFocus: () -> Unit,
    archive: () -> Unit,
    leave: () -> Unit,
    remove: (String) -> Unit,
    cancelInvitation: (String) -> Unit,
    changeRole: (String, String) -> Unit,
    transferOwnership: (String) -> Unit,
) {
    var name by remember(group.id) { mutableStateOf(group.name) }
    var city by remember(group.id) { mutableStateOf(group.city.orEmpty()) }
    var resetWeekday by remember(group.id) { mutableIntStateOf(group.resetWeekday.coerceIn(1, 7)) }
    var timeZone by remember(group.id) { mutableStateOf(group.timeZone.ifBlank { java.util.TimeZone.getDefault().id }) }
    var calendarApply by remember(group.id) { mutableStateOf("next_week") }
    var savedCalendarApply by remember(group.id) { mutableStateOf("next_week") }
    var notificationsMuted by remember(group.id) { mutableStateOf(group.currentUserMuted) }
    var weekdayMenu by remember { mutableStateOf(false) }
    val hasUnsavedChanges = name.trim() != group.name || city.trim() != group.city.orEmpty() ||
        resetWeekday != group.resetWeekday || timeZone.trim() != group.timeZone ||
        calendarApply != savedCalendarApply || notificationsMuted != group.currentUserMuted
    val canManage = group.currentUserRole in setOf("owner", "admin")
    val canInvite = canManage && group.lifecycle != "archived"
    val weekdays = java.text.DateFormatSymbols.getInstance().weekdays

    Dialog(onDismissRequest = { if (!hasUnsavedChanges) close() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Column {
                Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(close) { Icon(Icons.Outlined.ArrowBack, stringResource(R.string.social_done)) }
                    Text(stringResource(R.string.group_manage), Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                    TextButton({
                        save(name, city, resetWeekday, timeZone, calendarApply, notificationsMuted, calendarApply != savedCalendarApply)
                        savedCalendarApply = calendarApply
                    }, enabled = hasUnsavedChanges) {
                        Text(stringResource(R.string.group_settings_save))
                    }
                }
                LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (group.currentUserRole == "owner" || (group.week.focusConfigured && group.focusMode in setOf("theme", "personal_targets"))) {
                                OutlinedButton(openFocus, Modifier.fillMaxWidth()) { Text(stringResource(if (group.currentUserRole == "owner") R.string.group_weekly_theme else R.string.group_my_commitment)) }
                            }
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(stringResource(R.string.group_mute), Modifier.weight(1f))
                                Switch(notificationsMuted, { notificationsMuted = it })
                            }
                        }
                    }
                    if (canManage) {
                        item {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(stringResource(R.string.group_owner_controls), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                                OutlinedTextField(name, { name = it.take(80) }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.group_create_name)) }, singleLine = true)
                                OutlinedTextField(city, { city = it.take(120) }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.group_base_location)) }, singleLine = true)
                                if (canInvite) OutlinedButton(invite, Modifier.fillMaxWidth()) { Text(stringResource(R.string.group_invite_connections)) }
                            }
                        }
                        if (group.invitations.isNotEmpty()) {
                            item { Text(stringResource(R.string.group_pending_invitations), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold) }
                            items(group.invitations, key = GroupInvitationSnapshot::id) { invitation ->
                                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                    Text(invitation.recipient?.displayName ?: stringResource(R.string.group_invited_person), Modifier.weight(1f))
                                    TextButton({ cancelInvitation(invitation.id) }) { Text(stringResource(R.string.group_invitation_cancel)) }
                                }
                            }
                        }
                        item {
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(stringResource(R.string.group_week_settings), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                                Box {
                                    TextButton({ weekdayMenu = true }) { Text("${stringResource(R.string.group_reset_day)} · ${weekdays[(resetWeekday % 7) + 1]}") }
                                    DropdownMenu(weekdayMenu, { weekdayMenu = false }) {
                                        (1..7).forEach { day -> DropdownMenuItem(text = { Text(weekdays[(day % 7) + 1]) }, onClick = { resetWeekday = day; weekdayMenu = false }) }
                                    }
                                }
                                OutlinedTextField(timeZone, { timeZone = it.take(80) }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.group_timezone)) }, singleLine = true)
                                Text(stringResource(R.string.group_calendar_apply), style = MaterialTheme.typography.labelLarge)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    FilterChip(calendarApply == "now", { calendarApply = "now" }, label = { Text(stringResource(R.string.group_apply_now)) })
                                    FilterChip(calendarApply == "next_week", { calendarApply = "next_week" }, label = { Text(stringResource(R.string.group_apply_next)) })
                                }
                            }
                        }
                        if (group.members.any { !it.isCurrentUser }) {
                            item { Text(stringResource(R.string.group_members_manage), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold) }
                            items(group.members.filter { !it.isCurrentUser }, key = { it.person.id }) { member ->
                                Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                                    Text(member.person.displayName, style = MaterialTheme.typography.bodyLarge)
                                    Text(member.role.replaceFirstChar { it.uppercase() }, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                        if (group.currentUserRole == "owner" && member.role != "owner") {
                                            TextButton({ changeRole(member.person.id, if (member.role == "admin") "member" else "admin") }) { Text(stringResource(if (member.role == "admin") R.string.group_make_member else R.string.group_make_admin)) }
                                            TextButton({ transferOwnership(member.person.id) }) { Text(stringResource(R.string.group_transfer_ownership)) }
                                        }
                                        if (member.role != "owner" && (group.currentUserRole == "owner" || (group.currentUserRole == "admin" && member.role == "member"))) {
                                            TextButton({ remove(member.person.id) }, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text(stringResource(R.string.group_remove_member, member.person.displayName)) }
                                        }
                                    }
                                }
                            }
                        }
                        item {
                            TextButton(archive) { Text(stringResource(if (group.lifecycle == "archived") R.string.social_group_reactivate else R.string.social_group_archive)) }
                        }
                    } else if (group.currentUserRole == "member") {
                        item { TextButton(leave, colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error)) { Text(stringResource(R.string.group_leave)) } }
                    }
                }
            }
        }
    }
}

@Composable
fun GroupLoadingScreen(loading: Boolean, unavailable: Boolean, retry: () -> Unit, close: () -> Unit) {
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column {
            IconButton(close) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.social_done)) }
            Column(Modifier.weight(1f).fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                if (loading) {
                    CircularProgressIndicator()
                    Spacer(Modifier.height(12.dp))
                    Text(stringResource(R.string.group_loading))
                } else {
                    Icon(Icons.Outlined.WarningAmber, null)
                    Spacer(Modifier.height(12.dp))
                    Text(stringResource(if (unavailable) R.string.group_invitation_unavailable_title else R.string.group_loading_failed_title), style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))
                    Text(stringResource(if (unavailable) R.string.group_invitation_unavailable_detail else R.string.group_loading_failed_detail), textAlign = androidx.compose.ui.text.style.TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.height(16.dp))
                    Button(retry) { Text(stringResource(R.string.group_loading_retry)) }
                }
            }
        }
    }
}

@Composable
fun GroupInvitationPreviewScreen(group: GroupSummary, responding: Boolean, close: () -> Unit, respond: (Boolean) -> Unit) {
    val invitation = group.pendingInvitation ?: return
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconButton(close) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.social_done)) }
                Text(group.name, Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            }
            LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                item {
                    ElevatedCard {
                        Column(Modifier.fillMaxWidth().padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(stringResource(if (group.trustPolicy == "community") R.string.group_community_badge else R.string.group_private_badge), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(group.name, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                            Text(if (group.memberCount == 1) stringResource(R.string.group_invitation_one_member) else stringResource(R.string.social_members, group.memberCount), color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(stringResource(R.string.group_invitation_organizer, group.owner?.displayName.orEmpty()), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
                if (!group.description.isNullOrEmpty()) item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(stringResource(R.string.group_about), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        Text(group.description)
                    }
                }
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Text(stringResource(R.string.group_invitation_title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                        Text(stringResource(R.string.group_invitation_from, invitation.sender.displayName, group.name))
                        Text(stringResource(R.string.group_invitation_preview_detail), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Button({ respond(true) }, enabled = !responding) { Text(stringResource(R.string.social_accept)) }
                            OutlinedButton({ respond(false) }, enabled = !responding) { Text(stringResource(R.string.social_decline)) }
                            if (responding) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                        }
                    }
                }
            }
        }
    }
}
