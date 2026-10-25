package com.plainstride.outbound.feature.recording

import android.widget.Toast
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.launch

@Composable
internal fun StretchRoutineEditor(
    routine: StretchRoutine,
    onDismiss: () -> Unit,
    onAction: (String) -> Unit,
    onSave: suspend (List<StretchEntry>?) -> Boolean,
) {
    var entries by remember { mutableStateOf(routine.entries) }
    var removed by remember { mutableStateOf<Pair<Int, StretchEntry>?>(null) }
    var picking by remember { mutableStateOf(false) }
    var replacing by remember { mutableStateOf<String?>(null) }
    var area by remember { mutableStateOf("all") }
    var requirement by remember { mutableStateOf("any") }
    var busy by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    fun save(value: List<StretchEntry>?) {
        busy = true
        scope.launch {
            val success = onSave(value)
            busy = false
            Toast.makeText(context, if (success) R.string.stretch_catalog_ui_saved else R.string.stretch_catalog_ui_failed, Toast.LENGTH_SHORT).show()
            if (success) { onAction(if (value == null) "reset" else "saved"); onDismiss() }
        }
    }
    Dialog(onDismissRequest = { if (!busy) onDismiss() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.safeDrawingPadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(if (picking) R.string.stretch_catalog_ui_add else R.string.stretch_catalog_ui_editor), style = MaterialTheme.typography.titleLarge)
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    TextButton(enabled = !busy, onClick = { if (picking) picking = false else onDismiss() }) { Text(stringResource(R.string.stretch_catalog_ui_cancel)) }
                    if (!picking) Button(enabled = !busy && StretchCatalog.valid(entries), onClick = { save(entries) }) { Text(stringResource(R.string.stretch_catalog_ui_save)) }
                }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    if (picking) {
                        StretchFilter(area, listOf("all" to R.string.stretch_catalog_ui_all, "upper" to R.string.stretch_catalog_ui_upper, "lower" to R.string.stretch_catalog_ui_lower)) { area = it }
                        StretchFilter(requirement, listOf("any" to R.string.stretch_catalog_ui_any, "none" to R.string.stretch_catalog_ui_none, "wall" to R.string.stretch_catalog_ui_wall, "floor" to R.string.stretch_catalog_ui_floor, "surface" to R.string.stretch_catalog_ui_surface)) { requirement = it }
                        StretchCatalogData.definitions.filter { d ->
                            d.dynamic == routine.isWarmup &&
                            (area == "all" || d.area == area) &&
                            (requirement == "any" || requirement == "none" && !d.floor && !d.support && !d.surface || requirement == "wall" && d.support || requirement == "floor" && d.floor || requirement == "surface" && d.surface) &&
                            (entries.none { it.movementID == d.id } || d.id == replacing)
                        }.forEach { d ->
                            Card(onClick = {
                                val index = entries.indexOfFirst { it.movementID == replacing }
                                entries = if (index >= 0) entries.toMutableList().apply { set(index, get(index).copy(movementID = d.id)) }
                                    else entries + StretchEntry(d.id, 25)
                                onAction(if (index >= 0) "replace" else "add")
                                picking = false
                            }) {
                                Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                                    StretchIllustration(d.id + if (d.bilateral) "_left" else "_both", Modifier.size(64.dp))
                                    Column { Text(stringResource(d.title)); Text(stringResource(d.instruction), style = MaterialTheme.typography.bodySmall) }
                                }
                            }
                        }
                    } else {
                        val preview = routine.copy(entries = entries)
                        Text(stringResource(routine.title), style = MaterialTheme.typography.titleMedium)
                        Text("≈ ${preview.totalSeconds / 60}:${(preview.totalSeconds % 60).toString().padStart(2, '0')} · ${preview.requirements(context)}")
                        if (entries.isEmpty()) Text(stringResource(R.string.stretch_catalog_ui_empty))
                        entries.forEachIndexed { index, entry ->
                            val d = StretchCatalog.definition(entry.movementID) ?: return@forEachIndexed
                            Card {
                                Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                                        StretchIllustration(d.id + if (d.bilateral) "_left" else "_both", Modifier.size(64.dp))
                                        Column {
                                            Text(stringResource(d.title), style = MaterialTheme.typography.titleSmall)
                                            if (d.bilateral) Text(stringResource(R.string.stretch_catalog_ui_both_sides))
                                            Text(routine.copy(entries = listOf(entry)).requirements(context), style = MaterialTheme.typography.bodySmall)
                                        }
                                    }
                                    Text(stringResource(if (d.bilateral) R.string.stretch_catalog_ui_duration else R.string.stretch_catalog_ui_duration_both))
                                    StretchFilter(entry.seconds.toString(), StretchCatalog.durations.map { it.toString() to 0 }) { seconds ->
                                        entries = entries.toMutableList().apply { set(index, entry.copy(seconds = seconds.toInt())) }; onAction("duration")
                                    }
                                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        TextButton(enabled = !busy, onClick = { replacing = d.id; area = d.area; picking = true }) { Text(stringResource(R.string.stretch_catalog_ui_replace)) }
                                        TextButton(enabled = !busy, onClick = { removed = index to entry; entries = entries.filterIndexed { i, _ -> i != index }; onAction("remove") }) { Text(stringResource(R.string.stretch_catalog_ui_remove)) }
                                    }
                                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        TextButton(enabled = index > 0 && !busy, onClick = { entries = entries.toMutableList().apply { java.util.Collections.swap(this, index, index - 1) }; onAction("reorder") }) { Text(stringResource(R.string.stretch_catalog_ui_up)) }
                                        TextButton(enabled = index < entries.lastIndex && !busy, onClick = { entries = entries.toMutableList().apply { java.util.Collections.swap(this, index, index + 1) }; onAction("reorder") }) { Text(stringResource(R.string.stretch_catalog_ui_down)) }
                                    }
                                }
                            }
                        }
                        TextButton(enabled = entries.size < 20 && !busy, onClick = { replacing = null; area = "all"; picking = true }) { Text(stringResource(R.string.stretch_catalog_ui_add)) }
                        if (entries.size >= 20) Text(stringResource(R.string.stretch_catalog_ui_limit))
                        removed?.let { item -> TextButton(enabled = entries.size < 20 && !busy && entries.none { it.movementID == item.second.movementID }, onClick = { entries = entries.toMutableList().apply { add(minOf(item.first, size), item.second) }; removed = null; onAction("undo") }) { Text(stringResource(R.string.stretch_catalog_ui_undo)) } }
                        TextButton(enabled = !busy, onClick = { save(null) }) { Text(stringResource(R.string.stretch_catalog_ui_reset)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun StretchFilter(selected: String, options: List<Pair<String, Int>>, onSelect: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val option = options.first { it.first == selected }
    Box {
        OutlinedButton(onClick = { expanded = true }) { Text(if (option.second == 0) option.first else stringResource(option.second)) }
        DropdownMenu(expanded, onDismissRequest = { expanded = false }) {
            options.forEach { (id, resource) -> DropdownMenuItem(text = { Text(if (resource == 0) id else stringResource(resource)) }, onClick = { onSelect(id); expanded = false }) }
        }
    }
}
