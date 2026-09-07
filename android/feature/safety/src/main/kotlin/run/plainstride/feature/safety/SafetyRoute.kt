package run.plainstride.feature.safety

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.ContactsContract
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle

/** Feature-owned Android integration for contact picking, permissions, and safe link sharing. */
@Composable
fun SafetyRoute(targetId: String? = null, viewModel: SafetySettingsViewModel = hiltViewModel()) {
    val context = LocalContext.current
    val contacts by viewModel.trustedContacts.collectAsStateWithLifecycle()
    val activeShare by viewModel.activeShare.collectAsStateWithLifecycle()
    val groupRun by viewModel.groupRun.collectAsStateWithLifecycle()
    androidx.compose.runtime.LaunchedEffect(targetId) { targetId?.takeIf(String::isNotBlank)?.let(viewModel::openGroup) }
    var permission by remember { mutableStateOf(notificationPermissionState(context)) }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        permission = notificationPermissionState(context)
    }
    val contactPicker = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        result.data?.data?.let { uri ->
            context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) viewModel.add(PickedContact(cursor.getString(0), cursor.getString(1)))
            }
        }
    }
    val share: (String) -> Unit = { url ->
        context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, url), null))
    }
    SafetySettingsScreen(
        contacts = contacts,
        permission = permission,
        onRequestPermission = { permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) },
        onOpenSettings = { context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:${context.packageName}"))) },
        onAdd = { contactPicker.launch(Intent(Intent.ACTION_PICK, ContactsContract.CommonDataKinds.Phone.CONTENT_URI)) },
        onRemove = viewModel::remove,
        onArm = viewModel::arm,
        activeShare = activeShare,
        groupRun = groupRun,
        onShare = share,
        onCreateGroup = viewModel::createGroup,
        onJoinGroup = viewModel::joinGroup,
        onLeaveGroup = viewModel::leaveGroup,
    )
}

private fun notificationPermissionState(context: android.content.Context): NotificationPermissionState =
    if (android.os.Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
        NotificationPermissionState.GRANTED
    } else {
        NotificationPermissionState.DENIED
    }
