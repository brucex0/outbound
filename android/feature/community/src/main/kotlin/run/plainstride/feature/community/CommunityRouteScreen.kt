package run.plainstride.feature.community
import run.plainstride.core.designsystem.*
import kotlinx.serialization.json.*

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import java.io.File

@Composable fun CommunityRouteScreen(library: RouteLibrary, scope: RouteScope, onScope: (RouteScope)->Unit, onRefresh:()->Unit, onSearch:(String)->Unit, onFollow:(run.plainstride.feature.recording.RecordingLaunchConfiguration)->Unit, onBookmark:(CommunityRoute)->Unit,publishableActivities:List<Pair<String,String>> = emptyList(),onPublish:(String,String,String?)->Unit={_,_,_->}) {
 val context=LocalContext.current
 var pendingNearby by remember { mutableStateOf(false) }
 val locationPermission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()){granted->pendingNearby=false;if(granted){onScope(RouteScope.NEARBY);onRefresh()}}
 var query by remember { mutableStateOf("") }
 var selected by remember { mutableStateOf<CommunityRoute?>(null) }
 var publish by remember { mutableStateOf<Pair<String,String>?>(null) }
 LazyColumn(Modifier.fillMaxSize(), contentPadding=PaddingValues(16.dp), verticalArrangement=Arrangement.spacedBy(12.dp)) {
  item { Row { Text(stringResource(R.string.routes_title), style=MaterialTheme.typography.headlineMedium, fontWeight=FontWeight.Bold, modifier=Modifier.weight(1f)); IconButton(onRefresh){Icon(Icons.Outlined.Refresh,stringResource(R.string.routes_refresh))} } }
  if(scope==RouteScope.MINE&&publishableActivities.isNotEmpty())item{publishableActivities.forEach{activity->TextButton({publish=activity}){Icon(Icons.Outlined.Publish,null);Spacer(Modifier.width(8.dp));Text(stringResource(R.string.routes_publish_activity,activity.second))}}}
  item { SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()){ RouteScope.entries.forEachIndexed { index,item->SegmentedButton(item==scope,{if(item==RouteScope.NEARBY&&context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)!=PackageManager.PERMISSION_GRANTED)pendingNearby=true else onScope(item)},SegmentedButtonDefaults.itemShape(index,RouteScope.entries.size)){Text(stringResource(when(item){RouteScope.DISCOVERY->R.string.routes_discover;RouteScope.MINE->R.string.routes_mine;RouteScope.NEARBY->R.string.routes_nearby}))} } } }
  if(scope==RouteScope.DISCOVERY) item { OutlinedTextField(query,{query=it;onSearch(it)},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.routes_search))},leadingIcon={Icon(Icons.Outlined.Search,null)}) }
  if(library.stale) item { Text(stringResource(R.string.routes_offline),style=MaterialTheme.typography.labelMedium) }
  items(library.routes,key=CommunityRoute::id){ route->ElevatedCard({selected=route},Modifier.fillMaxWidth()){Column{ route.coordinates().takeIf{it.size>1}?.let { PlainstrideRouteMap(it,Modifier.fillMaxWidth().height(150.dp)) }; Column(Modifier.padding(16.dp)){Row{Text(route.name,Modifier.weight(1f),fontWeight=FontWeight.SemiBold);IconButton({onBookmark(route)}){Icon(if(route.isBookmarked) Icons.Outlined.Bookmark else Icons.Outlined.BookmarkBorder,stringResource(R.string.routes_bookmark))}};Text(stringResource(R.string.routes_summary,route.distanceM/1000,route.elevationGainM?:0.0));Text(stringResource(R.string.routes_community_counts,route.bookmarkCount,route.completionCount),style=MaterialTheme.typography.bodySmall)}}} }
  if(library.routes.isEmpty()) item { Text(stringResource(R.string.routes_empty),Modifier.padding(24.dp)) }
 }
 selected?.let { route -> RouteDetailDialog(route,{selected=null}) { reverse -> selected=null;onFollow(CommunityRecordingCoordinator.launch(route,reverse)) } }
 publish?.let{activity->var name by remember(activity){mutableStateOf(activity.second)};var description by remember(activity){mutableStateOf("")};AlertDialog({publish=null},title={Text(stringResource(R.string.routes_publish))},text={Column{OutlinedTextField(name,{name=it.take(80)},label={Text(stringResource(R.string.routes_publish_name))});OutlinedTextField(description,{description=it.take(300)},label={Text(stringResource(R.string.routes_publish_description))})}},confirmButton={TextButton({onPublish(activity.first,name,description.takeIf(String::isNotBlank));publish=null},enabled=name.isNotBlank()){Text(stringResource(R.string.routes_publish))}},dismissButton={TextButton({publish=null}){Text(stringResource(R.string.routes_close))}})}
 if(pendingNearby)AlertDialog(onDismissRequest={pendingNearby=false},title={Text(stringResource(R.string.routes_location_title))},text={Text(stringResource(R.string.routes_location_body))},confirmButton={TextButton({locationPermission.launch(Manifest.permission.ACCESS_COARSE_LOCATION)}){Text(stringResource(R.string.routes_location_allow))}},dismissButton={TextButton({pendingNearby=false}){Text(stringResource(R.string.routes_close))}})
}

@Composable private fun RouteDetailDialog(route:CommunityRoute,close:()->Unit,follow:(Boolean)->Unit){val context=LocalContext.current;var reverse by remember{mutableStateOf(false)};AlertDialog(onDismissRequest=close,title={Text(route.name)},text={Column(verticalArrangement=Arrangement.spacedBy(12.dp)){route.description?.let{Text(it)};route.coordinates().takeIf{it.size>1}?.let{PlainstrideRouteMap(if(reverse)it.reversed() else it,Modifier.fillMaxWidth().height(220.dp))};Row{Text(stringResource(R.string.routes_reverse),Modifier.weight(1f));Switch(reverse,{reverse=it})};TextButton({shareRoute(context,route)}){Text(stringResource(R.string.routes_export))}}},confirmButton={Button({follow(reverse)}){Text(stringResource(R.string.routes_follow))}},dismissButton={TextButton(close){Text(stringResource(R.string.routes_close))}})}
private fun shareRoute(context:android.content.Context,route:CommunityRoute){val points=route.guidancePoints();if(points.size<2)return;val directory=File(context.cacheDir,"activity_exports").apply{mkdirs()};val file=File(directory,"route-${route.id.filter(Char::isLetterOrDigit).take(48)}.gpx");file.writeBytes(OfflineRouteExporter.gpx(route.name,points));val uri=FileProvider.getUriForFile(context,"${context.packageName}.activityphotos",file);context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("application/gpx+xml").putExtra(Intent.EXTRA_STREAM,uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),null))}

private fun CommunityRoute.coordinates(): List<MapCoordinate> {
  val coordinates = geometry?.get("coordinates") as? JsonArray ?: return emptyList()
  val line = if (coordinates.firstOrNull() is JsonPrimitive) listOf(coordinates) else coordinates.mapNotNull { it as? JsonArray }
  return line.mapNotNull { pair -> val lon=(pair.getOrNull(0) as? JsonPrimitive)?.doubleOrNull; val lat=(pair.getOrNull(1) as? JsonPrimitive)?.doubleOrNull; if(lat!=null&&lon!=null) MapCoordinate(lat,lon) else null }
}
fun CommunityRoute.guidancePoints()=coordinates().map{GuidancePoint(it.latitude,it.longitude)}
