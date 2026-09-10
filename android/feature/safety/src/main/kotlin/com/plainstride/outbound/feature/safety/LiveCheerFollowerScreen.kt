package com.plainstride.outbound.feature.safety

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.os.Build
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.StopCircle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.designsystem.MapCoordinate
import com.plainstride.outbound.core.designsystem.PlainstrideRouteMap
import java.io.File

@Composable
fun LiveCheerFollowerScreen(session:InvitedLiveShare?,loading:Boolean,message:String?,send:(String,Int)->Unit){
 val context=LocalContext.current
 val snackbar=remember{SnackbarHostState()}
 var recorder by remember{mutableStateOf<MediaRecorder?>(null)}
 var recordingFile by remember{mutableStateOf<File?>(null)}
 var startedAt by remember{mutableLongStateOf(0L)}
 var pendingStart by remember{mutableStateOf(false)}
 val startRecording={
  val file=File.createTempFile("plainstride-cheer-",".m4a",context.cacheDir)
  val value=if(Build.VERSION.SDK_INT>=31)MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
  runCatching{value.setAudioSource(MediaRecorder.AudioSource.MIC);value.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);value.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);value.setAudioSamplingRate(22_050);value.setAudioEncodingBitRate(48_000);value.setOutputFile(file.absolutePath);value.prepare();value.start()}.onSuccess{recorder=value;recordingFile=file;startedAt=android.os.SystemClock.elapsedRealtime()}.onFailure{value.release();file.delete()}
 }
 val permission=rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()){granted->if(granted&&pendingStart)startRecording();pendingStart=false}
 fun finish(){val value=recorder?:return;val duration=(android.os.SystemClock.elapsedRealtime()-startedAt).toInt().coerceIn(250,15_000);runCatching{value.stop()};value.release();recorder=null;recordingFile?.let{file->runCatching{Base64.encodeToString(file.readBytes(),Base64.NO_WRAP)}.getOrNull()?.let{send(it,duration)};file.delete()};recordingFile=null}
 DisposableEffect(Unit){onDispose{runCatching{recorder?.stop()};recorder?.release();recordingFile?.delete()}}
 LaunchedEffect(message){message?.let{snackbar.showSnackbar(context.getString(when(it){"sent"->R.string.cheer_sent;"send_failed"->R.string.cheer_send_failed;else->R.string.cheer_load_failed}))}}
 Scaffold(snackbarHost={SnackbarHost(snackbar)}){padding->when{
  session==null&&loading->Box(Modifier.fillMaxSize().padding(padding),contentAlignment=Alignment.Center){CircularProgressIndicator()}
  session==null->Box(Modifier.fillMaxSize().padding(24.dp),contentAlignment=Alignment.Center){Text(stringResource(R.string.cheer_load_failed))}
  else->Column(Modifier.fillMaxSize().padding(padding).padding(16.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(16.dp)){
   Text(stringResource(R.string.cheer_title,session.runner.displayName),style=MaterialTheme.typography.headlineSmall,fontWeight=FontWeight.Bold)
   session.routePreview.map{MapCoordinate(it.latitude,it.longitude)}.takeIf{it.size>1}?.let{PlainstrideRouteMap(it,Modifier.fillMaxWidth().weight(1f))}
   Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.SpaceEvenly){Metric("%.2f km".format(session.distanceM/1000),stringResource(R.string.cheer_distance));Metric(session.currentPaceSecsPerKm?.let{"%d:%02d/km".format(it.toInt()/60,it.toInt()%60)}?:"—",stringResource(R.string.cheer_pace));Metric(session.heartRate?.toString()?:"—",stringResource(R.string.cheer_heart_rate))}
   Text(stringResource(if(session.status=="active")R.string.cheer_runner_moving else R.string.cheer_activity_ended,session.runner.displayName),fontWeight=FontWeight.SemiBold)
   if(session.status=="active"){
    FilledIconButton(onClick={},modifier=Modifier.size(80.dp).pointerInput(recorder){detectTapGestures(onPress={
     if(context.checkSelfPermission(Manifest.permission.RECORD_AUDIO)==PackageManager.PERMISSION_GRANTED)startRecording() else{pendingStart=true;permission.launch(Manifest.permission.RECORD_AUDIO)}
     tryAwaitRelease();finish()
    })},colors=IconButtonDefaults.filledIconButtonColors(containerColor=if(recorder!=null)Color(0xFFD32F2F) else MaterialTheme.colorScheme.primary)){
     Icon(if(recorder!=null)Icons.Outlined.StopCircle else Icons.Outlined.Mic,stringResource(if(recorder!=null)R.string.cheer_release_to_send else R.string.cheer_hold_to_send),Modifier.size(44.dp))
    }
    Text(stringResource(if(recorder!=null)R.string.cheer_release_to_send else R.string.cheer_hold_to_send))
   }
  }
 }}
}

@Composable private fun Metric(value:String,label:String)=Column(horizontalAlignment=Alignment.CenterHorizontally){Text(value,fontWeight=FontWeight.Bold);Text(label,style=MaterialTheme.typography.labelSmall,color=MaterialTheme.colorScheme.onSurfaceVariant)}
