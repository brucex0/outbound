package com.plainstride.outbound.feature.community
import com.plainstride.outbound.core.designsystem.*
import com.plainstride.outbound.feature.recording.HarvestRunSimulation
import kotlinx.serialization.json.*

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalContext
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import java.io.File
import java.util.UUID
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.put

@Composable fun CommunityRouteScreen(library: RouteLibrary, scope: RouteScope, onScope: (RouteScope)->Unit, onRefresh:()->Unit, onSearch:(String)->Unit, onFollow:(com.plainstride.outbound.feature.recording.RecordingLaunchConfiguration)->Unit, onBookmark:(CommunityRoute)->Unit,publishableActivities:List<Pair<String,String>> = emptyList(),onPublish:(String,String,String?)->Unit={_,_,_->},onImport:(Boolean)->Unit={},embedded:Boolean=false,bottomContentPadding:androidx.compose.ui.unit.Dp=0.dp,routeDetail:CommunityRoute?=null,routeDetailLoading:Boolean=false,onLoadDetail:(String)->Unit={},onRemovePublished:(String)->Unit={},onClearDetail:()->Unit={},unitSystem:com.plainstride.outbound.core.model.activity.MeasurementUnitSystem=com.plainstride.outbound.core.model.activity.MeasurementUnitSystem.metric,onImportedDelete:()->Unit={},importRequest:Int=0) {
 val debugRoute = if (BuildConfig.DEBUG && scope != RouteScope.MINE) {
  debugHarvestRoute(
   stringResource(com.plainstride.outbound.feature.recording.R.string.recording_simulation_route_name),
  )
 } else null
 val visibleRoutes = if (debugRoute == null) library.routes else
  listOf(debugRoute) + library.routes.filterNot { it.id == HarvestRunSimulation.ROUTE_ID }
 val visibleLibrary = library.copy(routes = visibleRoutes)
 if(embedded){EmbeddedCommunityRouteLibrary(visibleLibrary,scope,onScope,onRefresh,onSearch,onFollow,onBookmark,onImport,routeDetail,routeDetailLoading,onLoadDetail,onRemovePublished,onClearDetail,unitSystem,onImportedDelete,bottomContentPadding,importRequest);return}
 val context=LocalContext.current
 var pendingNearby by remember { mutableStateOf(false) }
 val locationPermission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()){granted->pendingNearby=false;if(granted){onScope(RouteScope.NEARBY);onRefresh()}}
 var query by remember { mutableStateOf("") }
 var selected by remember { mutableStateOf<CommunityRoute?>(null) }
 var imported by remember { mutableStateOf<List<CommunityRoute>>(emptyList()) }
 var publish by remember { mutableStateOf<Pair<String,String>?>(null) }
 val importFile=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()){uri->
  uri ?: return@rememberLauncherForActivityResult
  val route=runCatching{context.contentResolver.openInputStream(uri)?.bufferedReader()?.use{reader->importRoute(reader.readText(),uri.lastPathSegment)}}.getOrNull()
  if(route!=null){imported=listOf(route)+imported.filterNot{it.id==route.id};selected=route;onImport(true)}else onImport(false)
 }
  LazyColumn(Modifier.fillMaxSize(), contentPadding=PaddingValues(16.dp), verticalArrangement=Arrangement.spacedBy(12.dp)) {
  item { Row { Text(stringResource(R.string.routes_title), style=MaterialTheme.typography.headlineMedium, fontWeight=FontWeight.Bold, modifier=Modifier.weight(1f)); IconButton({importFile.launch(arrayOf("application/gpx+xml","application/geo+json","application/json","text/xml","text/plain"))}){Icon(Icons.Outlined.FileOpen,stringResource(R.string.route_library_action_import))}; IconButton(onRefresh){Icon(Icons.Outlined.Refresh,stringResource(R.string.routes_refresh))} } }
  if(scope==RouteScope.MINE&&publishableActivities.isNotEmpty())item{publishableActivities.forEach{activity->TextButton({publish=activity}){Icon(Icons.Outlined.Publish,null);Spacer(Modifier.width(8.dp));Text(stringResource(R.string.routes_publish_activity,activity.second))}}}
  item { SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()){ RouteScope.entries.forEachIndexed { index,item->SegmentedButton(item==scope,{if(item==RouteScope.NEARBY&&context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)!=PackageManager.PERMISSION_GRANTED)pendingNearby=true else onScope(item)},SegmentedButtonDefaults.itemShape(index,RouteScope.entries.size)){Text(stringResource(when(item){RouteScope.DISCOVERY->R.string.routes_discover;RouteScope.MINE->R.string.routes_mine;RouteScope.NEARBY->R.string.routes_nearby}))} } } }
  if(scope==RouteScope.DISCOVERY) item { OutlinedTextField(query,{query=it;onSearch(it)},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.routes_search))},leadingIcon={Icon(Icons.Outlined.Search,null)}) }
  if(library.stale) item { Text(stringResource(R.string.routes_offline),style=MaterialTheme.typography.labelMedium) }
  items(imported + visibleRoutes,key=CommunityRoute::id){ route->ElevatedCard({selected=route},Modifier.fillMaxWidth()){Column{ route.coordinates().takeIf{it.size>1}?.let { PlainstrideRouteMap(it,Modifier.fillMaxWidth().height(150.dp)) }; Column(Modifier.padding(16.dp)){Row{Text(route.name,Modifier.weight(1f),fontWeight=FontWeight.SemiBold);if(!route.id.startsWith("import:")&&!isDebugHarvestRoute(route))IconButton({onBookmark(route)}){Icon(if(route.isBookmarked) Icons.Outlined.Bookmark else Icons.Outlined.BookmarkBorder,stringResource(R.string.routes_bookmark))}};if(isDebugHarvestRoute(route))DebugTestRouteBadge();Text(stringResource(R.string.routes_summary,route.distanceM/1000,route.elevationGainM?:0.0));if(!route.id.startsWith("import:")&&!isDebugHarvestRoute(route))Text(stringResource(R.string.routes_community_counts,route.bookmarkCount,route.completionCount),style=MaterialTheme.typography.bodySmall)}}} }
  if(visibleRoutes.isEmpty()&&imported.isEmpty()) item { Text(stringResource(R.string.routes_empty),Modifier.padding(24.dp)) }
 }
 selected?.let { route -> RouteDetailDialog(route,{selected=null}) { reverse -> selected=null;onFollow(CommunityRecordingCoordinator.launch(route,reverse)) } }
 publish?.let{activity->var name by remember(activity){mutableStateOf(activity.second)};var description by remember(activity){mutableStateOf("")};AlertDialog({publish=null},title={Text(stringResource(R.string.routes_publish))},text={Column{OutlinedTextField(name,{name=it.take(80)},label={Text(stringResource(R.string.routes_publish_name))});OutlinedTextField(description,{description=it.take(300)},label={Text(stringResource(R.string.routes_publish_description))})}},confirmButton={TextButton({onPublish(activity.first,name,description.takeIf(String::isNotBlank));publish=null},enabled=name.isNotBlank()){Text(stringResource(R.string.routes_publish))}},dismissButton={TextButton({publish=null}){Text(stringResource(R.string.routes_close))}})}
 if(pendingNearby)AlertDialog(onDismissRequest={pendingNearby=false},title={Text(stringResource(R.string.routes_location_title))},text={Text(stringResource(R.string.routes_location_body))},confirmButton={TextButton({locationPermission.launch(Manifest.permission.ACCESS_COARSE_LOCATION)}){Text(stringResource(R.string.routes_location_allow))}},dismissButton={TextButton({pendingNearby=false}){Text(stringResource(R.string.routes_close))}})
}

