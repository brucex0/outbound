package com.plainstride.outbound.feature.recording

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.ExperimentalCoroutinesApi

/** Lifecycle-neutral UI gateway; a ViewModel can connect/disconnect without owning recording. */
@OptIn(ExperimentalCoroutinesApi::class)
class RecordingSessionClient(context: Context) : AutoCloseable {
    private val appContext = context.applicationContext
    private val coordinator = MutableStateFlow<RecordingCoordinator?>(null)
    private var bound = false
    private var pendingRecovery: PendingRecovery? = null

    val snapshots: Flow<RecordingSnapshot> = coordinator.filterNotNull().flatMapLatest { it.snapshot }
    val events: Flow<RecordingEvent> = coordinator.flatMapLatest { it?.events ?: emptyFlow() }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            lastBinder = service as? RecordingService.LocalBinder
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            lastBinder = null
        }
    }

    fun connect(): Boolean {
        if (bound) return true
        bound = appContext.bindService(
            Intent(appContext, RecordingService::class.java),
            connection,
            Context.BIND_AUTO_CREATE,
        )
        return bound
    }

    fun updatePermission(state: LocationPermissionState) {
        // Permission state stays outside the service and is pushed in after each UI permission result.
        lastBinder?.updatePermission(state)
    }

    fun start(
        accountId: String,
        activityKind: ActivityKind,
        permission: LocationPermissionState,
        commandId: String,
    ) = RecordingService.start(appContext, accountId, activityKind, permission, commandId)

    fun recover(
        accountId: String,
        permission: LocationPermissionState,
        commandId: String,
    ) {
        pendingRecovery = PendingRecovery(accountId, permission, commandId)
        deliverPendingRecovery()
    }

    fun pause(commandId: String) = RecordingService.pause(appContext, commandId)
    fun resume(commandId: String) = RecordingService.resume(appContext, commandId)
    fun finish(commandId: String) = RecordingService.finish(appContext, commandId)
    fun discard(commandId: String) = RecordingService.discard(appContext, commandId)

    fun markSaved(commandId: String) = RecordingService.markSaved(appContext, commandId)

    override fun close() {
        if (bound) appContext.unbindService(connection)
        bound = false
        coordinator.value = null
        lastBinder = null
    }

    private var lastBinder: RecordingService.LocalBinder? = null
        set(value) {
            field = value
            coordinator.value = value?.service()?.coordinator
            deliverPendingRecovery()
        }

    private fun deliverPendingRecovery() {
        val binder = lastBinder ?: return
        val pending = pendingRecovery ?: return
        binder.updatePermission(pending.permission)
        binder.recover(pending.accountId, pending.commandId)
        pendingRecovery = null
    }

    private data class PendingRecovery(
        val accountId: String,
        val permission: LocationPermissionState,
        val commandId: String,
    )
}
