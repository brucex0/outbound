package run.plainstride.feature.social

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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import android.content.Intent
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.serialization.json.*
import run.plainstride.core.designsystem.*

@Composable fun SocialRoute(accountId: String, localeTag: String, targetType:String?=null,targetId:String?=null,onNotifications:()->Unit={}, modifier: Modifier = Modifier, viewModel: SocialViewModel = hiltViewModel()) {
    LaunchedEffect(accountId, localeTag) { viewModel.start(accountId, localeTag) }
    val state by viewModel.state.collectAsStateWithLifecycle()
    LaunchedEffect(targetType,targetId,state.loading){if(!state.loading&&targetType!=null&&targetId!=null)viewModel.openTarget(targetType,targetId)}
    SocialScreen(state, viewModel::refresh, viewModel::search, viewModel::openProfile, viewModel::openCircle, viewModel::openComments, viewModel::openTarget, onNotifications, viewModel::toggleCheer, viewModel::joinGroup, viewModel::loadMore, viewModel::report, viewModel::block, modifier)
    state.selectedProfile?.let { ProfileDialog(it, viewModel::closeProfile) { viewModel.connect(it) } }
    state.selectedCircle?.let { circle -> CircleDialog(circle, viewModel::closeCircle, { recipient, preset -> viewModel.cheerCircle(circle, recipient, preset) }, { viewModel.setCircleFocus(circle,"weekly_sessions",circle.target ?: 3,false) }, { viewModel.setCircleArchived(circle,true) }) }
    state.selectedEvent?.let{event->ActionDialog(event.name,stringResource(if(event.joined)R.string.social_leave else R.string.social_join),{viewModel.setEventRsvp(event,!event.joined);viewModel.closeTarget()},viewModel::closeTarget)}
    state.selectedGroup?.let{group->ActionDialog(group.name,stringResource(if(group.joined)R.string.social_leave else R.string.social_join),{viewModel.joinGroup(group);viewModel.closeTarget()},viewModel::closeTarget)}
    state.selectedInvitation?.let{invitation->AlertDialog(onDismissRequest=viewModel::closeTarget,title={Text(invitation.title)},confirmButton={TextButton({viewModel.respondToInvitation(invitation,true)}){Text(stringResource(R.string.social_accept))}},dismissButton={TextButton({viewModel.respondToInvitation(invitation,false)}){Text(stringResource(R.string.social_decline))}})}
    state.selectedPost?.let { CommentsDialog(it, state.comments, viewModel::addComment, viewModel::deleteComment, viewModel::closeComments) }
}
@Composable private fun ActionDialog(title:String,action:String,onAction:()->Unit,onClose:()->Unit)=AlertDialog(onDismissRequest=onClose,title={Text(title)},confirmButton={TextButton(onAction){Text(action)}},dismissButton={TextButton(onClose){Text(stringResource(R.string.social_done))}})

