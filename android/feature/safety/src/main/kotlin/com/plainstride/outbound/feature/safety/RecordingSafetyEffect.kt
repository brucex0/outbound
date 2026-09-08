package com.plainstride.outbound.feature.safety

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import java.time.Instant
import com.plainstride.outbound.feature.recording.RecordingSnapshot
import com.plainstride.outbound.feature.recording.RecordingStatus
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf

@HiltViewModel class RecordingSafetyViewModel @Inject constructor(val coordinator:LiveShareCoordinator):ViewModel()
@Composable fun RecordingSafetyEffect(snapshot:RecordingSnapshot,viewModel:RecordingSafetyViewModel=hiltViewModel()){val coordinator=viewModel.coordinator;val prior=remember{mutableStateOf<RecordingStatus?>(null)}
 LaunchedEffect(snapshot.status,snapshot.sessionId){val previous=prior.value;prior.value=snapshot.status;when(snapshot.status){RecordingStatus.ACTIVE->coordinator.recordingStarted(snapshot.sessionId);RecordingStatus.AWAITING_SAVE->coordinator.recordingEnded();RecordingStatus.IDLE->if(previous!=null&&previous!=RecordingStatus.IDLE)coordinator.recordingEnded() else Unit;else->Unit}}
 LaunchedEffect(snapshot.latestLocation?.capturedAtEpochMilliseconds){val p=snapshot.latestLocation?:return@LaunchedEffect;if(snapshot.status==RecordingStatus.ACTIVE)coordinator.updateRecording(LiveLocation(Instant.ofEpochMilli(p.capturedAtEpochMilliseconds).toString(),p.latitude,p.longitude,p.altitudeMeters,p.horizontalAccuracyMeters,snapshot.elapsedSeconds.toInt(),snapshot.distanceMeters),snapshot.currentPaceSecondsPerKilometer)}
}
