package run.plainstride.feature.recording

import android.content.Context
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import java.io.File
import java.util.UUID

@Composable
internal fun InAppCamera(
    onCaptured: (String) -> Unit,
    onUnavailable: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val capture = remember { ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build() }
    var previewView by remember { mutableStateOf<PreviewView?>(null) }
    LaunchedEffect(previewView, owner) {
        val view = previewView ?: return@LaunchedEffect
        val provider = runCatching { ProcessCameraProvider.getInstance(context).get() }.getOrElse { onUnavailable(); return@LaunchedEffect }
        runCatching {
            provider.unbindAll()
            val preview = Preview.Builder().build().also { it.surfaceProvider = view.surfaceProvider }
            provider.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, preview, capture)
        }.onFailure { onUnavailable() }
    }
    Box(modifier) {
        AndroidView(factory = { PreviewView(it).also { view -> view.scaleType = PreviewView.ScaleType.FILL_CENTER; previewView = view } }, modifier = Modifier.fillMaxSize())
        FilledIconButton(onClick = { capture(context, capture, onCaptured, onUnavailable) }, modifier = Modifier.align(Alignment.CenterEnd).padding(24.dp).size(64.dp)) {
            Icon(Icons.Default.CameraAlt, stringResource(R.string.recording_capture_photo))
        }
    }
}

private fun capture(context: Context, capture: ImageCapture, success: (String) -> Unit, failure: () -> Unit) {
    val directory = File(context.filesDir, "activity_photos").apply { mkdirs() }
    val file = File(directory, "${UUID.randomUUID()}.jpg")
    capture.takePicture(ImageCapture.OutputFileOptions.Builder(file).build(), ContextCompat.getMainExecutor(context), object : ImageCapture.OnImageSavedCallback {
        override fun onImageSaved(output: ImageCapture.OutputFileResults) = success(file.absolutePath)
        override fun onError(exception: ImageCaptureException) { file.delete(); failure() }
    })
}
