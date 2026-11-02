package com.plainstride.outbound.feature.recording

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
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
    Dialog(onDismissRequest = { if (!busy) { if (picking) picking = false else onDismiss() } }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.safeDrawingPadding().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(enabled = !busy, onClick = { if (picking) picking = false else onDismiss() }) { Text(stringResource(R.string.stretch_catalog_ui_cancel)) }
                    Spacer(Modifier.weight(1f))
                    if (!picking) TextButton(enabled = !busy && StretchCatalog.valid(entries), onClick = { save(entries) }) { Text(stringResource(R.string.stretch_catalog_ui_save)) }
                }
                Text(stringResource(if (!picking) R.string.stretch_catalog_ui_editor else if (replacing == null) R.string.stretch_catalog_ui_add else R.string.stretch_catalog_ui_replace), style = MaterialTheme.typography.headlineSmall)
                if (picking) {
                    val definitions = StretchCatalogData.definitions.filter { d ->
                        d.dynamic == routine.isWarmup && (area == "all" || d.area == area) &&
                            (requirement == "any" || requirement == "none" && !d.floor && !d.support && !d.surface || requirement == "wall" && d.support || requirement == "floor" && d.floor || requirement == "surface" && d.surface) &&
                            (entries.none { it.movementID == d.id } || d.id == replacing)
                    }
                    LazyVerticalGrid(columns = GridCells.Adaptive(145.dp), modifier = Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp), contentPadding = PaddingValues(bottom = 24.dp)) {
                        item(span = { GridItemSpan(maxLineSpan) }) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                StretchFilter(area, listOf("all" to R.string.stretch_catalog_ui_all, "upper" to R.string.stretch_catalog_ui_upper, "lower" to R.string.stretch_catalog_ui_lower)) { area = it }
                                StretchFilter(requirement, listOf("any" to R.string.stretch_catalog_ui_any, "none" to R.string.stretch_catalog_ui_none, "wall" to R.string.stretch_catalog_ui_wall, "floor" to R.string.stretch_catalog_ui_floor, "surface" to R.string.stretch_catalog_ui_surface)) { requirement = it }
                            }
                        }
                        items(definitions, key = { it.id }) { definition ->
                            Card(onClick = {
                                val index = entries.indexOfFirst { it.movementID == replacing }
                                entries = if (index >= 0) entries.toMutableList().apply { set(index, get(index).copy(movementID = definition.id)) } else entries + StretchEntry(definition.id, 25)
                                onAction(if (index >= 0) "replace" else "add")
                                picking = false
                            }, shape = RoundedCornerShape(20.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.06f))) {
                                Column(Modifier.fillMaxWidth().heightIn(min = 200.dp).padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    StretchIllustration(definition.id + if (definition.bilateral) "_left" else "_both", Modifier.fillMaxWidth().height(120.dp))
                                    Text(stringResource(definition.title), style = MaterialTheme.typography.titleSmall, textAlign = TextAlign.Center)
                                    Text(routine.copy(entries = listOf(StretchEntry(definition.id, 25))).requirements(context), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
                                }
                            }
                        }
                    }
                } else {
                    val preview = routine.copy(entries = entries)
                    LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        item {
                            Column(Modifier.padding(vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(stringResource(routine.title), style = MaterialTheme.typography.titleMedium)
                                Text("≈ ${stretchClock(preview.totalSeconds)} · ${preview.requirements(context)}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                if (entries.isEmpty()) Text(stringResource(R.string.stretch_catalog_ui_empty))
                            }
                        }
                        itemsIndexed(entries, key = { _, entry -> entry.movementID }) { index, entry ->
                            val definition = StretchCatalog.definition(entry.movementID) ?: return@itemsIndexed
                            StretchEditorRow(definition, entry, routine.copy(entries = listOf(entry)).requirements(context), busy,
                                canMoveUp = index > 0, canMoveDown = index < entries.lastIndex,
                                onDuration = { seconds -> entries = entries.toMutableList().apply { set(index, entry.copy(seconds = seconds)) }; onAction("duration") },
                                onReplace = { replacing = definition.id; area = definition.area; picking = true },
                                onRemove = { removed = index to entry; entries = entries.filterIndexed { i, _ -> i != index }; onAction("remove") },
                                onMove = { offset -> entries = entries.toMutableList().apply { java.util.Collections.swap(this, index, index + offset) }; onAction("reorder") },
                            )
                        }
                        item { TextButton(enabled = entries.size < 20 && !busy, onClick = { replacing = null; area = "all"; picking = true }) { Text(stringResource(R.string.stretch_catalog_ui_add)) } }
                        if (entries.size >= 20) item { Text(stringResource(R.string.stretch_catalog_ui_limit)) }
                        removed?.let { removedEntry -> item { TextButton(enabled = entries.size < 20 && !busy && entries.none { it.movementID == removedEntry.second.movementID }, onClick = { entries = entries.toMutableList().apply { add(minOf(removedEntry.first, size), removedEntry.second) }; removed = null; onAction("undo") }) { Text(stringResource(R.string.stretch_catalog_ui_undo)) } } }
                        item { TextButton(enabled = !busy, onClick = { save(null) }) { Text(stringResource(R.string.stretch_catalog_ui_reset)) } }
                    }
                }
            }
        }
    }
}

