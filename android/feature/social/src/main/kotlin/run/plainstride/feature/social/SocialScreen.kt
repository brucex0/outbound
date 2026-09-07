package run.plainstride.feature.social

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable fun SocialRoute(accountId: String, localeTag: String, modifier: Modifier = Modifier, viewModel: SocialViewModel = hiltViewModel()) {
    LaunchedEffect(accountId, localeTag) { viewModel.start(accountId, localeTag) }
    val state by viewModel.state.collectAsStateWithLifecycle()
    SocialScreen(state, viewModel::refresh, viewModel::search, viewModel::openProfile, viewModel::openCircle, viewModel::toggleCheer, viewModel::joinGroup, viewModel::loadMore, viewModel::report, viewModel::block, modifier)
    state.selectedProfile?.let { ProfileDialog(it, viewModel::closeProfile) }
    state.selectedCircle?.let { CircleDialog(it, viewModel::closeCircle) { recipient, preset -> viewModel.cheerCircle(it, recipient, preset) } }
}

@Composable private fun SocialScreen(state: SocialUiState, refresh: () -> Unit, search: (String) -> Unit, openProfile: (SocialPerson) -> Unit, openCircle: (CircleSummary) -> Unit, cheer: (SocialPost) -> Unit, group: (SocialGroup) -> Unit, loadMore: () -> Unit, report: (SocialPost, String) -> Unit, block: (SocialPost) -> Unit, modifier: Modifier) {
    var safetyPost by remember { mutableStateOf<SocialPost?>(null) }
    LazyColumn(modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item { Row(verticalAlignment = Alignment.CenterVertically) { Text(stringResource(R.string.social_title), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f)); IconButton(refresh) { Icon(Icons.Outlined.Refresh, stringResource(R.string.social_refresh)) }; IconButton({}) { BadgedBox({ if (state.home.invitations.isNotEmpty()) Badge() }) { Icon(Icons.Outlined.Notifications, stringResource(R.string.social_notifications)) } } } }
        if (state.offline) item { AssistChip({}, { Text(stringResource(R.string.social_offline)) }, leadingIcon = { Icon(Icons.Outlined.CloudOff, null) }) }
        item { OutlinedTextField(state.search, search, modifier = Modifier.fillMaxWidth(), singleLine = true, label = { Text(stringResource(R.string.social_search_people)) }, leadingIcon = { Icon(Icons.Outlined.Search, null) }) }
        if (state.searchResults.isNotEmpty()) item { ElevatedCard { state.searchResults.forEach { PersonRow(it) { openProfile(it) } } } }
        item { SectionTitle(stringResource(R.string.social_connections)) }
        item { if (state.home.connections.isEmpty()) EmptyCard(stringResource(R.string.social_connections_empty)) else LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) { items(state.home.connections, key = SocialPerson::id) { PersonChip(it) { openProfile(it) } } } }
        item { SectionTitle(stringResource(R.string.social_circle)) }
        if (state.home.circles.isNotEmpty()) items(state.home.circles, key = CircleSummary::id) { circle -> OutlinedCard({ openCircle(circle) }, Modifier.fillMaxWidth()) { Row(Modifier.padding(16.dp)) { Text(circle.name, Modifier.weight(1f), fontWeight = FontWeight.SemiBold); circle.target?.let { Text("${circle.completed}/$it") } } } }
        else item { if (state.home.invitations.isNotEmpty()) InvitationCard(state.home.invitations.first()) else EmptyCard(stringResource(R.string.social_circle_empty)) }
        item { SectionTitle(stringResource(R.string.social_upcoming)) }
        items(state.home.upcomingRuns, key = SocialEvent::id) { EventCard(it) }
        if (state.home.upcomingRuns.isEmpty()) item { EmptyCard(stringResource(R.string.social_upcoming_empty)) }
        item { SectionTitle(stringResource(R.string.social_groups)) }
        items(state.home.groups, key = SocialGroup::id) { GroupCard(it) { group(it) } }
        item { SectionTitle(stringResource(R.string.social_feed)) }
        items(state.home.posts, key = SocialPost::id) { post -> PostCard(post, { openProfile(post.author) }, { cheer(post) }, { safetyPost = post }) }
        if (state.loading) item { Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
        if (state.home.nextCursor != null) item { Button(loadMore, Modifier.fillMaxWidth(), enabled = !state.feedLoading) { Text(stringResource(R.string.social_load_more)) } }
    }
    safetyPost?.let { post -> AlertDialog(onDismissRequest = { safetyPost = null }, title = { Text(stringResource(R.string.social_safety_title)) }, text = { Text(stringResource(R.string.social_safety_body)) }, confirmButton = { TextButton({ report(post, "inappropriate"); safetyPost = null }) { Text(stringResource(R.string.social_report)) } }, dismissButton = { TextButton({ block(post); safetyPost = null }) { Text(stringResource(R.string.social_block)) } }) }
}

