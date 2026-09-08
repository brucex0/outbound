package com.plainstride.outbound.feature.health

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.database.CyclePreferenceEntity
import com.plainstride.outbound.core.database.CycleWellbeingEntity
import com.plainstride.outbound.core.database.PlainstrideDatabase
import com.plainstride.outbound.core.network.AccessTokenProvider
import com.plainstride.outbound.core.network.ApiResult
import com.plainstride.outbound.core.network.CycleTrainingSignalRequest
import com.plainstride.outbound.core.network.CycleTrainingSignalResponse
import com.plainstride.outbound.core.network.PlanningApiService
import com.plainstride.outbound.core.network.apiCall

enum class CycleTrainingSignal(val wireValue:String) { NO_ADJUSTMENT("noAdjustment"), OFFER_FLEXIBLE_OPTION("offerFlexibleOption"), REDUCE_LOAD("reduceLoad"), RECOMMEND_REST("recommendRest") }
data class CycleWellbeingLog(val id:String,val recordedAt:Instant,val bleeding:Boolean,val energy:Int,val discomfort:Int)
data class CycleAwareState(val eligible:Boolean=false,val loaded:Boolean=false,val enabled:Boolean=false,val logs:List<CycleWellbeingLog> = emptyList(),val response:CycleTrainingSignalResponse?=null){
 val currentSignal:CycleTrainingSignal get(){val latest=logs.firstOrNull()?:return CycleTrainingSignal.NO_ADJUSTMENT;if(!enabled)return CycleTrainingSignal.NO_ADJUSTMENT;return when{latest.discomfort>=4||latest.energy==1->CycleTrainingSignal.RECOMMEND_REST;latest.discomfort>=3||latest.energy==2->CycleTrainingSignal.REDUCE_LOAD;latest.bleeding||latest.energy==3->CycleTrainingSignal.OFFER_FLEXIBLE_OPTION;else->CycleTrainingSignal.NO_ADJUSTMENT}}
}

class CycleAwareRepository @Inject constructor(private val database:PlainstrideDatabase,private val api:PlanningApiService,private val tokens:AccessTokenProvider,private val analytics:ProductAnalytics){
 suspend fun state(accountId:String):CycleAwareState{val token=tokens.validAccessToken();val profile=token?.let{apiCall{api.trainingProfile("Bearer $it")}};val eligible=(profile as? ApiResult.Success)?.value?.sexAtBirth?.lowercase()!="male";val dao=database.cycleWellbeingDao();val enabled=dao.preference(accountId)?.enabled==true&&eligible;return CycleAwareState(eligible,true,enabled,dao.logs(accountId).map{CycleWellbeingLog(it.logId,Instant.ofEpochMilli(it.recordedAtEpochMs),it.bleeding,it.energy,it.discomfort)})}
 suspend fun setEnabled(accountId:String,enabled:Boolean){database.cycleWellbeingDao().setPreference(CyclePreferenceEntity(accountId,enabled));analytics.record(AnalyticsEvent("cycle_guidance_preference_changed",mapOf(AnalyticsProperty.Enabled to enabled)))}
 suspend fun log(accountId:String,bleeding:Boolean,energy:Int,discomfort:Int,workoutId:String?):CycleTrainingSignalResponse?{require(energy in 1..5&&discomfort in 1..5);val now=Instant.now();database.cycleWellbeingDao().insert(CycleWellbeingEntity(accountId,UUID.randomUUID().toString(),now.toEpochMilli(),bleeding,energy,discomfort));val signal=signal(bleeding,energy,discomfort);val token=tokens.validAccessToken();val result=token?.let{apiCall{api.submitCycleSignal("Bearer $it",CycleTrainingSignalRequest(signal.wireValue,workoutId,LocalDate.now().toString(),"${LocalDate.now()}-${signal.wireValue}"))}};analytics.record(AnalyticsEvent("cycle_private_checkin_saved",mapOf(AnalyticsProperty.Result to if(result is ApiResult.Success)"signal_sent" else "local_only")));return (result as? ApiResult.Success)?.value}
 suspend fun request(accountId:String,workoutId:String):CycleTrainingSignalResponse?{val signal=state(accountId).currentSignal;val token=tokens.validAccessToken()?:return null;return when(val result=apiCall{api.submitCycleSignal("Bearer $token",CycleTrainingSignalRequest(signal.wireValue,workoutId,LocalDate.now().toString(),"${LocalDate.now()}-${signal.wireValue}-$workoutId"))}){is ApiResult.Success->result.value;is ApiResult.Failure->null}}
 suspend fun clear(accountId:String){database.cycleWellbeingDao().deleteLogs(accountId);database.cycleWellbeingDao().deletePreference(accountId);analytics.record(AnalyticsEvent("cycle_private_data_deleted"))}
 private fun signal(bleeding:Boolean,energy:Int,discomfort:Int)=when{discomfort>=4||energy==1->CycleTrainingSignal.RECOMMEND_REST;discomfort>=3||energy==2->CycleTrainingSignal.REDUCE_LOAD;bleeding||energy==3->CycleTrainingSignal.OFFER_FLEXIBLE_OPTION;else->CycleTrainingSignal.NO_ADJUSTMENT}
}

@HiltViewModel class CycleAwareViewModel @Inject constructor(private val repository:CycleAwareRepository):ViewModel(){private val mutable=MutableStateFlow(CycleAwareState());val state=mutable.asStateFlow();private var accountId:String?=null
 fun start(accountId:String){if(this.accountId==accountId&&mutable.value.loaded)return;this.accountId=accountId;reload()}
 fun setEnabled(value:Boolean)=viewModelScope.launch{accountId?.let{repository.setEnabled(it,value);reload()}}
 fun log(bleeding:Boolean,energy:Int,discomfort:Int,workoutId:String?=null)=viewModelScope.launch{val id=accountId?:return@launch;val response=repository.log(id,bleeding,energy,discomfort,workoutId);reload();mutable.value=mutable.value.copy(response=response)}
 fun requestGentler(workoutId:String)=viewModelScope.launch{val id=accountId?:return@launch;mutable.value=mutable.value.copy(response=repository.request(id,workoutId))}
 fun clear()=viewModelScope.launch{accountId?.let{repository.clear(it);reload()}}
 private fun reload()=viewModelScope.launch{accountId?.let{mutable.value=repository.state(it)}}
}