@Composable
private fun EmbeddedCommunityRouteLibrary(
 library:RouteLibrary,
 scope:RouteScope,
 onScope:(RouteScope)->Unit,
 onRefresh:()->Unit,
 onSearch:(String)->Unit,
 onFollow:(com.plainstride.outbound.feature.recording.RecordingLaunchConfiguration)->Unit,
 onBookmark:(CommunityRoute)->Unit,
 onImport:(Boolean)->Unit,
 routeDetail:CommunityRoute?,
 routeDetailLoading:Boolean,
 onLoadDetail:(String)->Unit,
 onRemovePublished:(String)->Unit,
 onClearDetail:()->Unit,
 unitSystem:com.plainstride.outbound.core.model.activity.MeasurementUnitSystem,
 onImportedDelete:()->Unit,
 bottomContentPadding:androidx.compose.ui.unit.Dp,
 importRequest:Int,
) {
 val context=LocalContext.current
 var query by remember { mutableStateOf("") }
 var selectedRoute by remember { mutableStateOf<CommunityRoute?>(null) }
 var selectedImportedRoute by remember { mutableStateOf<CommunityRoute?>(null) }
 var confirmDeleteImported by remember { mutableStateOf<CommunityRoute?>(null) }
 var importedRoutes by remember { mutableStateOf<List<CommunityRoute>>(emptyList()) }
 var pendingNearby by remember { mutableStateOf(false) }
 var handledImportRequest by rememberSaveable { mutableStateOf(0) }
 val locationPermission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()){granted->pendingNearby=false;if(granted){onScope(RouteScope.NEARBY);onRefresh()}}
 val importFile=rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()){uri->
  uri ?: return@rememberLauncherForActivityResult
  val route=runCatching{context.contentResolver.openInputStream(uri)?.bufferedReader()?.use{reader->importRoute(reader.readText(),uri.lastPathSegment)}}.getOrNull()
  if(route!=null){importedRoutes=listOf(route)+importedRoutes.filterNot{it.id==route.id};selectedRoute=route;onImport(true)}else onImport(false)
 }
 LaunchedEffect(importRequest) { if (importRequest > handledImportRequest) { handledImportRequest = importRequest; importFile.launch(arrayOf("application/gpx+xml","application/geo+json","application/json","text/xml","text/plain")) } }
 LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(bottom=16.dp+bottomContentPadding),verticalArrangement=Arrangement.spacedBy(0.dp)) {
  item {
   Row(Modifier.fillMaxWidth().heightIn(min=52.dp).padding(horizontal=16.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
    Icon(Icons.Outlined.Search,null,tint=MaterialTheme.colorScheme.onSurfaceVariant)
    OutlinedTextField(query,{query=it},Modifier.weight(1f),singleLine=true,placeholder={Text(stringResource(R.string.route_library_search_prompt))},keyboardOptions=androidx.compose.foundation.text.KeyboardOptions(imeAction=androidx.compose.ui.text.input.ImeAction.Search),keyboardActions=androidx.compose.foundation.text.KeyboardActions(onSearch={onSearch(query)}))
    IconButton(onClick={onSearch(query)},modifier=Modifier.sizeIn(minWidth=44.dp,minHeight=44.dp)){Icon(Icons.Outlined.ArrowForward,stringResource(R.string.route_library_search_prompt))}
   }
  }
  item {
   Column(Modifier.fillMaxWidth().padding(horizontal=16.dp,vertical=6.dp)) {
    RouteLibraryAction(stringResource(R.string.route_library_action_find_nearby),Icons.Outlined.MyLocation){if(context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)!=PackageManager.PERMISSION_GRANTED)pendingNearby=true else{onScope(RouteScope.NEARBY);onRefresh()}}
    RouteLibraryAction(stringResource(R.string.route_library_action_import),Icons.Outlined.FileOpen){importFile.launch(arrayOf("application/gpx+xml","application/geo+json","application/json","text/xml","text/plain"))}
   }
  }
  if(importedRoutes.isNotEmpty()) {
   item { RouteLibrarySectionLabel(stringResource(R.string.route_library_section_imported)) }
   items(importedRoutes,key=CommunityRoute::id){route->
    Row(Modifier.fillMaxWidth().heightIn(min=64.dp).clickable{selectedImportedRoute=route}.padding(horizontal=16.dp,vertical=8.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
     RouteLibraryGlyph(Icons.Outlined.FileOpen)
     Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(3.dp)) {Text(route.name,style=MaterialTheme.typography.titleSmall,fontWeight=FontWeight.SemiBold,maxLines=1,overflow=TextOverflow.Ellipsis);Text(stringResource(R.string.route_library_imported_device_private),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
     IconButton({confirmDeleteImported=route},modifier=Modifier.sizeIn(minWidth=44.dp,minHeight=44.dp)){Icon(Icons.Outlined.Delete,stringResource(R.string.route_library_action_delete))}
    }
    HorizontalDivider(Modifier.padding(start=62.dp))
   }
  }
  item { RouteLibrarySectionLabel(stringResource(R.string.route_library_section_community)) }
  if(library.routes.isEmpty()&&routeDetailLoading) item { Box(Modifier.fillMaxWidth().padding(vertical=28.dp),contentAlignment=Alignment.Center){CircularProgressIndicator(Modifier.size(28.dp));Text(stringResource(R.string.route_library_loading),Modifier.padding(top=44.dp),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)} }
  else if(library.routes.isEmpty()) item {
   Column(Modifier.fillMaxWidth().padding(horizontal=32.dp,vertical=28.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(8.dp)) {
    Icon(Icons.Outlined.Map,null,Modifier.size(30.dp),tint=MaterialTheme.colorScheme.onSurfaceVariant)
    Text(stringResource(R.string.route_library_empty_community_title),style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.SemiBold)
    Text(stringResource(R.string.route_library_empty_community_description),style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
   }
  } else items(library.routes,key=CommunityRoute::id){route->
   Row(Modifier.fillMaxWidth().heightIn(min=68.dp).clickable{selectedRoute=route;if(!route.id.startsWith("import:")&&!isDebugHarvestRoute(route))onLoadDetail(route.id)}.padding(horizontal=16.dp,vertical=8.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(12.dp)) {
    RouteLibraryGlyph(if(route.routeShape=="loop")Icons.Outlined.Cached else Icons.Outlined.Timeline)
    Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(3.dp)) {
     Text(route.name,style=MaterialTheme.typography.titleSmall,fontWeight=FontWeight.SemiBold,maxLines=1,overflow=TextOverflow.Ellipsis)
     Text(stringResource(R.string.route_library_row_summary_format,routeDistanceLabel(route.distanceM,unitSystem),route.owner.displayName),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant,maxLines=1,overflow=TextOverflow.Ellipsis)
     if(isDebugHarvestRoute(route))DebugTestRouteBadge()
    }
    if(route.isBookmarked&&!route.isOwner&&!isDebugHarvestRoute(route))Icon(Icons.Outlined.Bookmark,stringResource(R.string.route_library_accessibility_saved),tint=MaterialTheme.colorScheme.primary)
   }
   HorizontalDivider(Modifier.padding(start=62.dp))
  }
 }
 if(pendingNearby)AlertDialog(onDismissRequest={pendingNearby=false},title={Text(stringResource(R.string.routes_location_title))},text={Text(stringResource(R.string.routes_location_body))},confirmButton={TextButton({locationPermission.launch(Manifest.permission.ACCESS_COARSE_LOCATION)}){Text(stringResource(R.string.routes_location_allow))}},dismissButton={TextButton({pendingNearby=false}){Text(stringResource(R.string.routes_close))}})
 selectedRoute?.let{selected->
  val detail=routeDetail?.takeIf{it.id==selected.id}?:selected
  EmbeddedCommunityRouteDetail(route=detail,loading=routeDetailLoading&&routeDetail?.id!=selected.id,unitSystem=unitSystem,onClose={selectedRoute=null;onClearDetail()},onRetry={if(!isDebugHarvestRoute(selected))onLoadDetail(selected.id)},onFollow={reverse->onFollow(CommunityRecordingCoordinator.launch(detail,reverse));selectedRoute=null;onClearDetail()},onBookmark={onBookmark(detail)},onRemovePublished={onRemovePublished(detail.id)})
 }
 selectedImportedRoute?.let { route ->
  ImportedRoutePreview(route=route,onClose={selectedImportedRoute=null},onUse={onFollow(CommunityRecordingCoordinator.launch(route,false));selectedImportedRoute=null},onDelete={confirmDeleteImported=route})
 }
 confirmDeleteImported?.let { route ->
  AlertDialog(onDismissRequest={confirmDeleteImported=null},title={Text(stringResource(R.string.route_import_delete_confirmation_title))},text={Text(stringResource(R.string.route_import_delete_confirmation_message))},confirmButton={TextButton({importedRoutes=importedRoutes.filterNot{it.id==route.id};confirmDeleteImported=null;if(selectedImportedRoute?.id==route.id)selectedImportedRoute=null;onImportedDelete()},colors=ButtonDefaults.textButtonColors(contentColor=MaterialTheme.colorScheme.error)){Text(stringResource(R.string.route_import_action_delete))}},dismissButton={TextButton({confirmDeleteImported=null}){Text(stringResource(R.string.routes_close))}})
 }
}

@Composable private fun ImportedRoutePreview(route:CommunityRoute,onClose:()->Unit,onUse:()->Unit,onDelete:()->Unit){
 Dialog(onDismissRequest=onClose,properties=DialogProperties(usePlatformDefaultWidth=false)) {
  Surface(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.background) {
   Column(Modifier.fillMaxSize()) {
    Row(Modifier.fillMaxWidth().heightIn(min=56.dp).padding(horizontal=8.dp),verticalAlignment=Alignment.CenterVertically){IconButton(onClose){Icon(Icons.AutoMirrored.Outlined.ArrowBack,stringResource(R.string.routes_close))};Text(stringResource(R.string.route_import_preview_title),Modifier.weight(1f),style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.SemiBold)}
    Column(Modifier.fillMaxSize().padding(16.dp),verticalArrangement=Arrangement.spacedBy(20.dp),horizontalAlignment=Alignment.CenterHorizontally) {
     val points=route.coordinates()
     if(points.size>1)PlainstrideRouteMap(points,Modifier.fillMaxWidth().weight(1f).clip(RoundedCornerShape(18.dp)))
     Column(horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(5.dp)) {Text(route.name,style=MaterialTheme.typography.headlineSmall,fontWeight=FontWeight.Bold);Text(stringResource(R.string.route_import_preview_privacy),style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant,textAlign=androidx.compose.ui.text.style.TextAlign.Center)}
     Button(onUse,Modifier.fillMaxWidth().heightIn(min=48.dp)){Icon(Icons.Outlined.DirectionsRun,null);Spacer(Modifier.width(8.dp));Text(stringResource(R.string.route_import_action_use))}
     OutlinedButton(onDelete,Modifier.fillMaxWidth().heightIn(min=48.dp),colors=ButtonDefaults.outlinedButtonColors(contentColor=MaterialTheme.colorScheme.error)){Icon(Icons.Outlined.Delete,null);Spacer(Modifier.width(8.dp));Text(stringResource(R.string.route_import_action_delete))}
    }
   }
  }
 }
}

@Composable private fun RouteLibraryAction(label:String,icon:androidx.compose.ui.graphics.vector.ImageVector,onClick:()->Unit){TextButton(onClick,Modifier.fillMaxWidth().heightIn(min=44.dp),contentPadding=PaddingValues(horizontal=8.dp,vertical=4.dp)){Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)){Icon(icon,null);Text(label,style=MaterialTheme.typography.bodyMedium)}}}
@Composable private fun RouteLibrarySectionLabel(label:String){Text(label.uppercase(),Modifier.fillMaxWidth().padding(start=16.dp,end=16.dp,top=18.dp,bottom=7.dp),style=MaterialTheme.typography.labelMedium,fontWeight=FontWeight.SemiBold,color=MaterialTheme.colorScheme.onSurfaceVariant)}
@Composable private fun RouteLibraryGlyph(icon:androidx.compose.ui.graphics.vector.ImageVector){Surface(Modifier.size(34.dp),shape=CircleShape,color=MaterialTheme.colorScheme.primary.copy(alpha=.12f)){Box(contentAlignment=Alignment.Center){Icon(icon,null,tint=MaterialTheme.colorScheme.primary,modifier=Modifier.size(18.dp))}}}
@Composable private fun DebugTestRouteBadge(){val label=stringResource(R.string.route_library_test_badge);val accessibilityLabel=stringResource(R.string.route_library_test_badge_accessibility);Text(label,Modifier.semantics{contentDescription=accessibilityLabel},style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.primary)}
private fun routeDistanceLabel(meters:Double,unitSystem:com.plainstride.outbound.core.model.activity.MeasurementUnitSystem):String{val distance=com.plainstride.outbound.core.model.activity.SessionFormatting.distance(meters,unitSystem);val unit=if(unitSystem==com.plainstride.outbound.core.model.activity.MeasurementUnitSystem.metric)"km" else "mi";return "%.1f %s".format(java.util.Locale.getDefault(),distance.value,unit)}

@Composable private fun EmbeddedCommunityRouteDetail(route:CommunityRoute,loading:Boolean,unitSystem:com.plainstride.outbound.core.model.activity.MeasurementUnitSystem,onClose:()->Unit,onRetry:()->Unit,onFollow:(Boolean)->Unit,onBookmark:()->Unit,onRemovePublished:()->Unit){
 val context=LocalContext.current
 var bookmarked by remember(route.id){mutableStateOf(route.isBookmarked)}
 var confirmRemove by remember{mutableStateOf(false)}
 Dialog(onDismissRequest=onClose,properties=DialogProperties(usePlatformDefaultWidth=false)) {
  Surface(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.background) {
   Column(Modifier.fillMaxSize()) {
    Row(Modifier.fillMaxWidth().heightIn(min=56.dp).padding(horizontal=8.dp),verticalAlignment=Alignment.CenterVertically){IconButton(onClose){Icon(Icons.AutoMirrored.Outlined.ArrowBack,stringResource(R.string.routes_close))};Text(route.name,Modifier.weight(1f),style=MaterialTheme.typography.titleMedium,fontWeight=FontWeight.SemiBold,maxLines=1,overflow=TextOverflow.Ellipsis)}
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
     item {
      Box(Modifier.fillMaxWidth().height(310.dp).clip(RoundedCornerShape(18.dp)).background(MaterialTheme.colorScheme.surfaceVariant),contentAlignment=Alignment.Center){
       val points=route.coordinates()
       if(points.size>1)PlainstrideRouteMap(points,Modifier.fillMaxSize()) else if(loading)CircularProgressIndicator() else Column(horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(8.dp)){Icon(Icons.Outlined.WifiOff,null);Text(stringResource(R.string.route_library_detail_unavailable_title),style=MaterialTheme.typography.titleSmall);TextButton(onRetry){Text(stringResource(R.string.route_library_detail_retry))}}
      }
     }
     item { Column(verticalArrangement=Arrangement.spacedBy(6.dp)) {
      Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)){Text(route.name,Modifier.weight(1f),style=MaterialTheme.typography.headlineSmall,fontWeight=FontWeight.Bold);if(isDebugHarvestRoute(route))DebugTestRouteBadge()}
      Text(stringResource(R.string.route_library_detail_creator_format,route.owner.displayName),style=MaterialTheme.typography.bodyMedium,color=MaterialTheme.colorScheme.onSurfaceVariant)
      val distance=routeDistanceLabel(route.distanceM,unitSystem)
      val elevation=route.elevationGainM?.let{meters->val unit=if(unitSystem==com.plainstride.outbound.core.model.activity.MeasurementUnitSystem.metric)"m" else "ft";" · ${"%.0f".format(java.util.Locale.getDefault(),if(unitSystem==com.plainstride.outbound.core.model.activity.MeasurementUnitSystem.metric)meters else meters*3.28084)} $unit"}.orEmpty()
      Text(distance+elevation,style=MaterialTheme.typography.titleSmall,fontWeight=FontWeight.SemiBold)
      Text(stringResource(R.string.route_library_detail_stats_format,route.bookmarkCount,route.completionCount),style=MaterialTheme.typography.bodySmall,color=MaterialTheme.colorScheme.onSurfaceVariant)
      route.description?.takeIf(String::isNotBlank)?.let{Text(it,Modifier.padding(top=4.dp),style=MaterialTheme.typography.bodyMedium)}
     } }
     item { Button({onFollow(false)},Modifier.fillMaxWidth().heightIn(min=48.dp)){Text(stringResource(R.string.route_library_action_start))} }
     item {
      if(route.isOwner)OutlinedButton({confirmRemove=true},Modifier.fillMaxWidth(),enabled=!loading){Icon(Icons.Outlined.Delete,null);Spacer(Modifier.width(8.dp));Text(stringResource(R.string.route_library_remove_published_action))}
      else if(!isDebugHarvestRoute(route))OutlinedButton({onBookmark();bookmarked=!bookmarked},Modifier.fillMaxWidth(),enabled=!loading){Icon(if(bookmarked)Icons.Outlined.BookmarkRemove else Icons.Outlined.Bookmark,null);Spacer(Modifier.width(8.dp));Text(stringResource(if(bookmarked)R.string.library_my_routes_remove else R.string.library_my_routes_save))}
     }
    }
   }
  }
 }
 if(confirmRemove)AlertDialog(onDismissRequest={confirmRemove=false},title={Text(stringResource(R.string.route_library_remove_published_confirmation_title))},text={Text(stringResource(R.string.route_library_remove_published_confirmation_message))},confirmButton={TextButton({confirmRemove=false;onRemovePublished()},colors=ButtonDefaults.textButtonColors(contentColor=MaterialTheme.colorScheme.error)){Text(stringResource(R.string.route_library_remove_published_confirm))}},dismissButton={TextButton({confirmRemove=false}){Text(stringResource(R.string.routes_close))}})
}