@Composable private fun SectionTitle(text: String) = Text(text, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
@Composable private fun EmptyCard(text: String) = OutlinedCard(Modifier.fillMaxWidth()) { Text(text, Modifier.padding(18.dp), style = MaterialTheme.typography.bodyMedium) }
@Composable private fun PersonChip(person: SocialPerson, click: () -> Unit) = AssistChip(click, { Text(person.displayName) }, leadingIcon = { Icon(if (person.isActive) Icons.Outlined.DirectionsRun else Icons.Outlined.Person, null) })
@Composable private fun PersonRow(person: SocialPerson, click: () -> Unit) = TextButton(click, Modifier.fillMaxWidth()) { Icon(Icons.Outlined.Person, null); Spacer(Modifier.width(12.dp)); Column(Modifier.weight(1f), horizontalAlignment = Alignment.Start) { Text(person.displayName); person.username?.let { Text("@$it", style = MaterialTheme.typography.bodySmall) } } }
@Composable private fun InvitationCard(invitation: SocialInvitation) = ElevatedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)) { Text(invitation.title, fontWeight = FontWeight.SemiBold); Text(stringResource(R.string.social_invited_by, invitation.sender.displayName), style = MaterialTheme.typography.bodySmall); Button({}, Modifier.padding(top = 8.dp)) { Text(stringResource(R.string.social_review)) } } }
@Composable private fun EventCard(event: SocialEvent) = OutlinedCard(Modifier.fillMaxWidth()) { Column(Modifier.padding(16.dp)) { Text(event.name, fontWeight = FontWeight.SemiBold); Text(stringResource(R.string.social_hybrid)); event.locationName?.let { Text(it, style = MaterialTheme.typography.bodySmall) } } }
@Composable private fun GroupCard(group: SocialGroup, membership: () -> Unit) = OutlinedCard(Modifier.fillMaxWidth()) { Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) { Column(Modifier.weight(1f)) { Text(group.name, fontWeight = FontWeight.SemiBold); Text(stringResource(R.string.social_members, group.memberCount), style = MaterialTheme.typography.bodySmall) }; TextButton(membership) { Text(stringResource(if (group.joined) R.string.social_leave else R.string.social_join)) } } }
@Composable private fun PostCard(post: SocialPost, profile: () -> Unit, cheer: () -> Unit, safety: () -> Unit) = ElevatedCard(Modifier.fillMaxWidth()) { Column { Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) { TextButton(profile, Modifier.weight(1f)) { Icon(Icons.Outlined.AccountCircle, null); Spacer(Modifier.width(8.dp)); Text(post.author.displayName) }; IconButton(safety) { Icon(Icons.Outlined.MoreVert, stringResource(R.string.social_more)) } }; Surface(Modifier.fillMaxWidth().height(150.dp), color = MaterialTheme.colorScheme.surfaceVariant) { Box(contentAlignment = Alignment.Center) { Icon(Icons.Outlined.Route, stringResource(R.string.social_route), Modifier.size(44.dp)) } }; Column(Modifier.padding(16.dp)) { post.activity?.let { Text(it.title, fontWeight = FontWeight.SemiBold) }; post.caption?.let { Text(it, Modifier.padding(top = 6.dp)) }; Row(verticalAlignment = Alignment.CenterVertically) { IconButton(cheer, Modifier.semantics { contentDescription = "cheer" }) { Icon(if (post.viewerHasCheered) Icons.Outlined.Favorite else Icons.Outlined.FavoriteBorder, null) }; Text(post.cheerCount.toString()); Spacer(Modifier.width(18.dp)); Icon(Icons.Outlined.ChatBubbleOutline, null); Spacer(Modifier.width(6.dp)); Text(post.commentCount.toString()) } } } }
@Composable private fun ProfileDialog(person: SocialPerson, close: () -> Unit) = AlertDialog(onDismissRequest = close, icon = { Icon(Icons.Outlined.AccountCircle, null) }, title = { Text(person.displayName) }, text = { Column { person.username?.let { Text("@$it") }; if (person.recognitions.isNotEmpty()) Text(stringResource(R.string.social_milestones, person.recognitions.size), Modifier.padding(top = 12.dp)) } }, confirmButton = { TextButton(close) { Text(stringResource(R.string.social_done)) } })
@Composable private fun CircleDialog(circle: CircleSummary, close: () -> Unit, cheer: (String, String) -> Unit) = AlertDialog(onDismissRequest = close, title = { Text(circle.name) }, text = { LazyColumn { item { Text(stringResource(R.string.social_circle_progress, circle.completed, circle.target ?: 0)) }; items(circle.members, key = { it.person.id }) { member -> Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) { Text(member.person.displayName, Modifier.weight(1f)); IconButton({ cheer(member.person.id, "encouragement") }) { Icon(Icons.Outlined.FavoriteBorder, stringResource(R.string.social_cheer)) } } } } }, confirmButton = { TextButton(close) { Text(stringResource(R.string.social_done)) } })
