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
import com.plainstride.outbound.core.designsystem.PlainstrideLiveRouteMap
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import java.io.File
import java.util.Locale

@Composable
fun LiveCheerFollowerScreen(
    session: InvitedLiveShare?,
    liveTrack: List<LiveRoutePoint>,
    loading: Boolean,
    message: String?,
    unitSystem: MeasurementUnitSystem,
    send: (String, Int) -> Unit,
) {
    val context = LocalContext.current
    val snackbar = remember { SnackbarHostState() }
    var recorder by remember { mutableStateOf<MediaRecorder?>(null) }
    var recordingFile by remember { mutableStateOf<File?>(null) }
    var startedAt by remember { mutableLongStateOf(0L) }
    var recording by remember { mutableStateOf(false) }
    var permissionMessage by remember { mutableStateOf<Int?>(null) }
    val startRecording = {
        val file = File.createTempFile("plainstride-cheer-", ".m4a", context.cacheDir)
        val value = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
        runCatching {
            value.setAudioSource(MediaRecorder.AudioSource.MIC)
            value.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            value.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            value.setAudioSamplingRate(22_050)
            value.setAudioEncodingBitRate(48_000)
            value.setOutputFile(file.absolutePath)
            value.prepare()
            value.start()
        }.onSuccess {
            recorder = value
            recordingFile = file
            startedAt = android.os.SystemClock.elapsedRealtime()
            recording = true
        }.onFailure {
            value.release()
            file.delete()
            recording = false
        }
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (!granted) permissionMessage = R.string.cheer_microphone_required
    }
    fun finish() {
        val value = recorder ?: return
        val duration = (android.os.SystemClock.elapsedRealtime() - startedAt).toInt().coerceIn(250, 15_000)
        val valid = runCatching { value.stop(); true }.getOrDefault(false)
        value.release()
        recorder = null
        recording = false
        recordingFile?.let { file ->
            if (valid) runCatching { Base64.encodeToString(file.readBytes(), Base64.NO_WRAP) }.getOrNull()?.let { send(it, duration) }
            file.delete()
        }
        recordingFile = null
    }
    val startRecordingLatest = rememberUpdatedState(startRecording)
    val finishRecordingLatest = rememberUpdatedState(::finish)
    DisposableEffect(Unit) {
        onDispose { runCatching { recorder?.stop() }; recorder?.release(); recordingFile?.delete() }
    }
    LaunchedEffect(recording) {
        if (recording) {
            kotlinx.coroutines.delay(15_000)
            if (recording) finish()
        }
    }
    LaunchedEffect(message) {
        message?.let { snackbar.showSnackbar(context.getString(when (it) {
            "sent" -> R.string.cheer_sent
            "send_failed" -> R.string.cheer_send_failed
            else -> R.string.cheer_load_failed
        })) }
    }
    LaunchedEffect(permissionMessage) {
        permissionMessage?.let { snackbar.showSnackbar(context.getString(it)); permissionMessage = null }
    }
    Scaffold(snackbarHost = { SnackbarHost(snackbar) }) { padding -> when {
        session == null && loading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
        session == null -> Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) { Text(stringResource(R.string.cheer_load_failed)) }
        else -> Column(
            Modifier.fillMaxSize().padding(padding).padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(stringResource(R.string.cheer_title, session.runner.displayName), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            val runnerPosition = session.lastLocation?.let { MapCoordinate(it.latitude, it.longitude) }
            PlainstrideLiveRouteMap(
                recordedRoute = liveTrack.map { MapCoordinate(it.latitude, it.longitude) },
                runnerLocation = runnerPosition,
                modifier = Modifier.fillMaxWidth().weight(1f),
                followRunner = true,
                rotateWithRunner = true,
                showRunnerMascot = true,
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                Metric(distance(session.distanceM, unitSystem), stringResource(R.string.cheer_distance))
                Metric(elapsedTime(session.elapsedSeconds), stringResource(R.string.cheer_time))
                Metric(pace(session, unitSystem), stringResource(if (session.status == "active") R.string.cheer_pace else R.string.cheer_average_pace))
                Metric(session.heartRate?.toString() ?: "—", stringResource(R.string.cheer_heart_rate))
            }
            Text(
                stringResource(if (session.status == "active") R.string.cheer_runner_moving else R.string.cheer_activity_ended, session.runner.displayName),
                fontWeight = FontWeight.SemiBold,
            )
            if (session.latestCheer != null) VoiceCheerDeliveryStatus(session.latestCheer)
            if (session.status == "active" && session.voiceCheerEnabled) {
                FilledIconButton(
                    onClick = {},
                    modifier = Modifier.size(80.dp).pointerInput(session.id) {
                        detectTapGestures(onPress = {
                            if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) startRecordingLatest.value()
                            else permission.launch(Manifest.permission.RECORD_AUDIO)
                            tryAwaitRelease()
                            finishRecordingLatest.value()
                        })
                    },
                    colors = IconButtonDefaults.filledIconButtonColors(containerColor = if (recording) Color(0xFFD32F2F) else MaterialTheme.colorScheme.primary),
                ) {
                    Icon(if (recording) Icons.Outlined.StopCircle else Icons.Outlined.Mic, stringResource(if (recording) R.string.cheer_release_to_send else R.string.cheer_hold_to_send), Modifier.size(44.dp))
                }
                Text(stringResource(if (recording) R.string.cheer_release_to_send else R.string.cheer_hold_to_send))
            } else if (session.status == "active") {
                Text(stringResource(R.string.cheer_voice_locked), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
            }
        }
    } }
}

