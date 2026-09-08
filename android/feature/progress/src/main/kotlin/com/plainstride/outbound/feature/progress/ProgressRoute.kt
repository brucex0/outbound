package com.plainstride.outbound.feature.progress

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@HiltViewModel class GearViewModel @Inject constructor(private val repository: GearRepository) : ViewModel() {
    private val mutable = MutableStateFlow<List<GearMileageSummary>>(emptyList()); val gear = mutable.asStateFlow()
    fun start(accountId:String)=viewModelScope.launch{repository.configure(accountId);refresh()}
    fun add(name:String)=viewModelScope.launch{repository.replace(repository.collection().adding(name,"",name,GearPurpose.DAILY_TRAINER));refresh()}
    fun retire(item:GearItem)=viewModelScope.launch{repository.replace(repository.collection().retiring(item.id));refresh()}
    fun makeDefault(item:GearItem)=viewModelScope.launch{repository.replace(repository.collection().settingDefault(item.id));refresh()}
    private suspend fun refresh(){val collection=repository.collection();mutable.value=collection.mileage(repository.activityDistances())}
}

@Composable fun ProgressRoute(accountId:String,state:ProgressScreenState,viewModel:GearViewModel=hiltViewModel()){
    LaunchedEffect(accountId){viewModel.start(accountId)}
    val gear by viewModel.gear.collectAsState()
    var add by remember{mutableStateOf(false)}
    Column{Row(Modifier.fillMaxWidth().padding(horizontal=20.dp),horizontalArrangement=Arrangement.End){TextButton({add=true}){Text(stringResource(R.string.progress_add_gear))}};ProgressScreen(state.copy(gear=gear),Modifier.weight(1f));gear.filterNot{it.item.isRetired}.forEach{summary->Row(Modifier.fillMaxWidth().padding(horizontal=20.dp)){TextButton({viewModel.makeDefault(summary.item)}){Text(stringResource(R.string.progress_make_default))};TextButton({viewModel.retire(summary.item)}){Text(stringResource(R.string.progress_retire))}}}}
    if(add){var name by remember{mutableStateOf("")};AlertDialog({add=false},title={Text(stringResource(R.string.progress_add_gear))},text={OutlinedTextField(name,{name=it.take(60)},label={Text(stringResource(R.string.progress_gear_name))})},confirmButton={TextButton({viewModel.add(name);add=false},enabled=name.isNotBlank()){Text(stringResource(R.string.progress_add))}},dismissButton={TextButton({add=false}){Text(stringResource(R.string.progress_cancel))}})}
}
