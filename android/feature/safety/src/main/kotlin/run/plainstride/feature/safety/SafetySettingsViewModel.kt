package run.plainstride.feature.safety

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.StateFlow

@HiltViewModel class SafetySettingsViewModel @Inject constructor(private val contacts:DeviceTrustedContactStore,private val liveShare:LiveShareCoordinator):ViewModel(){
 private val mutableContacts=MutableStateFlow<List<TrustedContact>>(emptyList());val trustedContacts=mutableContacts.asStateFlow()
 val activeShare=liveShare.active
 val groupRun=liveShare.group
 init{reload()}
 fun add(contact:PickedContact)=viewModelScope.launch{contacts.savePicked(contact,mutableContacts.value.isEmpty());reload()}
 fun remove(contact:TrustedContact)=viewModelScope.launch{contacts.remove(contact.id);reload()}
 fun arm(){val targets=mutableContacts.value.map{DeliveryTarget(it.channel,it.displayName,it.address)};if(targets.isNotEmpty())liveShare.arm(CreateLiveShareRequest(recipientLabel=targets.first().label,deliveryTargets=targets))}
 fun createGroup()=viewModelScope.launch{liveShare.createGroupRun(CreateGroupRunRequest())}
 fun joinGroup(invite:String)=viewModelScope.launch{liveShare.joinGroupRun(invite)}
 fun openGroup(id:String)=viewModelScope.launch{liveShare.groupRun(id)}
 fun openLiveShare(id:String)=viewModelScope.launch{liveShare.liveShare(id)}
 fun leaveGroup()=viewModelScope.launch{liveShare.group.value?.let{liveShare.leaveGroupRun(it.id,false)}}
 private fun reload()=viewModelScope.launch{mutableContacts.value=contacts.contacts()}
}