@Composable private fun RouteDetailDialog(route:CommunityRoute,close:()->Unit,follow:(Boolean)->Unit){val context=LocalContext.current;var reverse by remember{mutableStateOf(false)};AlertDialog(onDismissRequest=close,title={Text(route.name)},text={Column(verticalArrangement=Arrangement.spacedBy(12.dp)){route.description?.let{Text(it)};route.coordinates().takeIf{it.size>1}?.let{PlainstrideRouteMap(if(reverse)it.reversed() else it,Modifier.fillMaxWidth().height(220.dp))};Row{Text(stringResource(R.string.routes_reverse),Modifier.weight(1f));Switch(reverse,{reverse=it})};TextButton({shareRoute(context,route)}){Text(stringResource(R.string.routes_export))}}},confirmButton={Button({follow(reverse)}){Text(stringResource(R.string.routes_follow))}},dismissButton={TextButton(close){Text(stringResource(R.string.routes_close))}})}
private fun shareRoute(context:android.content.Context,route:CommunityRoute){val points=route.guidancePoints();if(points.size<2)return;val directory=File(context.cacheDir,"activity_exports").apply{mkdirs()};val file=File(directory,"route-${route.id.filter(Char::isLetterOrDigit).take(48)}.gpx");file.writeBytes(OfflineRouteExporter.gpx(route.name,points));val uri=FileProvider.getUriForFile(context,"${context.packageName}.activityphotos",file);context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("application/gpx+xml").putExtra(Intent.EXTRA_STREAM,uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),null))}

