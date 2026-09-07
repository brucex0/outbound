package run.plainstride.feature.health

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle

@Composable fun CycleAwareSection(accountId:String,viewModel:CycleAwareViewModel=hiltViewModel()){
 LaunchedEffect(accountId){viewModel.start(accountId)};val state by viewModel.state.collectAsStateWithLifecycle();if(!state.loaded||!state.eligible)return
 var bleeding by remember{mutableStateOf(false)};var energy by remember{mutableIntStateOf(3)};var discomfort by remember{mutableIntStateOf(1)}
 Column(Modifier.fillMaxWidth().padding(horizontal=20.dp,vertical=8.dp),verticalArrangement=Arrangement.spacedBy(10.dp)){
  Row{Column(Modifier.weight(1f)){Text(stringResource(R.string.cycle_title),style=MaterialTheme.typography.titleMedium);Text(stringResource(R.string.cycle_privacy),style=MaterialTheme.typography.bodySmall)};Switch(state.enabled,viewModel::setEnabled)}
  if(state.enabled){HorizontalDivider();Text(stringResource(R.string.cycle_checkin_title));Row{Text(stringResource(R.string.cycle_period_today),Modifier.weight(1f));Switch(bleeding,{bleeding=it})};RatingRow(stringResource(R.string.cycle_energy),energy,{energy=it});RatingRow(stringResource(R.string.cycle_discomfort),discomfort,{discomfort=it});Button({viewModel.log(bleeding,energy,discomfort)},Modifier.fillMaxWidth()){Text(stringResource(R.string.cycle_save))};Text(stringResource(signalString(state.currentSignal)),style=MaterialTheme.typography.bodyMedium);Text(stringResource(R.string.cycle_agency),style=MaterialTheme.typography.bodySmall);if(state.logs.isNotEmpty())TextButton(viewModel::clear){Text(stringResource(R.string.cycle_delete),color=MaterialTheme.colorScheme.error)}}
 }
}
@Composable private fun RatingRow(label:String,value:Int,onValue:(Int)->Unit){Column{Text(stringResource(R.string.cycle_rating,label,value));Slider(value.toFloat(),{onValue(it.toInt().coerceIn(1,5))},valueRange=1f..5f,steps=3)}}
private fun signalString(value:CycleTrainingSignal)=when(value){CycleTrainingSignal.NO_ADJUSTMENT->R.string.cycle_no_change;CycleTrainingSignal.OFFER_FLEXIBLE_OPTION->R.string.cycle_flexible;CycleTrainingSignal.REDUCE_LOAD->R.string.cycle_reduce;CycleTrainingSignal.RECOMMEND_REST->R.string.cycle_rest}

@Composable fun CycleTodayGuidance(state:CycleAwareState,onKeep:()->Unit,onGentler:()->Unit){if(!state.enabled||state.currentSignal==CycleTrainingSignal.NO_ADJUSTMENT)return;ElevatedCard(Modifier.fillMaxWidth()){Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(8.dp)){Text(stringResource(signalString(state.currentSignal)),style=MaterialTheme.typography.titleMedium);Text(state.response?.explanation?:stringResource(R.string.cycle_today_reason),style=MaterialTheme.typography.bodySmall);Row(horizontalArrangement=Arrangement.spacedBy(8.dp)){TextButton(onKeep){Text(stringResource(R.string.cycle_keep_plan))};Button(onGentler){Text(stringResource(R.string.cycle_choose_gentler))}}}}}
