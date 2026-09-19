package com.plainstride.outbound.feature.recording

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.core.content.getSystemService
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.database.PlainstrideDatabase
import com.plainstride.outbound.core.model.activity.ActivityCompanionType
import java.util.UUID
import javax.inject.Inject

/** Canonical process owner for recording state, location collection, and recovery journal writes. */
@AndroidEntryPoint
class RecordingService : Service() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val permissionState = MutableStateFlow(LocationPermissionState.NOT_REQUESTED)
    private val binder = LocalBinder()
    lateinit var coordinator: RecordingCoordinator
        private set
    @Inject lateinit var database: PlainstrideDatabase
    @Inject lateinit var analytics: ProductAnalytics

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val source = FusedRecordingLocationSource(applicationContext, permissionState, serviceScope)
        coordinator = RecordingCoordinator(
            journal = database.activeSessionJournalDao(),
            locationSource = source,
            permissionState = permissionState,
            scope = serviceScope,
            analytics = analytics,
        )
        serviceScope.launch {
            coordinator.snapshot.collect { snapshot ->
                if (snapshot.status != RecordingStatus.IDLE) {
                    getSystemService<NotificationManager>()?.notify(NOTIFICATION_ID, notification(snapshot.status))
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: return START_NOT_STICKY
        // Android requires foreground promotion before asynchronous command handling.
        startAsForeground(RecordingStatus.ACTIVE)
        val commandId = intent.getStringExtra(EXTRA_COMMAND_ID) ?: UUID.randomUUID().toString()
        permissionState.value = intent.permissionStateExtra() ?: permissionState.value
        serviceScope.launch {
            when (action) {
                ACTION_START -> coordinator.start(
                    commandId = commandId,
                    accountId = intent.requireStringExtra(EXTRA_ACCOUNT_ID),
                    activityKind = intent.activityKindExtra(),
                    sessionId = intent.getStringExtra(EXTRA_SESSION_ID) ?: UUID.randomUUID().toString(),
                    companionType = intent.getStringExtra(EXTRA_COMPANION_TYPE)?.let { raw ->
                        runCatching { ActivityCompanionType.valueOf(raw) }.getOrNull()
                    },
                )
                ACTION_RECOVER -> coordinator.recover(intent.requireStringExtra(EXTRA_ACCOUNT_ID), commandId)
                ACTION_PAUSE -> coordinator.pause(commandId)
                ACTION_RESUME -> coordinator.resume(commandId)
                ACTION_FINISH -> coordinator.finish(commandId)
                ACTION_SAVED -> {
                    coordinator.markSaved(commandId)
                    if (coordinator.snapshot.value.status == RecordingStatus.IDLE) {
                        stopForeground(STOP_FOREGROUND_REMOVE)
                        stopSelf()
                    }
                }
                ACTION_DISCARD -> {
                    coordinator.discard(commandId)
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
            // A non-start command may be redelivered after process death before the UI
            // supplies its account-scoped RECOVER command. Do not leave a phantom FGS;
            // the Room journal remains intact for explicit recovery.
            if (coordinator.snapshot.value.status == RecordingStatus.IDLE &&
                action != ACTION_START && action != ACTION_RECOVER
            ) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun startAsForeground(status: RecordingStatus) {
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification(status),
            if (Build.VERSION.SDK_INT >= 29) android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else 0,
        )
    }

    private fun notification(status: RecordingStatus): Notification {
        val isPaused = status == RecordingStatus.PAUSED || status == RecordingStatus.AWAITING_SAVE
        val toggleAction = if (isPaused) ACTION_RESUME else ACTION_PAUSE
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_recording_notification)
            .setContentTitle(getString(R.string.recording_notification_title))
            .setContentText(getString(if (isPaused) R.string.recording_notification_paused else R.string.recording_notification_active))
            .setOngoing(status != RecordingStatus.AWAITING_SAVE)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_WORKOUT)
        if (status != RecordingStatus.AWAITING_SAVE) {
            builder.addAction(
                0,
                getString(if (isPaused) R.string.recording_notification_resume_action else R.string.recording_notification_pause_action),
                commandPendingIntent(toggleAction),
            )
        }
        return builder.build()
    }

    private fun commandPendingIntent(action: String): PendingIntent {
        val intent = Intent(this, RecordingService::class.java)
            .setAction(action)
            .putExtra(EXTRA_COMMAND_ID, UUID.randomUUID().toString())
        return PendingIntent.getService(
            this,
            action.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.recording_notification_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply { description = getString(R.string.recording_notification_channel_description) }
        getSystemService<NotificationManager>()?.createNotificationChannel(channel)
    }

    inner class LocalBinder : Binder() {
        fun service(): RecordingService = this@RecordingService
        fun updatePermission(state: LocationPermissionState) {
            permissionState.value = state
        }
        fun recover(accountId: String, commandId: String) {
            serviceScope.launch { coordinator.recover(accountId, commandId) }
        }
    }

    companion object {
        private const val CHANNEL_ID = "activity_recording"
        private const val NOTIFICATION_ID = 4_101
        private const val EXTRA_COMMAND_ID = "recording.command_id"
        private const val EXTRA_ACCOUNT_ID = "recording.account_id"
        private const val EXTRA_SESSION_ID = "recording.session_id"
        private const val EXTRA_ACTIVITY_KIND = "recording.activity_kind"
        private const val EXTRA_PERMISSION = "recording.permission"
        private const val EXTRA_COMPANION_TYPE = "recording.companion_type"
        private const val ACTION_START = "com.plainstride.outbound.recording.START"
        private const val ACTION_RECOVER = "com.plainstride.outbound.recording.RECOVER"
        private const val ACTION_PAUSE = "com.plainstride.outbound.recording.PAUSE"
        private const val ACTION_RESUME = "com.plainstride.outbound.recording.RESUME"
        private const val ACTION_FINISH = "com.plainstride.outbound.recording.FINISH"
        private const val ACTION_SAVED = "com.plainstride.outbound.recording.SAVED"
        private const val ACTION_DISCARD = "com.plainstride.outbound.recording.DISCARD"

        fun start(
            context: Context,
            accountId: String,
            activityKind: ActivityKind,
            permission: LocationPermissionState,
            commandId: String = UUID.randomUUID().toString(),
            sessionId: String = UUID.randomUUID().toString(),
            companionType: ActivityCompanionType? = null,
        ) = dispatch(context, ACTION_START, commandId) {
            require(permission == LocationPermissionState.PRECISE || permission == LocationPermissionState.APPROXIMATE) {
                "Location permission must be granted before starting an outdoor recording."
            }
            putExtra(EXTRA_ACCOUNT_ID, accountId)
            putExtra(EXTRA_ACTIVITY_KIND, activityKind.name)
            putExtra(EXTRA_PERMISSION, permission.name)
            putExtra(EXTRA_SESSION_ID, sessionId)
            companionType?.let { putExtra(EXTRA_COMPANION_TYPE, it.name) }
        }

        fun recover(
            context: Context,
            accountId: String,
            permission: LocationPermissionState,
            commandId: String = UUID.randomUUID().toString(),
        ) = dispatch(context, ACTION_RECOVER, commandId) {
            putExtra(EXTRA_ACCOUNT_ID, accountId)
            putExtra(EXTRA_PERMISSION, permission.name)
        }

        fun pause(context: Context, commandId: String = UUID.randomUUID().toString()) =
            dispatch(context, ACTION_PAUSE, commandId)

        fun resume(context: Context, commandId: String = UUID.randomUUID().toString()) =
            dispatch(context, ACTION_RESUME, commandId)

        fun finish(context: Context, commandId: String = UUID.randomUUID().toString()) =
            dispatch(context, ACTION_FINISH, commandId)

        fun markSaved(context: Context, commandId: String = UUID.randomUUID().toString()) =
            dispatch(context, ACTION_SAVED, commandId)

        fun discard(context: Context, commandId: String = UUID.randomUUID().toString()) =
            dispatch(context, ACTION_DISCARD, commandId)

        private fun dispatch(
            context: Context,
            action: String,
            commandId: String,
            extras: Intent.() -> Unit = {},
        ) {
            val intent = Intent(context, RecordingService::class.java)
                .setAction(action)
                .putExtra(EXTRA_COMMAND_ID, commandId)
                .apply(extras)
            ContextCompat.startForegroundService(context, intent)
        }
    }
}

private fun Intent.requireStringExtra(key: String): String =
    requireNotNull(getStringExtra(key)) { "Missing required recording command extra: $key" }

private fun Intent.activityKindExtra(): ActivityKind =
    getStringExtra("recording.activity_kind")?.let(ActivityKind::valueOf) ?: ActivityKind.RUNNING

private fun Intent.permissionStateExtra(): LocationPermissionState? =
    getStringExtra("recording.permission")?.let(LocationPermissionState::valueOf)