private fun CommunityRoute.coordinates(): List<MapCoordinate> {
  val coordinates = geometry?.get("coordinates") as? JsonArray ?: return emptyList()
  val line = if (coordinates.firstOrNull() is JsonPrimitive) listOf(coordinates) else coordinates.mapNotNull { it as? JsonArray }
  return line.mapNotNull { pair -> val lon=(pair.getOrNull(0) as? JsonPrimitive)?.doubleOrNull; val lat=(pair.getOrNull(1) as? JsonPrimitive)?.doubleOrNull; if(lat!=null&&lon!=null) MapCoordinate(lat,lon) else null }
}
fun CommunityRoute.guidancePoints()=coordinates().map{GuidancePoint(it.latitude,it.longitude)}

private fun isDebugHarvestRoute(route: CommunityRoute): Boolean =
 route.id == HarvestRunSimulation.ROUTE_ID

private fun debugHarvestRoute(name: String): CommunityRoute {
 val simulationRoute = HarvestRunSimulation.route
 val geometry = buildJsonObject {
  put("type", "LineString")
  put("coordinates", buildJsonArray {
   simulationRoute.points.forEach { point ->
    add(buildJsonArray {
     add(JsonPrimitive(point.longitude))
     add(JsonPrimitive(point.latitude))
     add(JsonPrimitive(point.altitudeMeters ?: 0.0))
    })
   }
  })
 }
 return CommunityRoute(
  id = HarvestRunSimulation.ROUTE_ID,
  name = name,
  description = null,
  activityType = "running",
  distanceM = 21_097.5,
  elevationGainM = 112.0,
  routeShape = "out_and_back",
  owner = RouteOwner("debug-harvest-fixture", "Test route"),
  geometry = geometry,
 )
}

