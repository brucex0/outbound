package com.plainstride.outbound.feature.recording

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import java.util.UUID

@HiltViewModel class ActiveRecordingViewModel @Inject constructor(@ApplicationContext context:Context):ViewModel(){
 private val client=RecordingSessionClient(context).apply{connect()}
 val active=client.snapshots.map{it.status==RecordingStatus.ACTIVE||it.status==RecordingStatus.PAUSED||it.status==RecordingStatus.AWAITING_SAVE}.stateIn(viewModelScope,SharingStarted.Eagerly,false)
 fun recover(accountId:String,permission:LocationPermissionState)=client.recover(accountId,permission,UUID.randomUUID().toString())
 override fun onCleared(){client.close();super.onCleared()}
}
