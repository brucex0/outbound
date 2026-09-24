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

@Composable fun CircleCreateScreen(connections:List<SocialPerson>,close:()->Unit,create:(String?,List<SocialPerson>)->Unit)=Dialog(onDismissRequest=close){
 var name by rememberSaveable{mutableStateOf("")};var selected by remember{mutableStateOf(setOf<String>())}
 Surface(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.background){Column{
  Row(Modifier.padding(16.dp),verticalAlignment=Alignment.CenterVertically){IconButton(close){Icon(Icons.Outlined.Close,stringResource(R.string.social_done))};Text(stringResource(R.string.circle_create_title),Modifier.weight(1f),style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold)}
  LazyColumn(Modifier.weight(1f),contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(12.dp)){
   item{ElevatedCard{Column(Modifier.padding(20.dp),verticalArrangement=Arrangement.spacedBy(8.dp)){Row(horizontalArrangement=Arrangement.spacedBy(12.dp)){Icon(Icons.Outlined.DirectionsWalk,null);Icon(Icons.Outlined.DirectionsRun,null);Icon(Icons.Outlined.DirectionsBike,null)};Text(stringResource(R.string.circle_create_inspiration),style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold);Text(stringResource(R.string.circle_create_detail))}}}
   item{Text(stringResource(R.string.circle_create_people),style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.SemiBold);Text(stringResource(R.string.circle_create_selected,selected.size),style=MaterialTheme.typography.bodySmall)}
   items(connections,key=SocialPerson::id){person->val checked=person.id in selected;Card(onClick={selected=if(checked)selected-person.id else selected+person.id}){Row(Modifier.fillMaxWidth().padding(12.dp),verticalAlignment=Alignment.CenterVertically){SocialAvatar(person);Spacer(Modifier.width(12.dp));Text(person.displayName,Modifier.weight(1f));Checkbox(checked,{selected=if(checked)selected-person.id else selected+person.id})}}}
   item{OutlinedTextField(name,{name=it.take(80)},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.circle_create_name))},supportingText={Text(stringResource(R.string.circle_create_name_help))})}
  }
  Button({create(name.trim().ifEmpty{null},connections.filter{it.id in selected})},Modifier.fillMaxWidth().padding(16.dp).heightIn(min=50.dp),enabled=selected.isNotEmpty()){Text(stringResource(R.string.circle_create_action))}
 }}
}