@Composable private fun SocialScreen(state: SocialUiState, refresh: () -> Unit, search: (String) -> Unit, openProfile: (SocialPerson) -> Unit, openCircle: (CircleSummary) -> Unit, comments: (SocialPost) -> Unit, openTarget:(String,String)->Unit, notifications:()->Unit, cheer: (SocialPost) -> Unit, group: (SocialGroup) -> Unit, loadMore: () -> Unit, report: (SocialPost, String) -> Unit, block: (SocialPost) -> Unit, modifier: Modifier) {
    var safetyPost by remember { mutableStateOf<SocialPost?>(null) }
    LazyColumn(modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item { Row(verticalAlignment = Alignment.CenterVertically) { Text(stringResource(R.string.social_title), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f)); IconButton(refresh) { Icon(Icons.Outlined.Refresh, stringResource(R.string.social_refresh)) }; IconButton(notifications) { BadgedBox({ if (state.home.invitations.isNotEmpty()) Badge() }) { Icon(Icons.Outlined.Notifications, stringResource(R.string.social_notifications)) } } } }
        if (state.offline) item { AssistChip({}, { Text(stringResource(R.string.social_offline)) }, leadingIcon = { Icon(Icons.Outlined.CloudOff, null) }) }
        item { OutlinedTextField(state.search, search, modifier = Modifier.fillMaxWidth(), singleLine = true, label = { Text(stringResource(R.string.social_search_people)) }, leadingIcon = { Icon(Icons.Outlined.Search, null) }) }
        if (state.searchResults.isNotEmpty()) item { ElevatedCard { state.searchResults.forEach { PersonRow(it) { openProfile(it) } } } }
        item { SectionTitle(stringResource(R.string.social_connections)) }
        item { if (state.home.connections.isEmpty()) EmptyCard(stringResource(R.string.social_connections_empty)) else LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) { items(state.home.connections, key = SocialPerson::id) { PersonChip(it) { openProfile(it) } } } }
        item { SectionTitle(stringResource(R.string.social_circle)) }
        if (state.home.circles.isNotEmpty()) items(state.home.circles, key = CircleSummary::id) { circle -> OutlinedCard({ openCircle(circle) }, Modifier.fillMaxWidth()) { Row(Modifier.padding(16.dp)) { Text(circle.name, Modifier.weight(1f), fontWeight = FontWeight.SemiBold); circle.target?.let { Text("${circle.completed}/$it") } } } }
        else item { if (state.home.invitations.isNotEmpty()) InvitationCard(state.home.invitations.first()) { openTarget("invitation",it.id) } else EmptyCard(stringResource(R.string.social_circle_empty)) }
        item { SectionTitle(stringResource(R.string.social_upcoming)) }
        items(state.home.upcomingRuns, key = SocialEvent::id) { event -> EventCard(event) { openTarget("event",event.id) } }
        if (state.home.upcomingRuns.isEmpty()) item { EmptyCard(stringResource(R.string.social_upcoming_empty)) }
        item { SectionTitle(stringResource(R.string.social_groups)) }
        items(state.home.groups, key = SocialGroup::id) { GroupCard(it) { group(it) } }
        item { SectionTitle(stringResource(R.string.social_feed)) }
        items(state.home.posts, key = SocialPost::id) { post -> PostCard(post, { openProfile(post.author) }, { cheer(post) }, { comments(post) }, { safetyPost = post }) }
        if (state.loading) item { Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
        if (state.home.nextCursor != null) item { Button(loadMore, Modifier.fillMaxWidth(), enabled = !state.feedLoading) { Text(stringResource(R.string.social_load_more)) } }
    }
    safetyPost?.let { post -> var reason by remember { mutableStateOf(ReportReason.OTHER) }; AlertDialog(onDismissRequest = { safetyPost = null }, title = { Text(stringResource(R.string.social_safety_title)) }, text = { Column { Text(stringResource(R.string.social_safety_body)); ReportReason.entries.forEach { option -> Row(verticalAlignment=Alignment.CenterVertically){RadioButton(reason==option,{reason=option});Text(reportReasonLabel(option))} } } }, confirmButton = { TextButton({ report(post, reason.wireValue); safetyPost = null }) { Text(stringResource(R.string.social_report)) } }, dismissButton = { TextButton({ block(post); safetyPost = null }) { Text(stringResource(R.string.social_block)) } }) }
}

