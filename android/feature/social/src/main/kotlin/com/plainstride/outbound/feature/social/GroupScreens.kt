package com.plainstride.outbound.feature.social

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.ui.window.Dialog

@Composable fun GroupCreateScreen(connections:List<SocialPerson>,close:()->Unit,create:(String,String?,List<SocialPerson>)->Unit)=Dialog(onDismissRequest=close){
 var template by rememberSaveable{mutableStateOf<String?>(null)}
 var name by rememberSaveable{mutableStateOf("")};var selected by remember{mutableStateOf(setOf<String>())}
 Surface(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.background){
  if(template==null) GroupTemplateChooser(close){template=it} else Column {
   Row(Modifier.padding(16.dp),verticalAlignment=Alignment.CenterVertically){IconButton(close){Icon(Icons.Outlined.Close,stringResource(R.string.social_done))};Text(stringResource(R.string.group_create_title),Modifier.weight(1f),style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold)}
   LazyColumn(Modifier.weight(1f),contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(12.dp)){
    item{ElevatedCard{Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(8.dp)){Text(if(template=="activities")stringResource(R.string.group_template_activities_title) else stringResource(R.string.group_template_motivation_title),style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold);Text(if(template=="activities")stringResource(R.string.group_template_activities_detail) else stringResource(R.string.group_template_motivation_detail))}}}
    if(template=="motivation"){
     item{Text(stringResource(R.string.group_create_people),style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.SemiBold);Text(stringResource(R.string.group_create_selected,selected.size),style=MaterialTheme.typography.bodySmall)}
     items(connections,key=SocialPerson::id){person->val checked=person.id in selected;Card(onClick={selected=if(checked)selected-person.id else selected+person.id}){Row(Modifier.fillMaxWidth().padding(12.dp),verticalAlignment=Alignment.CenterVertically){SocialAvatar(person);Spacer(Modifier.width(12.dp));Text(person.displayName,Modifier.weight(1f));Checkbox(checked,{selected=if(checked)selected-person.id else selected+person.id})}}}
    }
    item{OutlinedTextField(name,{name=it.take(80)},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.group_create_name))},supportingText={Text(if(template=="activities")stringResource(R.string.group_create_community_name_help) else stringResource(R.string.group_create_name_help))})}
    if(template=="activities") item{Text(stringResource(R.string.group_create_community_detail),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
   }
   Button({create(template!!,name.trim().ifEmpty{null},connections.filter{it.id in selected})},Modifier.fillMaxWidth().padding(16.dp).heightIn(min=50.dp),enabled=template=="activities"&&name.isNotBlank()||template=="motivation"&&selected.isNotEmpty()){Text(stringResource(R.string.group_create_action))}
  }
 }
}

@Composable private fun GroupTemplateChooser(close:()->Unit,choose:(String)->Unit){
 Column(Modifier.fillMaxSize().padding(20.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
  Row(verticalAlignment=Alignment.CenterVertically){IconButton(close){Icon(Icons.Outlined.Close,stringResource(R.string.social_done))};Text(stringResource(R.string.group_create_choose_title),style=MaterialTheme.typography.headlineSmall,fontWeight=FontWeight.Bold)}
  Text(stringResource(R.string.group_create_choose_detail),color=MaterialTheme.colorScheme.onSurfaceVariant)
  ElevatedCard(onClick={choose("motivation")}){Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(8.dp)){Text(stringResource(R.string.group_template_motivation_title),style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold);Text(stringResource(R.string.group_template_motivation_detail))}}
  ElevatedCard(onClick={choose("activities")}){Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(8.dp)){Text(stringResource(R.string.group_template_activities_title),style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold);Text(stringResource(R.string.group_template_activities_detail))}}
 }
}

