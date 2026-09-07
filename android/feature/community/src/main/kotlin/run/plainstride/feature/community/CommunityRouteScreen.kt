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

@Composable fun CommunityRouteScreen(library: RouteLibrary, scope: RouteScope, onScope: (RouteScope)->Unit, onRefresh:()->Unit, onSearch:(String)->Unit, onOpen:(CommunityRoute)->Unit, onBookmark:(CommunityRoute)->Unit) {
 var query by remember { mutableStateOf("") }
 LazyColumn(Modifier.fillMaxSize(), contentPadding=PaddingValues(16.dp), verticalArrangement=Arrangement.spacedBy(12.dp)) {
  item { Row { Text(stringResource(R.string.routes_title), style=MaterialTheme.typography.headlineMedium, fontWeight=FontWeight.Bold, modifier=Modifier.weight(1f)); IconButton(onRefresh){Icon(Icons.Outlined.Refresh,stringResource(R.string.routes_refresh))} } }
  item { SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()){ RouteScope.entries.forEachIndexed { index,item->SegmentedButton(item==scope,{onScope(item)},SegmentedButtonDefaults.itemShape(index,RouteScope.entries.size)){Text(stringResource(when(item){RouteScope.DISCOVERY->R.string.routes_discover;RouteScope.MINE->R.string.routes_mine;RouteScope.NEARBY->R.string.routes_nearby}))} } } }
  if(scope==RouteScope.DISCOVERY) item { OutlinedTextField(query,{query=it;onSearch(it)},Modifier.fillMaxWidth(),label={Text(stringResource(R.string.routes_search))},leadingIcon={Icon(Icons.Outlined.Search,null)}) }
  if(library.stale) item { Text(stringResource(R.string.routes_offline),style=MaterialTheme.typography.labelMedium) }
  items(library.routes,key=CommunityRoute::id){ route->ElevatedCard({onOpen(route)},Modifier.fillMaxWidth()){Column{ route.coordinates().takeIf{it.size>1}?.let { PlainstrideRouteMap(it,Modifier.fillMaxWidth().height(150.dp)) }; Column(Modifier.padding(16.dp)){Row{Text(route.name,Modifier.weight(1f),fontWeight=FontWeight.SemiBold);IconButton({onBookmark(route)}){Icon(if(route.isBookmarked) Icons.Outlined.Bookmark else Icons.Outlined.BookmarkBorder,stringResource(R.string.routes_bookmark))}};Text(stringResource(R.string.routes_summary,route.distanceM/1000,route.elevationGainM?:0.0));Text(stringResource(R.string.routes_community_counts,route.bookmarkCount,route.completionCount),style=MaterialTheme.typography.bodySmall)}}} }
  if(library.routes.isEmpty()) item { Text(stringResource(R.string.routes_empty),Modifier.padding(24.dp)) }
 }
}

private fun CommunityRoute.coordinates(): List<MapCoordinate> {
  val coordinates = geometry?.get("coordinates") as? JsonArray ?: return emptyList()
  val line = if (coordinates.firstOrNull() is JsonPrimitive) listOf(coordinates) else coordinates.mapNotNull { it as? JsonArray }
  return line.mapNotNull { pair -> val lon=(pair.getOrNull(0) as? JsonPrimitive)?.doubleOrNull; val lat=(pair.getOrNull(1) as? JsonPrimitive)?.doubleOrNull; if(lat!=null&&lon!=null) MapCoordinate(lat,lon) else null }
}