@Composable
private fun StretchEditorRow(
    definition: StretchDefinition, entry: StretchEntry, requirements: String, busy: Boolean,
    canMoveUp: Boolean, canMoveDown: Boolean, onDuration: (Int) -> Unit,
    onReplace: () -> Unit, onRemove: () -> Unit, onMove: (Int) -> Unit,
) {
    var durationMenu by remember { mutableStateOf(false) }
    var actionsMenu by remember { mutableStateOf(false) }
    val durationLabel = stringResource(if (definition.bilateral) R.string.stretch_catalog_ui_duration else R.string.stretch_catalog_ui_duration_both)
    val actionsLabel = stringResource(R.string.stretch_ui_posture_actions, stringResource(definition.title))
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        StretchIllustration(definition.id + if (definition.bilateral) "_left" else "_both", Modifier.size(56.dp, 64.dp).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.05f), RoundedCornerShape(12.dp)))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(stringResource(definition.title), style = MaterialTheme.typography.titleSmall)
            if (definition.bilateral) Text(stringResource(R.string.stretch_catalog_ui_both_sides), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (requirements != stringResource(R.string.stretch_catalog_ui_none)) Text(requirements, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Box {
            TextButton(enabled = !busy, onClick = { durationMenu = true }, modifier = Modifier.semantics { contentDescription = durationLabel }) { Text(stretchClock(entry.seconds)) }
            DropdownMenu(durationMenu, onDismissRequest = { durationMenu = false }) {
                StretchCatalog.durations.forEach { seconds -> DropdownMenuItem(text = { Text(stretchClock(seconds)) }, onClick = { durationMenu = false; onDuration(seconds) }) }
            }
        }
        Box {
            IconButton(enabled = !busy, onClick = { actionsMenu = true }) { Icon(Icons.Default.MoreHoriz, actionsLabel) }
            DropdownMenu(actionsMenu, onDismissRequest = { actionsMenu = false }) {
                DropdownMenuItem(text = { Text(stringResource(R.string.stretch_catalog_ui_replace)) }, onClick = { actionsMenu = false; onReplace() })
                DropdownMenuItem(text = { Text(stringResource(R.string.stretch_catalog_ui_up)) }, enabled = canMoveUp, onClick = { actionsMenu = false; onMove(-1) })
                DropdownMenuItem(text = { Text(stringResource(R.string.stretch_catalog_ui_down)) }, enabled = canMoveDown, onClick = { actionsMenu = false; onMove(1) })
                DropdownMenuItem(text = { Text(stringResource(R.string.stretch_catalog_ui_remove)) }, onClick = { actionsMenu = false; onRemove() })
            }
        }
    }
    HorizontalDivider()
}

@Composable
private fun StretchFilter(selected: String, options: List<Pair<String, Int>>, onSelect: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val option = options.first { it.first == selected }
    Box {
        OutlinedButton(onClick = { expanded = true }) { Text(stringResource(option.second)) }
        DropdownMenu(expanded, onDismissRequest = { expanded = false }) {
            options.forEach { (id, resource) -> DropdownMenuItem(text = { Text(stringResource(resource)) }, onClick = { onSelect(id); expanded = false }) }
        }
    }
}
