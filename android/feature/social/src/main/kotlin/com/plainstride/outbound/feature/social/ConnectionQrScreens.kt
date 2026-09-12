package com.plainstride.outbound.feature.social

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.Error
import androidx.compose.material.icons.outlined.QrCode
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.EncodeHintType
import com.google.zxing.MultiFormatWriter
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.common.HybridBinarizer
import java.util.concurrent.Executors
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine

@Composable
fun PersonalConnectionQrRoute(
    onClose: () -> Unit,
    viewModel: SocialViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    LaunchedEffect(viewModel) { viewModel.openConnectionQr(entrySource = "me_profile_card") }
    ConnectionQrScreen(state) {
        viewModel.closeConnectionQr()
        onClose()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ConnectionQrScreen(
    state: SocialUiState,
    onClose: () -> Unit,
) = Dialog(
    onDismissRequest = onClose,
    properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
) {
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column {
            TopAppBar(
                title = { Text(stringResource(R.string.social_my_qr_code)) },
                navigationIcon = {
                    IconButton(onClose) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.social_close))
                    }
                },
            )
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                state.connectionQr?.owner?.let { owner ->
                    Card(
                        Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(18.dp),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                    ) {
                        Column(
                            Modifier.fillMaxWidth().padding(18.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            SocialAvatar(owner, 56.dp)
                            Text(owner.displayName, style = MaterialTheme.typography.titleMedium)
                            owner.username?.takeIf(String::isNotBlank)?.let {
                                Text("@$it", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }

                Card(
                    Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(18.dp),
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
                ) {
                    Box(
                        Modifier.fillMaxWidth().heightIn(min = 344.dp).padding(24.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        when {
                            state.connectionQr != null -> {
                                val bitmap = remember(state.connectionQr.link.url) { qrBitmap(state.connectionQr.link.url) }
                                if (bitmap != null) {
                                    Column(
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                        verticalArrangement = Arrangement.spacedBy(14.dp),
                                    ) {
                                        Image(
                                            bitmap.asImageBitmap(),
                                            stringResource(R.string.social_my_plainstride_qr_code),
                                            Modifier.size(260.dp).background(Color.White).padding(4.dp),
                                        )
                                        Text(
                                            stringResource(R.string.social_scan_this_qr_code),
                                            style = MaterialTheme.typography.bodyMedium,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                } else {
                                    QrUnavailable()
                                }
                            }
                            state.connectionQrLoading -> CircularProgressIndicator()
                            state.connectionQrFailed -> QrUnavailable()
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun QrUnavailable() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Outlined.QrCode, null, Modifier.size(42.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(stringResource(R.string.social_qr_code_unavailable), style = MaterialTheme.typography.titleMedium)
        Text(
            stringResource(R.string.social_qr_load_failure),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private enum class CameraState { Requesting, Ready, Denied, Unavailable }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ConnectionQrScannerScreen(
    isProcessing: Boolean,
    serverMessage: String?,
    onOpened: () -> Unit,
    onPayload: (String) -> Unit,
    onClose: () -> Unit,
) = Dialog(
    onDismissRequest = onClose,
    properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
) {
    val context = LocalContext.current
    val invalidCodeMessage = stringResource(R.string.social_not_connection_code)
    var cameraState by remember { mutableStateOf(CameraState.Requesting) }
    var scannerMessage by remember { mutableStateOf<String?>(null) }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        cameraState = if (granted) CameraState.Ready else CameraState.Denied
    }

    LaunchedEffect(Unit) {
        onOpened()
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            cameraState = CameraState.Ready
        } else {
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }
    LaunchedEffect(scannerMessage) {
        if (scannerMessage == null) return@LaunchedEffect
        delay(2_000)
        scannerMessage = null
    }

    Surface(Modifier.fillMaxSize(), color = Color.Black) {
        Column {
            TopAppBar(
                title = { Text(stringResource(R.string.social_scan_qr_code)) },
                navigationIcon = {
                    IconButton(onClose) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.social_close))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = Color.Black.copy(alpha = .72f),
                    titleContentColor = Color.White,
                    navigationIconContentColor = Color.White,
                ),
            )
            when (cameraState) {
                CameraState.Requesting -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = Color.White)
                }
                CameraState.Ready -> Box(Modifier.fillMaxSize()) {
                    ConnectionCodeCamera(
                        enabled = !isProcessing,
                        onPayload = { payload ->
                            if (connectionCodeFromPayload(payload) == null) {
                                scannerMessage = invalidCodeMessage
                            } else {
                                onPayload(payload)
                            }
                        },
                        onUnavailable = { cameraState = CameraState.Unavailable },
                    )
                    Column(
                        Modifier.fillMaxSize().navigationBarsPadding().padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        ScannerPill(stringResource(R.string.social_scan_friend_qr_code))
                        Spacer(Modifier.weight(1f))
                        when {
                            isProcessing -> ScannerPill(stringResource(R.string.social_checking_qr_code), loading = true)
                            serverMessage != null -> ScannerPill(serverMessage, error = true)
                            scannerMessage != null -> ScannerPill(scannerMessage.orEmpty(), error = true)
                        }
                    }
                }
                CameraState.Denied -> CameraUnavailable(
                    title = stringResource(R.string.social_camera_access_needed),
                    description = stringResource(R.string.social_camera_access_description),
                    onSettings = { context.openAppSettings() },
                )
                CameraState.Unavailable -> CameraUnavailable(
                    title = stringResource(R.string.social_scanner_unavailable),
                    description = stringResource(R.string.social_scanner_unavailable_description),
                )
            }
        }
    }
}

@Composable
private fun ScannerPill(message: String, loading: Boolean = false, error: Boolean = false) {
    Surface(color = Color.Black.copy(alpha = .70f), shape = RoundedCornerShape(28.dp)) {
        Row(
            Modifier.padding(horizontal = 18.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (loading) CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
            if (error) Icon(Icons.Outlined.Error, null, tint = Color.White)
            Text(message, color = Color.White, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun CameraUnavailable(title: String, description: String, onSettings: (() -> Unit)? = null) {
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(Icons.Outlined.CameraAlt, null, Modifier.size(48.dp), tint = Color.White)
        Spacer(Modifier.height(14.dp))
        Text(title, color = Color.White, style = MaterialTheme.typography.titleLarge)
        Spacer(Modifier.height(8.dp))
        Text(
            description,
            color = Color.White.copy(alpha = .75f),
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
        )
        onSettings?.let {
            Spacer(Modifier.height(20.dp))
            Button(it) { Text(stringResource(R.string.social_open_settings)) }
        }
    }
}

@Composable
private fun ConnectionCodeCamera(
    enabled: Boolean,
    onPayload: (String) -> Unit,
    onUnavailable: () -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val currentEnabled by rememberUpdatedState(enabled)
    val currentPayload by rememberUpdatedState(onPayload)
    val executor = remember { Executors.newSingleThreadExecutor() }
    val binding = remember { CameraBinding() }
    var previewView by remember { mutableStateOf<PreviewView?>(null) }
    var lastPayload by remember { mutableStateOf<String?>(null) }
    var lastDeliveryAt by remember { mutableLongStateOf(0L) }

    DisposableEffect(Unit) {
        onDispose {
            val useCases = listOfNotNull(binding.preview, binding.analysis).toTypedArray()
            if (useCases.isNotEmpty()) binding.provider?.unbind(*useCases)
            executor.shutdown()
        }
    }
    LaunchedEffect(previewView, lifecycleOwner) {
        val view = previewView ?: return@LaunchedEffect
        val provider = try {
            context.awaitCameraProvider()
        } catch (error: CancellationException) {
            // Compose restarts this effect while the dialog's AndroidView and lifecycle owner
            // settle. Cancellation is normal lifecycle control, not a camera failure.
            throw error
        } catch (error: Throwable) {
            logCameraFailure("provider", error)
            onUnavailable()
            return@LaunchedEffect
        }
        val cameraSelector = runCatching {
            when {
                provider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA) -> CameraSelector.DEFAULT_BACK_CAMERA
                provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) -> CameraSelector.DEFAULT_FRONT_CAMERA
                else -> error("No camera available")
            }
        }.getOrElse { error ->
            logCameraFailure("selection", error)
            onUnavailable()
            return@LaunchedEffect
        }
        val preview = Preview.Builder().build().also { it.surfaceProvider = view.surfaceProvider }
        val analysis = ImageAnalysis.Builder()
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
        analysis.setAnalyzer(executor) { image ->
            try {
                if (!currentEnabled) return@setAnalyzer
                val payload = image.decodeQrCode() ?: return@setAnalyzer
                val now = System.currentTimeMillis()
                if (payload == lastPayload && now - lastDeliveryAt < 2_500) return@setAnalyzer
                lastPayload = payload
                lastDeliveryAt = now
                ContextCompat.getMainExecutor(context).execute { currentPayload(payload) }
            } finally {
                image.close()
            }
        }
        runCatching {
            // CameraX's process provider is shared by the recording and Social features. Clear any
            // stale use cases before starting the scanner so a previous preview cannot exhaust the
            // device's supported stream combination.
            provider.unbindAll()
            provider.bindToLifecycle(lifecycleOwner, cameraSelector, preview, analysis)
        }.onSuccess {
            binding.provider = provider
            binding.preview = preview
            binding.analysis = analysis
        }.onFailure { error ->
            analysis.clearAnalyzer()
            logCameraFailure("binding", error)
            onUnavailable()
        }
    }

    AndroidView(
        factory = { PreviewView(it).also { view -> view.scaleType = PreviewView.ScaleType.FILL_CENTER; previewView = view } },
        modifier = Modifier.fillMaxSize(),
    )
}

private fun ImageProxy.decodeQrCode(): String? {
    val plane = planes.firstOrNull() ?: return null
    val width = width
    val height = height
    val bytes = ByteArray(width * height)
    val buffer = plane.buffer
    val rowStride = plane.rowStride
    val pixelStride = plane.pixelStride
    for (row in 0 until height) {
        val rowStart = row * rowStride
        for (column in 0 until width) {
            bytes[row * width + column] = buffer.get(rowStart + column * pixelStride)
        }
    }
    val source = PlanarYUVLuminanceSource(bytes, width, height, 0, 0, width, height, false)
    return runCatching { com.google.zxing.qrcode.QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source))).text }.getOrNull()
}

internal fun connectionCodeFromPayload(payload: String): String? {
    val uri = runCatching { Uri.parse(payload) }.getOrNull() ?: return null
    if (uri.scheme != "https" || uri.host != "run.plainstride.com") return null
    val segments = uri.pathSegments
    if (segments.size != 2 || segments[0] != "connect") return null
    return segments[1].takeIf { CONNECTION_CODE.matches(it) }
}

private fun qrBitmap(payload: String): android.graphics.Bitmap? = runCatching {
    val size = 640
    val matrix = MultiFormatWriter().encode(
        payload,
        BarcodeFormat.QR_CODE,
        size,
        size,
        mapOf(EncodeHintType.MARGIN to 2),
    )
    android.graphics.Bitmap.createBitmap(size, size, android.graphics.Bitmap.Config.ARGB_8888).also { image ->
        for (y in 0 until size) for (x in 0 until size) {
            image.setPixel(x, y, if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
        }
    }
}.getOrNull()

private fun Context.openAppSettings() {
    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
}

private suspend fun Context.awaitCameraProvider(): ProcessCameraProvider = suspendCancellableCoroutine { continuation ->
    val future = ProcessCameraProvider.getInstance(this)
    continuation.invokeOnCancellation { future.cancel(false) }
    future.addListener(
        {
            if (continuation.isActive) {
                continuation.resumeWith(runCatching { future.get() })
            }
        },
        ContextCompat.getMainExecutor(this),
    )
}

private fun logCameraFailure(stage: String, error: Throwable) {
    Log.w(CAMERA_LOG_TAG, "Camera $stage failed: ${error.javaClass.simpleName}")
}

private class CameraBinding(
    var provider: ProcessCameraProvider? = null,
    var preview: Preview? = null,
    var analysis: ImageAnalysis? = null,
)

private val CONNECTION_CODE = Regex("[A-Za-z0-9_-]{8,64}")
private const val CAMERA_LOG_TAG = "PlainstrideQrScanner"
