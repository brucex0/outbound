package com.plainstride.outbound.feature.community.planning

import android.Manifest
import android.content.pm.PackageManager
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.plainstride.outbound.core.designsystem.*
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.feature.community.R
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

@HiltViewModel class RoutePlannerViewModel @Inject constructor(private val services: AndroidPlannerServices): ViewModel() {
    private var session: RoutePlannerSession? = null
    private var owner: String? = null
    fun session(accountId: String, activity: PlannerActivity, distanceM: Double?): RoutePlannerSession {
        if(owner!=accountId || session==null) { session?.close();owner=accountId;session=RoutePlannerSession(accountId,activity,distanceM,services,viewModelScope) }
        return requireNotNull(session)
    }
    override fun onCleared(){session?.close()}
}

/** Contextual host: only an immutable accepted route crosses back into its caller. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable fun RoutePlannerScreen(
    accountId: String, initialActivity: PlannerActivity, initialDistanceM: Double?, unitSystem: MeasurementUnitSystem,
    onAccepted: (AcceptedPlannerRoute)->Unit, onCancel: ()->Unit, viewModel: RoutePlannerViewModel = hiltViewModel(),
) {
    val session=remember(accountId,viewModel){viewModel.session(accountId,initialActivity,initialDistanceM)}
    val state by session.state.collectAsStateWithLifecycle()
    val context=LocalContext.current
    val metric=unitSystem==MeasurementUnitSystem.metric
    val divisor=if(metric)1000.0 else 1609.344
    var distanceText by rememberSaveable(accountId,unitSystem) { mutableStateOf(state.targetDistanceM?.let { String.format(java.util.Locale.US,"%.1f",it/divisor) }.orEmpty()) }
    var editingInputs by remember { mutableStateOf(true) }
    var searchingVia by remember { mutableStateOf<Boolean?>(null) }
    var query by remember { mutableStateOf("") }
    var pickingVia by remember { mutableStateOf<Boolean?>(null) }
    var proposedVia by remember { mutableStateOf<PlannerPlace?>(null) }
    val permission=rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        if(result.values.any{it})session.locate() else Toast.makeText(context,R.string.planner_location_unavailable,Toast.LENGTH_LONG).show()
    }
    val message=state.message
    LaunchedEffect(message) { if(message!=null) { Toast.makeText(context,when(message){PlannerMessage.LOCATION_UNAVAILABLE->R.string.planner_location_unavailable;PlannerMessage.NO_PLACES->R.string.planner_no_places;PlannerMessage.INVALID_DISTANCE->R.string.planner_distance_invalid;PlannerMessage.SAVE_FAILED->R.string.planner_save_failed;else->R.string.planner_failed},Toast.LENGTH_LONG).show();session.consumeMessage() } }
    fun back(){ when {state.selected!=null->session.select(null);pickingVia!=null->pickingVia=null;else->{session.cancel();onCancel()}} }
    BackHandler { back() }
    fun choose(place: PlannerPlace,via:Boolean) { if(via) proposedVia=place else session.edit(start=place);searchingVia=null;session.clearSearch() }
    Surface(Modifier.fillMaxSize(),color=MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
            Row(verticalAlignment=Alignment.CenterVertically) {
                IconButton(onClick={back()}){Icon(Icons.AutoMirrored.Outlined.ArrowBack,stringResource(R.string.planner_back))}
                Text(stringResource(R.string.planner_title),style=MaterialTheme.typography.titleLarge)
            }
            OutlinedButton(onClick={editingInputs=true},modifier=Modifier.padding(horizontal=16.dp)) { Text(stringResource(R.string.planner_inputs)) }
            if(pickingVia!=null)Text(stringResource(if(pickingVia==true)R.string.planner_pick_access else R.string.planner_pick_start),modifier=Modifier.padding(16.dp))
            val colors=RouteComparisonColors
            val mapPoints=state.candidates.flatMap{it.points}.map{MapCoordinate(it.latitude,it.longitude)}
            PlainstrideRouteMap(
                points=mapPoints,modifier=Modifier.fillMaxWidth().weight(1f),showEndpointMarkers=false,
                routeSegments=state.candidates.mapIndexed{i,c->MapRouteSegment(c.points.map{MapCoordinate(it.latitude,it.longitude)},colors[i%colors.size].copy(alpha=if(state.selected==null || state.selected?.id==c.id)1f else .25f),c.id)},
                markers=buildList {
                    state.start?.let{add(MapRouteMarker("start",MapCoordinate(it.coordinate.latitude,it.coordinate.longitude),context.getString(R.string.planner_start)))}
                    state.via?.let{add(MapRouteMarker("via",MapCoordinate(it.coordinate.latitude,it.coordinate.longitude),context.getString(R.string.planner_via)))}
                    state.candidates.forEachIndexed{i,c->c.points.getOrNull(c.points.size/3)?.let{add(MapRouteMarker(c.id,MapCoordinate(it.latitude,it.longitude),"${i+1}",participantInitials="${i+1}",pinColor=colors[i%colors.size]))}}
                },
                onMarkerClick={id->state.candidates.firstOrNull{it.id==id}?.let(session::select)},
                onRouteClick={id->state.candidates.firstOrNull{it.id==id}?.let(session::select)},
                followCoordinate=state.start?.coordinate?.takeIf{state.candidates.isEmpty()}?.let{MapCoordinate(it.latitude,it.longitude)},
                followAnimationDurationMs=600,followZoom=14f,resumeFollowAfterGesture=false,
                initialCameraCoordinate=state.start?.coordinate?.let{MapCoordinate(it.latitude,it.longitude)},
                onMapClick={point->pickingVia?.let{via->choose(PlannerPlace(PlannerCoordinate(point.latitude,point.longitude)),via);pickingVia=null}},
            )
            if(state.candidates.isNotEmpty()) Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(12.dp),horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                state.candidates.forEachIndexed { i,c->
                    Card(onClick={session.select(c)},modifier=Modifier.width(210.dp)) { Column(Modifier.padding(12.dp)) {
                        Text("${i+1}. ${stringResource(if(c.source==PlannerSource.COMMUNITY)R.string.planner_existing else R.string.planner_generated)}",style=MaterialTheme.typography.titleSmall)
                        Text(routeDistance(c.distanceM,metric),style=MaterialTheme.typography.bodyLarge)
                        c.name?.let{Text(it,style=MaterialTheme.typography.bodySmall)}
                    } }
                }
            }
            Column(Modifier.fillMaxWidth().heightIn(max=190.dp).verticalScroll(rememberScrollState()).padding(horizontal=16.dp,vertical=8.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                state.targetDistanceM?.let{Text(routeDistance(it,metric),style=MaterialTheme.typography.titleSmall)}
                if(state.busy)LinearProgressIndicator(Modifier.fillMaxWidth())
                if(state.completed && state.candidates.isEmpty())Text(stringResource(R.string.planner_no_routes),style=MaterialTheme.typography.bodySmall)
                if(state.generationUnavailable)Text(stringResource(R.string.planner_generation_unavailable),style=MaterialTheme.typography.bodySmall)
                Button(onClick={if(state.start==null || state.targetDistanceM==null)editingInputs=true else session.generate()},enabled=!state.busy && state.activity!=PlannerActivity.CYCLING){Text(stringResource(if(state.candidates.isEmpty())R.string.planner_find else R.string.planner_again))}
                if(state.activity==PlannerActivity.CYCLING)Text(stringResource(R.string.planner_bike_unavailable),style=MaterialTheme.typography.bodySmall)
            }
        }
    }
    if(editingInputs) ModalBottomSheet(onDismissRequest={editingInputs=false}) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).imePadding().padding(20.dp),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.planner_start),style=MaterialTheme.typography.labelLarge)
                Text(state.start?.name ?: stringResource(if(state.start==null) R.string.planner_choose_start else R.string.planner_map_point),style=MaterialTheme.typography.bodyMedium)
                FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick={query="";searchingVia=false}){Text(stringResource(R.string.planner_search))}
                    OutlinedButton(onClick={pickingVia=false;editingInputs=false}){Text(stringResource(R.string.planner_map))}
                    OutlinedButton(onClick={
                        if(ContextCompat.checkSelfPermission(context,Manifest.permission.ACCESS_COARSE_LOCATION)==PackageManager.PERMISSION_GRANTED)session.locate()
                        else permission.launch(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION,Manifest.permission.ACCESS_FINE_LOCATION))
                    }){Text(stringResource(R.string.planner_current))}
                }
                OutlinedTextField(value=distanceText,onValueChange={distanceText=it;session.edit(distance=it.replace(',','.').toDoubleOrNull()?.times(divisor))},label={Text(stringResource(if(metric)R.string.planner_distance_km else R.string.planner_distance_mi))},keyboardOptions=KeyboardOptions(keyboardType=KeyboardType.Decimal),singleLine=true,modifier=Modifier.fillMaxWidth())
                Text(stringResource(R.string.planner_tolerance),style=MaterialTheme.typography.bodySmall)
                FlowRow(horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick={query="";searchingVia=true}){Text(state.via?.name ?: stringResource(if(state.via==null)R.string.planner_via else R.string.planner_map_point))}
                    if(state.via!=null) OutlinedButton(onClick={session.edit(via=null)}){Text(stringResource(R.string.planner_remove_via))}
                    FilterChip(selected=state.lessClimbing,onClick={session.edit(lessClimbing=!state.lessClimbing)},label={Text(stringResource(R.string.planner_less_climbing))})
                }
                Button(onClick={editingInputs=false}){Text(stringResource(R.string.planner_done))}
                if(state.activity==PlannerActivity.CYCLING)Text(stringResource(R.string.planner_bike_unavailable),style=MaterialTheme.typography.bodySmall)
                if(pickingVia!=null)Text(stringResource(if(pickingVia==true)R.string.planner_pick_access else R.string.planner_pick_start),style=MaterialTheme.typography.labelLarge)
            }
    }
    if(searchingVia!=null) AlertDialog(onDismissRequest={searchingVia=null;session.clearSearch()},title={Text(stringResource(if(searchingVia==true)R.string.planner_via else R.string.planner_start))},text={Column(Modifier.verticalScroll(rememberScrollState()),verticalArrangement=Arrangement.spacedBy(8.dp)){
        OutlinedTextField(query,{query=it;session.clearSearch()},label={Text(stringResource(R.string.planner_search))},singleLine=true)
        OutlinedButton(onClick={session.search(query)},enabled=query.isNotBlank()&&!state.busy){Text(stringResource(R.string.planner_search))}
        OutlinedButton(onClick={pickingVia=searchingVia;searchingVia=null;editingInputs=false;session.clearSearch()}){Text(stringResource(R.string.planner_map))}
        if(state.busy)CircularProgressIndicator()
        state.searchResults.forEach{place->TextButton(onClick={choose(place,searchingVia==true)}){Text(place.name ?: stringResource(R.string.planner_map_point))}}
    }},confirmButton={},dismissButton={TextButton(onClick={searchingVia=null;session.clearSearch()}){Text(stringResource(R.string.planner_close))}})
    proposedVia?.let{place->AlertDialog(onDismissRequest={proposedVia=null},title={Text(stringResource(R.string.planner_access_title))},text={Text(stringResource(R.string.planner_access_confirm))},confirmButton={Button(onClick={session.edit(via=place);proposedVia=null}){Text(stringResource(R.string.planner_confirm))}},dismissButton={TextButton(onClick={proposedVia=null;pickingVia=true;editingInputs=false}){Text(stringResource(R.string.planner_map))}})}
    state.selected?.let { candidate ->
        ModalBottomSheet(onDismissRequest={session.select(null)}) {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
                Text(candidate.name ?: stringResource(R.string.planner_generated),style=MaterialTheme.typography.titleLarge)
                Text(stringResource(if(candidate.source==PlannerSource.COMMUNITY)R.string.planner_existing else R.string.planner_generated))
                Text(routeDistance(candidate.distanceM,metric),style=MaterialTheme.typography.headlineSmall)
                Text(candidate.elevationGainM?.let{stringResource(R.string.planner_elevation,if(metric)it else it*3.28084,if(metric)"m" else "ft")} ?: stringResource(R.string.planner_elevation_unknown))
                Text(stringResource(R.string.planner_start_displacement,routeDistance(candidate.startDisplacementM,metric)))
                if(candidate.source==PlannerSource.COMMUNITY)Text(stringResource(R.string.planner_original_start),style=MaterialTheme.typography.bodySmall)
                candidate.attribution?.let{Text(it,style=MaterialTheme.typography.bodySmall)}
                FlowRow(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                    Button(onClick={session.accept(onAccepted)},enabled=!state.accepting){Text(stringResource(R.string.planner_use))}
                    OutlinedButton(onClick={session.select(null)},enabled=!state.accepting){Text(stringResource(R.string.planner_close))}
                }
            }
        }
    }
}
private fun routeDistance(meters: Double, metric: Boolean): String = String.format(java.util.Locale.getDefault(),"%.2f %s",meters/(if(metric)1000.0 else 1609.344),if(metric)"km" else "mi")