@Composable private fun SectionTitle(text: String) = Text(text, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
@Composable private fun EmptyCard(text: String) = OutlinedCard(Modifier.fillMaxWidth()) { Text(text, Modifier.padding(18.dp), style = MaterialTheme.typography.bodyMedium) }
@Composable private fun PersonChip(person: SocialPerson, click: () -> Unit) = AssistChip(click, { Text(person.displayName) }, leadingIcon = { Icon(if (person.isActive) Icons.Outlined.DirectionsRun else Icons.Outlined.Person, null) })
@Composable private fun PersonRow(person: SocialPerson, click: () -> Unit) = TextButton(click, Modifier.fillMaxWidth()) { Icon(Icons.Outlined.Person, null); Spacer(Modifier.width(12.dp)); Column(Modifier.weight(1f), horizontalAlignment = Alignment.Start) { Text(person.displayName); person.username?.let { Text("@$it", style = MaterialTheme.typography.bodySmall) } } }
@Composable private fun InvitationCard(invitation: SocialInvitation, review:(SocialInvitation)->Unit) = ElevatedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)) { Text(invitation.title, fontWeight = FontWeight.SemiBold); Text(stringResource(R.string.social_invited_by, invitation.sender.displayName), style = MaterialTheme.typography.bodySmall); Button({review(invitation)}, Modifier.padding(top = 8.dp)) { Text(stringResource(R.string.social_review)) } } }
@Composable private fun EventCard(event: SocialEvent, open:()->Unit) = OutlinedCard(open,Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)) { Text(event.name, fontWeight = FontWeight.SemiBold); Text(stringResource(R.string.social_hybrid)); event.locationName?.let { Text(it, style = MaterialTheme.typography.bodySmall) } } }
@Composable private fun GroupCard(group: SocialGroup, membership: () -> Unit) = OutlinedCard(Modifier.fillMaxWidth()) { Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(group.name, fontWeight = FontWeight.SemiBold); Text(stringResource(R.string.social_members, group.memberCount), style = MaterialTheme.typography.bodySmall) }; TextButton(membership) { Text(stringResource(if (group.joined) R.string.social_leave else R.string.social_join)) } } }
@Composable private fun PostCard(post: SocialPost, profile: () -> Unit, cheer: () -> Unit, comments:()->Unit, safety: () -> Unit) = ElevatedCard(Modifier.fillMaxWidth()) { val cheerLabel=stringResource(if(post.viewerHasCheered)R.string.social_remove_cheer else R.string.social_add_cheer);Column { Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) { TextButton(profile, Modifier.weight(1f)) { Icon(Icons.Outlined.AccountCircle, null); Spacer(Modifier.width(8.dp)); Text(post.author.displayName) }; IconButton(safety) { Icon(Icons.Outlined.MoreVert, stringResource(R.string.social_more)) } }; post.activity?.route.routeCoordinates().takeIf { it.size > 1 }?.let { PlainstrideRouteMap(it, Modifier.fillMaxWidth().height(150.dp)) } ?: Surface(Modifier.fillMaxWidth().height(150.dp), color = MaterialTheme.colorScheme.surfaceVariant) { Box(contentAlignment = Alignment.Center) { Icon(Icons.Outlined.Route, stringResource(R.string.social_route), Modifier.size(44.dp)) } }; Column(Modifier.padding(16.dp)) { post.activity?.let { Text(it.title, fontWeight = FontWeight.SemiBold) }; post.caption?.let { Text(it, Modifier.padding(top = 6.dp)) }; Row(verticalAlignment = Alignment.CenterVertically) { IconButton(cheer, Modifier.semantics { contentDescription = cheerLabel }) { Icon(if (post.viewerHasCheered) Icons.Outlined.Favorite else Icons.Outlined.FavoriteBorder, null) }; Text(post.cheerCount.toString()); Spacer(Modifier.width(18.dp)); IconButton(comments){Icon(Icons.Outlined.ChatBubbleOutline,stringResource(R.string.social_comments))};Text(post.commentCount.toString()) } } } }

@Composable private fun CommentsDialog(post:SocialPost,comments:List<SocialComment>,add:(String)->Unit,delete:(SocialComment)->Unit,close:()->Unit){var body by rememberSaveable{mutableStateOf("")};AlertDialog(onDismissRequest=close,title={Text(stringResource(R.string.social_comments_for,post.author.displayName))},text={Column{LazyColumn(Modifier.heightIn(max=320.dp)){items(comments,key=SocialComment::id){comment->Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){Column(Modifier.weight(1f)){Text(comment.author.displayName,fontWeight=FontWeight.SemiBold);Text(comment.body)};if(comment.canDelete)IconButton({delete(comment)}){Icon(Icons.Outlined.Delete,stringResource(R.string.social_delete_comment))}}}};OutlinedTextField(body,{body=it.take(500)},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.social_add_comment))})}},confirmButton={TextButton({if(body.isNotBlank()){add(body);body=""}}){Text(stringResource(R.string.social_post_comment))}},dismissButton={TextButton(close){Text(stringResource(R.string.social_done))}})}