@Composable fun GroupDetailScreen(group:GroupSummary,close:()->Unit,cheer:(String,String)->Unit,focus:(String,Int?,Boolean)->Unit,archive:()->Unit,invite:()->Unit,rename:(String)->Unit,commitment:(Int?,Boolean)->Unit,mute:(Boolean)->Unit,leave:()->Unit,remove:(String)->Unit,planActivity:()->Unit)=Dialog(onDismissRequest=close){
 var settings by rememberSaveable{mutableStateOf(false)};var focusOpen by rememberSaveable{mutableStateOf(false)}
 Surface(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.background){Column{
  Row(Modifier.padding(16.dp),verticalAlignment=Alignment.CenterVertically){IconButton(close){Icon(Icons.Outlined.ArrowBack,stringResource(R.string.social_done))};Text(group.name,Modifier.weight(1f),style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold);IconButton({settings=true}){Icon(Icons.Outlined.Settings,stringResource(R.string.group_manage))}}
  LazyColumn(Modifier.weight(1f),contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
   item{if(group.trustPolicy=="community") ElevatedCard{Column(Modifier.padding(18.dp),verticalArrangement=Arrangement.spacedBy(6.dp)){Text(stringResource(R.string.group_about),fontWeight=FontWeight.SemiBold);Text(group.description?:stringResource(R.string.group_community_detail));Text(if(group.joinPolicy=="request")stringResource(R.string.group_request_to_join) else stringResource(R.string.group_open_join),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.primary)}} else {val groupTarget=group.target;ElevatedCard{Column(Modifier.padding(18.dp)){Text(stringResource(R.string.group_relationship),fontWeight=FontWeight.SemiBold);Text(if(groupTarget!=null)stringResource(R.string.social_group_progress,group.completed,groupTarget) else stringResource(R.string.group_no_numeric_focus));groupTarget?.let{LinearProgressIndicator({(group.completed.toFloat()/it).coerceIn(0f,1f)},Modifier.fillMaxWidth().padding(top=12.dp))}}}}}
   if(group.trustPolicy=="community") items(group.notices,key=GroupNotice::id){notice->ElevatedCard{Column(Modifier.padding(14.dp),verticalArrangement=Arrangement.spacedBy(6.dp)){Text(notice.title?:stringResource(R.string.group_notice_update),fontWeight=FontWeight.SemiBold);Text(notice.body);if(notice.pinned)Text(stringResource(R.string.group_notice_pinned),style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.primary)}}}
   item{Row(verticalAlignment=Alignment.CenterVertically){Text(stringResource(R.string.social_members,group.memberCount.takeIf{it>0}?:group.members.size),Modifier.weight(1f),style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.SemiBold);TextButton(invite){Text(stringResource(R.string.social_invite))}}}
   items(group.members,key={it.person.id}){member->val memberTarget=member.target;ElevatedCard{Column(Modifier.padding(14.dp)){Row(verticalAlignment=Alignment.CenterVertically){SocialAvatar(member.person);Spacer(Modifier.width(12.dp));Column(Modifier.weight(1f)){Text(member.person.displayName,fontWeight=FontWeight.SemiBold);if(group.trustPolicy=="community")Text(member.role.replaceFirstChar{it.uppercase()},style=MaterialTheme.typography.bodySmall) else Text(when{member.skipped->stringResource(R.string.group_skipping);memberTarget!=null->stringResource(R.string.group_member_progress,member.completed,memberTarget);else->stringResource(R.string.group_contributed,member.completed)},style=MaterialTheme.typography.bodySmall)};if(group.trustPolicy!="community"&&!member.isCurrentUser)IconButton({cheer(member.person.id,"encouragement")}){Icon(Icons.Outlined.FavoriteBorder,stringResource(R.string.social_cheer))}};if(group.trustPolicy!="community")member.recentActivity?.let{activity->Text(activity.title?:activity.type,Modifier.padding(top=8.dp));Text(listOfNotNull(activity.durationSecs?.let{"${it/60} min"},activity.distanceM?.let{"%.2f km".format(it/1000)}).joinToString(" · "),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}}}}
   item{Button({if(group.trustPolicy=="community") planActivity() else focusOpen=true},Modifier.fillMaxWidth()){Text(if(group.trustPolicy=="community")stringResource(R.string.group_plan_activity) else stringResource(R.string.group_weekly_focus))}}
  }
 }}
 if(focusOpen)GroupFocusDialog(group,{focusOpen=false},focus,commitment)
 if(settings)GroupSettingsDialog(group,{settings=false},rename,mute,archive,leave,remove)
}

@Composable fun GroupActivityComposer(close:()->Unit, create:(String,String?)->Unit) {
 var title by rememberSaveable { mutableStateOf("") }; var location by rememberSaveable { mutableStateOf("") }
 AlertDialog(onDismissRequest=close,title={Text(stringResource(R.string.group_plan_activity))},text={Column(verticalArrangement=Arrangement.spacedBy(10.dp)){OutlinedTextField(title,{title=it.take(80)},label={Text(stringResource(R.string.group_activity_title))},singleLine=true);OutlinedTextField(location,{location=it.take(120)},label={Text(stringResource(R.string.group_activity_location))},singleLine=true);Text(stringResource(R.string.group_activity_timing),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}},confirmButton={TextButton({create(title.trim(),location.trim().takeIf{it.isNotEmpty()})}){Text(stringResource(R.string.social_done))}},dismissButton={TextButton(close){Text(stringResource(R.string.social_cancel))}})
}

@Composable private fun GroupFocusDialog(group:GroupSummary,close:()->Unit,focus:(String,Int?,Boolean)->Unit,commitment:(Int?,Boolean)->Unit){var mode by remember{mutableStateOf(group.focusMode)};var target by remember{mutableIntStateOf(group.target?:3)};var next by remember{mutableStateOf(false)};AlertDialog(onDismissRequest=close,title={Text(stringResource(R.string.group_weekly_focus))},text={Column{listOf("personal_targets" to R.string.group_focus_personal,"shared_target" to R.string.group_focus_shared,"none" to R.string.group_focus_none).forEach{(value,label)->Row(verticalAlignment=Alignment.CenterVertically){RadioButton(mode==value,{mode=value});Text(stringResource(label))}};if(mode!="none")Row(verticalAlignment=Alignment.CenterVertically){IconButton({target=(target-1).coerceAtLeast(1)}){Icon(Icons.Outlined.Remove,null)};Text(target.toString());IconButton({target=(target+1).coerceAtMost(14)}){Icon(Icons.Outlined.Add,null)}};Row(verticalAlignment=Alignment.CenterVertically){Checkbox(next,{next=it});Text(stringResource(R.string.group_apply_next_week))};if(mode=="personal_targets")TextButton({commitment(null,true);close()}){Text(stringResource(R.string.group_skip_week))}}},confirmButton={TextButton({if(mode=="personal_targets")commitment(target,false) else focus(mode,target.takeIf{mode=="shared_target"},next);close()}){Text(stringResource(R.string.social_done))}},dismissButton={TextButton(close){Text(stringResource(R.string.social_decline))}})}

@Composable private fun GroupSettingsDialog(group:GroupSummary,close:()->Unit,rename:(String)->Unit,mute:(Boolean)->Unit,archive:()->Unit,leave:()->Unit,remove:(String)->Unit){var name by remember{mutableStateOf(group.name)};AlertDialog(onDismissRequest=close,title={Text(stringResource(R.string.group_manage))},text={LazyColumn{item{OutlinedTextField(name,{name=it.take(80)},label={Text(stringResource(R.string.group_create_name))});TextButton({rename(name)}){Text(stringResource(R.string.group_rename))};Row(verticalAlignment=Alignment.CenterVertically){Text(stringResource(R.string.group_mute),Modifier.weight(1f));Switch(group.currentUserMuted,{mute(it)})}};if(group.role=="owner")items(group.members.filter{!it.isCurrentUser},key={it.person.id}){member->TextButton({remove(member.person.id)}){Text(stringResource(R.string.group_remove_member,member.person.displayName))}};item{TextButton(archive){Text(stringResource(if(group.lifecycle=="archived")R.string.social_group_reactivate else R.string.social_group_archive))};if(group.role!="owner")TextButton(leave){Text(stringResource(R.string.group_leave))}}}},confirmButton={TextButton(close){Text(stringResource(R.string.social_done))}})}
