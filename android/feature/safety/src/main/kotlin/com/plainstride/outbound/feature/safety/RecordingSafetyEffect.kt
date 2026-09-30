package com.plainstride.outbound.feature.safety

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import java.time.Instant
import com.plainstride.outbound.feature.recording.RecordingSnapshot
import com.plainstride.outbound.feature.recording.RecordingStatus
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf

data class HeardLiveCheer(val shareId:String,val cheerId:String,val senderName:String)

@HiltViewModel class RecordingSafetyViewModel @Inject constructor(val coordinator:LiveShareCoordinator,private val audio:LiveCheerAudioPlayer,private val analytics:com.plainstride.outbound.core.analytics.ProductAnalytics):ViewModel(){
 private val mutableHeard=androidx.compose.runtime.mutableStateOf<HeardLiveCheer?>(null)
 val heard:HeardLiveCheer? get()=mutableHeard.value
 suspend fun receivePendingCheer(){
  if(mutableHeard.value!=null)return
  val cheer=coordinator.pendingVoiceCheer().getOrNull()?:return
  val bytes=runCatching{android.util.Base64.decode(cheer.audioBase64,android.util.Base64.DEFAULT)}.getOrNull()?:return
  if(audio.play(bytes)&&coordinator.markVoiceCheerPlayed(cheer).isSuccess){
   mutableHeard.value=HeardLiveCheer(coordinator.active.value?.id.orEmpty(),cheer.id,cheer.sender.displayName)
   analytics.record(com.plainstride.outbound.core.analytics.AnalyticsEvent("live_voice_cheer_played",mapOf(com.plainstride.outbound.core.analytics.AnalyticsProperty.CountBucket to "1")))
  }
 }
 fun acknowledge(){val current=mutableHeard.value?:return;viewModelScope.launch{val ok=coordinator.acknowledgeVoiceCheer(current.shareId,current.cheerId).isSuccess;analytics.record(com.plainstride.outbound.core.analytics.AnalyticsEvent("live_voice_cheer_acknowledged",mapOf(com.plainstride.outbound.core.analytics.AnalyticsProperty.Result to if(ok)"success" else "failure")));if(ok&&mutableHeard.value==current)mutableHeard.value=null}}
 fun dismiss(){mutableHeard.value=null}
}
@Composable fun RecordingSafetyEffect(snapshot:RecordingSnapshot,viewModel:RecordingSafetyViewModel=hiltViewModel()){
 val coordinator=viewModel.coordinator;val prior=remember{mutableStateOf<RecordingStatus?>(null)};val heard=viewModel.heard
 LaunchedEffect(snapshot.status,snapshot.sessionId){val previous=prior.value;prior.value=snapshot.status;when(snapshot.status){RecordingStatus.ACTIVE->coordinator.recordingStarted(snapshot.sessionId);RecordingStatus.AWAITING_SAVE->coordinator.recordingEnded();RecordingStatus.IDLE->if(previous!=null&&previous!=RecordingStatus.IDLE)coordinator.recordingEnded() else Unit;else->Unit};while(snapshot.status==RecordingStatus.ACTIVE){viewModel.receivePendingCheer();delay(4_000)}}
 LaunchedEffect(snapshot.latestLocation?.capturedAtEpochMilliseconds){val p=snapshot.latestLocation?:return@LaunchedEffect;if(snapshot.status==RecordingStatus.ACTIVE)coordinator.updateRecording(LiveLocation(Instant.ofEpochMilli(p.capturedAtEpochMilliseconds).toString(),p.latitude,p.longitude,p.altitudeMeters,p.horizontalAccuracyMeters,snapshot.elapsedSeconds.toInt(),snapshot.distanceMeters),snapshot.currentPaceSecondsPerKilometer)}
 if(snapshot.status==RecordingStatus.ACTIVE&&heard!=null)Box(Modifier.fillMaxSize().padding(horizontal=16.dp, vertical=54.dp),contentAlignment=Alignment.TopCenter){Surface(color=MaterialTheme.colorScheme.surface,shape=RoundedCornerShape(18.dp),shadowElevation=8.dp,modifier=Modifier.fillMaxWidth()){Row(Modifier.padding(12.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(6.dp)){Text(stringResource(R.string.cheer_runner_heard_from,heard.senderName),Modifier.weight(1f),style=MaterialTheme.typography.bodyMedium);TextButton(onClick=viewModel::acknowledge){Text(stringResource(R.string.cheer_runner_acknowledge))};TextButton(onClick=viewModel::dismiss){Text(stringResource(R.string.cheer_runner_dismiss))}}}}
}
