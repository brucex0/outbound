package com.plainstride.outbound.feature.recording

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import kotlinx.coroutines.delay

data class StretchMovement(val id: String, val title: Int, val instruction: Int, val side: Int?, val seconds: Int = 60)
data class StretchRoutine(val id: String, val movements: List<StretchMovement>)
object PostWorkoutStretchCatalog { fun routine(kind: ActivityKind): StretchRoutine? { val p = when (kind) { ActivityKind.RUNNING -> "run"; ActivityKind.CYCLING -> "bike"; ActivityKind.HIKING -> "hike"; ActivityKind.SWIMMING -> "swim"; ActivityKind.WALKING -> return null }; val r = listOf(Triple(R.string.stretch_movement_calf,R.string.stretch_instruction_calf,R.string.stretch_side_left),Triple(R.string.stretch_movement_quad,R.string.stretch_instruction_quad,R.string.stretch_side_right),Triple(R.string.stretch_movement_hip,R.string.stretch_instruction_hip,R.string.stretch_side_left),Triple(R.string.stretch_movement_shoulder,R.string.stretch_instruction_shoulder,null)); return StretchRoutine("post_save_${p}_v1", r.mapIndexed { i, (t,x,s) -> StretchMovement("${p}_$i",t,x,s) }) } }
@Composable fun PostWorkoutStretchRoute(kind: ActivityKind, onDone: () -> Unit, onEvent: (String,String?) -> Unit) {
 val routine=remember(kind){PostWorkoutStretchCatalog.routine(kind)} ?: run { onDone(); return }; var chosen by remember{mutableStateOf(false)}; var i by remember{mutableIntStateOf(0)}; var left by remember{mutableIntStateOf(routine.movements[0].seconds)}; var running by remember{mutableStateOf(false)}; var complete by remember{mutableStateOf(false)}; var confirm by remember{mutableStateOf(false)}; val view=LocalView.current; val owner=LocalLifecycleOwner.current; val move=routine.movements[i]
 fun end(result:String?){running=false;view.keepScreenOn=false;result?.let{onEvent("post_workout_stretch_dismissed",it)};onDone()}
 DisposableEffect(owner){val obs=LifecycleEventObserver{_,e->if(e==Lifecycle.Event.ON_STOP||e==Lifecycle.Event.ON_PAUSE){running=false;view.keepScreenOn=false}};owner.lifecycle.addObserver(obs);onDispose{owner.lifecycle.removeObserver(obs);view.keepScreenOn=false}}
 LaunchedEffect(running,i){while(running&&!complete){delay(1000);if(left<=1){if(i==routine.movements.lastIndex){complete=true;running=false;view.keepScreenOn=false;onEvent("post_workout_stretch_completed",null)}else{i++;left=routine.movements[i].seconds}}else left--}}
 LaunchedEffect(Unit){onEvent("post_workout_stretch_offered",null)};LaunchedEffect(chosen){if(chosen)onEvent("post_workout_stretch_started",null)};BackHandler{if(running)confirm=true else end(if(chosen)"ended_early" else "not_started")}
 Column(Modifier.fillMaxSize().safeDrawingPadding().padding(24.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(18.dp)){Row(Modifier.fillMaxWidth(),verticalAlignment=Alignment.CenterVertically){Text(stringResource(R.string.stretch_saved),style=MaterialTheme.typography.titleLarge);Spacer(Modifier.weight(1f));TextButton({end(if(chosen)"ended_early" else "not_started")}){Text(stringResource(R.string.stretch_done))}};if(!chosen){Spacer(Modifier.weight(1f));Text(stringResource(R.string.stretch_offer_title),style=MaterialTheme.typography.headlineMedium);Text(stringResource(R.string.stretch_offer_body));Button({chosen=true;running=true;view.keepScreenOn=true}){Text(stringResource(R.string.stretch_start))};OutlinedButton({end("not_started")}){Text(stringResource(R.string.stretch_done))};Text(stringResource(R.string.stretch_disclaimer));Spacer(Modifier.weight(1f))}else if(complete){Spacer(Modifier.weight(1f));Icon(Icons.Default.CheckCircle,null,Modifier.size(72.dp));Text(stringResource(R.string.stretch_complete_title),style=MaterialTheme.typography.headlineMedium);Button({end(null)}){Text(stringResource(R.string.stretch_done))};Spacer(Modifier.weight(1f))}else{Spacer(Modifier.weight(1f));Text(stringResource(move.title),style=MaterialTheme.typography.headlineMedium);move.side?.let{Text(stringResource(it))};Text(stringResource(move.instruction));Text(left.toString(),style=MaterialTheme.typography.displayMedium);LinearProgressIndicator({i.toFloat()/routine.movements.size},Modifier.fillMaxWidth());Text(stringResource(R.string.stretch_safety));Row(horizontalArrangement=Arrangement.spacedBy(12.dp)){Button({running=!running;view.keepScreenOn=running}){Text(stringResource(if(running)R.string.stretch_pause else R.string.stretch_resume))};OutlinedButton({if(i==routine.movements.lastIndex){complete=true;running=false;view.keepScreenOn=false;onEvent("post_workout_stretch_completed",null)}else{i++;left=routine.movements[i].seconds}}){Text(stringResource(if(i==routine.movements.lastIndex)R.string.stretch_finish else R.string.stretch_next))}};TextButton({if(running)confirm=true else end("ended_early")}){Text(stringResource(R.string.stretch_end))};Spacer(Modifier.weight(1f))}};if(confirm)AlertDialog(
  onDismissRequest = { confirm = false },
  title = { Text(stringResource(R.string.stretch_end_title)) },
  text = { Text(stringResource(R.string.stretch_end_message)) },
  confirmButton = { TextButton(onClick = { confirm = false; end("ended_early") }) { Text(stringResource(R.string.stretch_end_confirm)) } },
  dismissButton = { TextButton(onClick = { confirm = false }) { Text(stringResource(R.string.recording_cancel)) } },
)
}