@Composable
private fun VoiceCheerDeliveryStatus(receipt: VoiceCheerReceipt) {
    val (label, icon) = when {
        receipt.acknowledgedAt != null -> stringResource(R.string.cheer_status_acknowledged) to "❤️"
        receipt.playedAt != null -> stringResource(R.string.cheer_status_heard) to "✓"
        receipt.deliveredAt != null -> stringResource(R.string.cheer_status_delivered) to "✓"
        else -> stringResource(R.string.cheer_status_sent) to "✓"
    }
    AssistChip(onClick = {}, label = { Text("$icon $label") }, enabled = false)
}

@Composable
private fun Metric(value: String, label: String) = Column(horizontalAlignment = Alignment.CenterHorizontally) {
    Text(value, fontWeight = FontWeight.Bold)
    Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

private fun distance(meters: Double, unitSystem: MeasurementUnitSystem): String {
    val value = if (unitSystem == MeasurementUnitSystem.metric) meters / 1_000 else meters / 1_609.344
    val unit = if (unitSystem == MeasurementUnitSystem.metric) "km" else "mi"
    return String.format(Locale.getDefault(), "%.2f %s", value, unit)
}

private fun pace(session: InvitedLiveShare, unitSystem: MeasurementUnitSystem): String {
    val seconds = if (session.status == "active") session.currentPaceSecsPerKm
        else if (session.distanceM > 0) session.elapsedSeconds / (session.distanceM / 1_000) else null
    if (seconds == null || !seconds.isFinite()) return "—"
    val perUnit = if (unitSystem == MeasurementUnitSystem.metric) seconds else seconds * 1_609.344 / 1_000
    val minutes = perUnit.toInt().coerceAtLeast(0)
    val remainder = (perUnit.toInt() % 60).coerceAtLeast(0)
    val unit = if (unitSystem == MeasurementUnitSystem.metric) "km" else "mi"
    return String.format(Locale.getDefault(), "%d:%02d/%s", minutes, remainder, unit)
}

private fun elapsedTime(seconds: Int): String {
    val safe = seconds.coerceAtLeast(0)
    return if (safe >= 3_600) String.format(Locale.getDefault(), "%d:%02d:%02d", safe / 3_600, safe / 60 % 60, safe % 60)
    else String.format(Locale.getDefault(), "%d:%02d", safe / 60, safe % 60)
}