@Composable fun CircleDetailScreen(circle:CircleSummary,close:()->Unit,cheer:(String,String)->Unit,focus:(String,Int?,Boolean)->Unit,archive:()->Unit,invite:()->Unit,rename:(String)->Unit,commitment:(Int?,Boolean)->Unit,mute:(Boolean)->Unit,leave:()->Unit,remove:(String)->Unit)=Dialog(onDismissRequest=close){
 var settings by rememberSaveable{mutableStateOf(false)};var focusOpen by rememberSaveable{mutableStateOf(false)}
 Surface(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.background){Column{
  Row(Modifier.padding(16.dp),verticalAlignment=Alignment.CenterVertically){IconButton(close){Icon(Icons.Outlined.ArrowBack,stringResource(R.string.social_done))};Text(circle.name,Modifier.weight(1f),style=MaterialTheme.typography.titleLarge,fontWeight=FontWeight.Bold);IconButton({settings=true}){Icon(Icons.Outlined.Settings,stringResource(R.string.circle_manage))}}
  LazyColumn(Modifier.weight(1f),contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(14.dp)){
   item{val circleTarget=circle.target;ElevatedCard{Column(Modifier.padding(18.dp)){Text(stringResource(R.string.circle_relationship),fontWeight=FontWeight.SemiBold);Text(if(circleTarget!=null)stringResource(R.string.social_circle_progress,circle.completed,circleTarget) else stringResource(R.string.circle_no_numeric_focus));circleTarget?.let{LinearProgressIndicator({(circle.completed.toFloat()/it).coerceIn(0f,1f)},Modifier.fillMaxWidth().padding(top=12.dp))}}}}
   item{Row(verticalAlignment=Alignment.CenterVertically){Text(stringResource(R.string.social_members,circle.memberCount.takeIf{it>0}?:circle.members.size),Modifier.weight(1f),style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.SemiBold);TextButton(invite){Text(stringResource(R.string.social_invite))}}}
   items(circle.members,key={it.person.id}){member->val memberTarget=member.target;ElevatedCard{Column(Modifier.padding(14.dp)){Row(verticalAlignment=Alignment.CenterVertically){SocialAvatar(member.person);Spacer(Modifier.width(12.dp));Column(Modifier.weight(1f)){Text(member.person.displayName,fontWeight=FontWeight.SemiBold);Text(when{member.skipped->stringResource(R.string.circle_skipping);memberTarget!=null->stringResource(R.string.circle_member_progress,member.completed,memberTarget);else->stringResource(R.string.circle_contributed,member.completed)},style=MaterialTheme.typography.bodySmall)};if(!member.isCurrentUser)IconButton({cheer(member.person.id,"encouragement")}){Icon(Icons.Outlined.FavoriteBorder,stringResource(R.string.social_cheer))}};member.recentActivity?.let{activity->Text(activity.title?:activity.type,Modifier.padding(top=8.dp));Text(listOfNotNull(activity.durationSecs?.let{"${it/60} min"},activity.distanceM?.let{"%.2f km".format(it/1000)}).joinToString(" · "),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}}}}
   item{Button({focusOpen=true},Modifier.fillMaxWidth()){Text(stringResource(R.string.circle_weekly_focus))}}
  }
 }}
 if(focusOpen)CircleFocusDialog(circle,{focusOpen=false},focus,commitment)
 if(settings)CircleSettingsDialog(circle,{settings=false},rename,mute,archive,leave,remove)
}

@Composable private fun CircleFocusDialog(circle:CircleSummary,close:()->Unit,focus:(String,Int?,Boolean)->Unit,commitment:(Int?,Boolean)->Unit){var mode by remember{mutableStateOf(circle.focusMode)};var target by remember{mutableIntStateOf(circle.target?:3)};var next by remember{mutableStateOf(false)};AlertDialog(onDismissRequest=close,title={Text(stringResource(R.string.circle_weekly_focus))},text={Column{listOf("personal_targets" to R.string.circle_focus_personal,"shared_target" to R.string.circle_focus_shared,"none" to R.string.circle_focus_none).forEach{(value,label)->Row(verticalAlignment=Alignment.CenterVertically){RadioButton(mode==value,{mode=value});Text(stringResource(label))}};if(mode!="none")Row(verticalAlignment=Alignment.CenterVertically){IconButton({target=(target-1).coerceAtLeast(1)}){Icon(Icons.Outlined.Remove,null)};Text(target.toString());IconButton({target=(target+1).coerceAtMost(14)}){Icon(Icons.Outlined.Add,null)}};Row(verticalAlignment=Alignment.CenterVertically){Checkbox(next,{next=it});Text(stringResource(R.string.circle_apply_next_week))};if(mode=="personal_targets")TextButton({commitment(null,true);close()}){Text(stringResource(R.string.circle_skip_week))}}},confirmButton={TextButton({if(mode=="personal_targets")commitment(target,false) else focus(mode,target.takeIf{mode=="shared_target"},next);close()}){Text(stringResource(R.string.social_done))}},dismissButton={TextButton(close){Text(stringResource(R.string.social_decline))}})}

@Composable private fun CircleSettingsDialog(circle:CircleSummary,close:()->Unit,rename:(String)->Unit,mute:(Boolean)->Unit,archive:()->Unit,leave:()->Unit,remove:(String)->Unit){var name by remember{mutableStateOf(circle.name)};AlertDialog(onDismissRequest=close,title={Text(stringResource(R.string.circle_manage))},text={LazyColumn{item{OutlinedTextField(name,{name=it.take(80)},label={Text(stringResource(R.string.circle_create_name))});TextButton({rename(name)}){Text(stringResource(R.string.circle_rename))};Row(verticalAlignment=Alignment.CenterVertically){Text(stringResource(R.string.circle_mute),Modifier.weight(1f));Switch(circle.currentUserMuted,{mute(it)})}};if(circle.role=="owner")items(circle.members.filter{!it.isCurrentUser},key={it.person.id}){member->TextButton({remove(member.person.id)}){Text(stringResource(R.string.circle_remove_member,member.person.displayName))}};item{TextButton(archive){Text(stringResource(if(circle.lifecycle=="archived")R.string.social_circle_reactivate else R.string.social_circle_archive))};if(circle.role!="owner")TextButton(leave){Text(stringResource(R.string.circle_leave))}}}},confirmButton={TextButton(close){Text(stringResource(R.string.social_done))}})}