private fun importRoute(text:String,fileName:String?):CommunityRoute?{
 val trimmed=text.trim()
 val points=if(trimmed.startsWith("{")){
  val root=Json.parseToJsonElement(trimmed).jsonObject
  val geometry=(root["geometry"] as? JsonObject)?:root
  val coordinates=geometry["coordinates"] as? JsonArray ?: return null
  val line=if(coordinates.firstOrNull() is JsonPrimitive) listOf(coordinates) else coordinates.mapNotNull{it as? JsonArray}
  line.mapNotNull{pair->val lon=(pair.getOrNull(0) as? JsonPrimitive)?.doubleOrNull;val lat=(pair.getOrNull(1) as? JsonPrimitive)?.doubleOrNull;if(lat!=null&&lon!=null)MapCoordinate(lat,lon)else null}
 }else Regex("<trkpt[^>]*lat=[\"']([^\"']+)[\"'][^>]*lon=[\"']([^\"']+)[\"']",RegexOption.IGNORE_CASE).findAll(trimmed).mapNotNull{match->val lat=match.groupValues[1].toDoubleOrNull();val lon=match.groupValues[2].toDoubleOrNull();if(lat!=null&&lon!=null)MapCoordinate(lat,lon)else null}.toList()
 if(points.size<2)return null
 val geometry=buildJsonObject{put("type","LineString");put("coordinates",buildJsonArray{points.forEach{point->add(buildJsonArray{add(point.longitude);add(point.latitude)})}})}
 val name=fileName?.substringAfterLast('/')?.substringBeforeLast('.')?.takeIf(String::isNotBlank)?:"Imported route"
 return CommunityRoute("import:${UUID.randomUUID()}",name,null,"run",routeDistance(points),null,"full",owner=RouteOwner("local","You"),geometry=geometry)
}
private fun routeDistance(points:List<MapCoordinate>)=points.zipWithNext().sumOf{(a,b)->val radius=6371000.0;val dLat=Math.toRadians(b.latitude-a.latitude);val dLon=Math.toRadians(b.longitude-a.longitude);val x=kotlin.math.sin(dLat/2)*kotlin.math.sin(dLat/2)+kotlin.math.cos(Math.toRadians(a.latitude))*kotlin.math.cos(Math.toRadians(b.latitude))*kotlin.math.sin(dLon/2)*kotlin.math.sin(dLon/2);radius*2*kotlin.math.atan2(kotlin.math.sqrt(x),kotlin.math.sqrt(1-x))}