private fun JsonElement?.routeCoordinates(): List<MapCoordinate> {
    val root = this as? JsonObject ?: return emptyList()
    val raw = (root["coordinates"] ?: (root["geometry"] as? JsonObject)?.get("coordinates")) as? JsonArray ?: return emptyList()
    val line = if (raw.firstOrNull() is JsonPrimitive) listOf(raw) else raw.mapNotNull { it as? JsonArray }
    return line.mapNotNull { pair -> val lon=(pair.getOrNull(0) as? JsonPrimitive)?.doubleOrNull; val lat=(pair.getOrNull(1) as? JsonPrimitive)?.doubleOrNull; if(lat!=null&&lon!=null) MapCoordinate(lat,lon) else null }
}
@Composable private fun ProfileDialog(person:SocialPerson,close:()->Unit,connect:()->Unit){
 val context=LocalContext.current;val shareLabel=stringResource(R.string.social_share_award_text,person.displayName)
 AlertDialog(onDismissRequest=close,icon={Icon(Icons.Outlined.AccountCircle,null)},title={Text(person.displayName)},text={Column{person.username?.let{Text("@$it")};Text(stringResource(R.string.social_relationship,relationshipLabel(person.relationship)),Modifier.padding(top=8.dp));if(person.recognitions.isNotEmpty()){Text(stringResource(R.string.social_milestones,person.recognitions.size),Modifier.padding(top=12.dp));person.recognitions.filter{it.shareable}.forEach{award->val badge=badgeLabel(award.badgeId);TextButton({context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT,"$shareLabel · $badge"),null))}){Icon(Icons.Outlined.Share,null);Spacer(Modifier.width(8.dp));Text(stringResource(R.string.social_share_award_named,badge))}}}}},confirmButton={Row{if(person.relationship=="none")TextButton(connect){Text(stringResource(R.string.social_connect))};TextButton(close){Text(stringResource(R.string.social_done))}}})
}
@Composable private fun reportReasonLabel(reason:ReportReason)=stringResource(when(reason){ReportReason.HARASSMENT->R.string.social_reason_harassment;ReportReason.HATE->R.string.social_reason_hate;ReportReason.SPAM->R.string.social_reason_spam;ReportReason.SEXUAL->R.string.social_reason_sexual;ReportReason.VIOLENCE->R.string.social_reason_violence;ReportReason.PRIVACY->R.string.social_reason_privacy;ReportReason.OTHER->R.string.social_reason_other})
@Composable private fun relationshipLabel(value:String)=when(value){"accepted","connected"->stringResource(R.string.social_relationship_connected);"pending"->stringResource(R.string.social_relationship_pending);else->stringResource(R.string.social_relationship_none)}
@Composable private fun badgeLabel(value:String)=stringResource(R.string.social_award_badge)
@Composable private fun CircleDialog(circle: CircleSummary, close: () -> Unit, cheer: (String, String) -> Unit,focus:()->Unit,archive:()->Unit) = AlertDialog(onDismissRequest = close, title = { Text(circle.name) }, text = { LazyColumn { item { Text(stringResource(R.string.social_circle_progress, circle.completed, circle.target ?: 0)) }; items(circle.members, key = { it.person.id }) { member -> Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Text(member.person.displayName, Modifier.weight(1f)); IconButton({ cheer(member.person.id, "encouragement") }) { Icon(Icons.Outlined.FavoriteBorder, stringResource(R.string.social_cheer)) } } };item{Row{TextButton(focus){Text(stringResource(R.string.social_circle_set_focus))};TextButton(archive){Text(stringResource(R.string.social_circle_archive))}}} } }, confirmButton = { TextButton(close) { Text(stringResource(R.string.social_done)) } })
