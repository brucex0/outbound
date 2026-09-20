package com.plainstride.outbound.feature.safety

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.StateFlow
import com.plainstride.outbound.feature.social.SocialPerson

@HiltViewModel class SafetySettingsViewModel @Inject constructor(
 private val contacts:TrustedContactStore,
 private val liveShare:LiveShareCoordinator,
 private val analytics:com.plainstride.outbound.core.analytics.ProductAnalytics,
):ViewModel(){
 private val mutableContacts=MutableStateFlow<List<TrustedContact>>(emptyList());val trustedContacts=mutableContacts.asStateFlow()
 val activeShare=liveShare.active
 val groupRun=liveShare.group
 private val mutableFollower=MutableStateFlow<InvitedLiveShare?>(null);val follower=mutableFollower.asStateFlow()
 private val mutableFollowerLoading=MutableStateFlow(false);val followerLoading=mutableFollowerLoading.asStateFlow()
 private val mutableFollowerMessage=MutableStateFlow<String?>(null);val followerMessage=mutableFollowerMessage.asStateFlow()
 private var connectionNames:Map<String,String> = emptyMap()

 init{reload()}

 /** Server pulls (screen open / account change) flow through here so the list survives reinstall. */
 fun onAccountActivated(accountId:String?)=viewModelScope.launch{
  contacts.migrateToServerBackedContacts()
  if(accountId==null)return@launch
  contacts.pull(accountId)
  reload()
 }

 /** Fresh connection roster so cached rows can be re-labelled after a reinstall. */
 fun onConnectionsUpdated(people:List<SocialPerson>){connectionNames=people.associate{it.id to it.displayName};reload()}

 fun add(contact:TrustedContact)=viewModelScope.launch{
  val makeDefault=mutableContacts.value.isEmpty()
  contacts.save(if(makeDefault)contact.copy(isDefault=true)else contact)
  contacts.push()
  reload()
 }
 fun remove(contact:TrustedContact)=viewModelScope.launch{contacts.remove(contact.id);contacts.push();reload()}
 fun arm(){val ids=mutableContacts.value.map{it.id};if(ids.isNotEmpty())liveShare.arm(CreateLiveShareRequest(recipientUserIds=ids))}
 fun createGroup()=viewModelScope.launch{liveShare.createGroupRun(CreateGroupRunRequest())}
 fun joinGroup(invite:String)=viewModelScope.launch{liveShare.joinGroupRun(invite)}
 fun openGroup(id:String)=viewModelScope.launch{liveShare.groupRun(id)}
 fun openLiveShare(id:String)=viewModelScope.launch{analytics.record(com.plainstride.outbound.core.analytics.AnalyticsEvent("live_cheer_follower_opened",mapOf(com.plainstride.outbound.core.analytics.AnalyticsProperty.Source to "notification")));while(true){mutableFollowerLoading.value=mutableFollower.value==null;liveShare.invitedShare(id).onSuccess{mutableFollower.value=it}.onFailure{mutableFollowerMessage.value="load_failed"};mutableFollowerLoading.value=false;if(mutableFollower.value?.status!="active")break;kotlinx.coroutines.delay(5_000)}}
 fun sendVoiceCheer(audioBase64:String,durationMs:Int)=viewModelScope.launch{val id=mutableFollower.value?.id?:return@launch;mutableFollowerMessage.value=null;liveShare.sendVoiceCheer(id,audioBase64,durationMs).onSuccess{mutableFollowerMessage.value="sent"}.onFailure{mutableFollowerMessage.value="send_failed"}}
 fun leaveGroup()=viewModelScope.launch{liveShare.group.value?.let{liveShare.leaveGroupRun(it.id,false)}}
 private fun reload()=viewModelScope.launch{mutableContacts.value=contacts.contacts().map{contact->connectionNames[contact.id]?.takeIf(String::isNotBlank)?.let{contact.copy(displayName=it)}?:contact}}
}
