package com.plainstride.outbound.feature.assistant

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import com.plainstride.outbound.core.analytics.*
import com.plainstride.outbound.core.music.*

data class MusicUiState(val query: String = "", val results: List<MusicItem> = emptyList(), val searching: Boolean = false)
@HiltViewModel class MusicViewModel @Inject constructor(private val provider: MusicProvider, private val catalog: SpotifyCatalog, private val analytics: ProductAnalytics) : ViewModel() {
    val music = provider.state; val ui = MutableStateFlow(MusicUiState())
    fun connect() = viewModelScope.launch { analytics.record(AnalyticsEvent("music_connect_started", mapOf(AnalyticsProperty.Source to "spotify"))); provider.connect() }
    fun disconnect() = viewModelScope.launch { provider.disconnect(); analytics.record(AnalyticsEvent("music_disconnected")) }
    fun query(value: String) { ui.value = ui.value.copy(query = value.take(100)) }
    fun search() = viewModelScope.launch { ui.value = ui.value.copy(searching = true); val result = catalog.search(ui.value.query); ui.value = ui.value.copy(results = result.getOrDefault(emptyList()), searching = false); analytics.record(AnalyticsEvent("music_search", mapOf(AnalyticsProperty.Result to if (result.isSuccess) "success" else "failure"))) }
    fun select(item: MusicItem) = viewModelScope.launch { val q = music.value.queue; provider.setQueue(q.copy(items = (q.items + item).distinctBy { it.uri })); analytics.record(AnalyticsEvent("music_queue_updated")) }
    fun repeat(value: Boolean) = viewModelScope.launch { provider.setQueue(music.value.queue.copy(repeat = value)) }
    fun shuffle(value: Boolean) = viewModelScope.launch { provider.setQueue(music.value.queue.copy(shuffle = value)) }
    fun play() = viewModelScope.launch { provider.play(music.value.queue.currentIndex) }; fun pause() = viewModelScope.launch { provider.pause() }; fun next() = viewModelScope.launch { provider.skipNext() }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable fun MusicRoute(onClose: () -> Unit, viewModel: MusicViewModel = hiltViewModel()) {
    val music = viewModel.music.collectAsStateWithLifecycle().value; val ui = viewModel.ui.collectAsStateWithLifecycle().value
    Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.music_title)) }, navigationIcon = { TextButton(onClick = onClose) { Text(stringResource(R.string.close)) } }) }) { p -> LazyColumn(Modifier.fillMaxSize().padding(p).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { Text(if (music.lastFailure == "spotify_not_configured") stringResource(R.string.spotify_not_configured) else music.connection.name, style = MaterialTheme.typography.titleMedium); Row { Button(onClick = viewModel::connect, enabled = music.lastFailure != "spotify_not_configured") { Text(stringResource(R.string.connect_spotify)) }; TextButton(onClick = viewModel::disconnect) { Text(stringResource(R.string.disconnect)) } } }
        item { Row { OutlinedTextField(ui.query, viewModel::query, Modifier.weight(1f), label = { Text(stringResource(R.string.search_music)) }); Button(onClick = viewModel::search, enabled = !ui.searching) { Text(stringResource(R.string.search)) } } }
        items(ui.results) { item -> ListItem(headlineContent = { Text(item.title) }, supportingContent = { Text(item.subtitle) }, modifier = Modifier.clickable { viewModel.select(item) }) }
        item { Text(stringResource(R.string.queue), style = MaterialTheme.typography.titleMedium); music.queue.items.forEach { Text("${it.title} · ${it.subtitle}") }; Row { FilterChip(music.queue.repeat, { viewModel.repeat(!music.queue.repeat) }, { Text(stringResource(R.string.repeat)) }); FilterChip(music.queue.shuffle, { viewModel.shuffle(!music.queue.shuffle) }, { Text(stringResource(R.string.shuffle)) }) }; Row { Button(onClick = viewModel::play, enabled = music.queue.items.isNotEmpty()) { Text(stringResource(R.string.play)) }; TextButton(onClick = viewModel::pause) { Text(stringResource(R.string.pause)) }; TextButton(onClick = viewModel::next) { Text(stringResource(R.string.next)) } } }
    } }
}
