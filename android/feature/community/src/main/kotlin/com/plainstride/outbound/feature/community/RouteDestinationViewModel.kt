package com.plainstride.outbound.feature.community

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.plainstride.outbound.core.analytics.*
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

@HiltViewModel
class RouteDestinationViewModel @Inject constructor(
    private val repository: CommunityRouteRepository,
    private val analytics: ProductAnalytics,
) : ViewModel() {
    private val mutableImports = MutableStateFlow<List<CommunityRoute>>(emptyList())
    val imports = mutableImports.asStateFlow()
    private val mutableDetail = MutableStateFlow<CommunityRoute?>(null)
    val detail = mutableDetail.asStateFlow()
    private val mutableLoading = MutableStateFlow(true)
    val loading = mutableLoading.asStateFlow()
    val feedback = MutableSharedFlow<Boolean>(extraBufferCapacity = 4)
    private var importsJob: Job? = null
    private var accountId: String? = null

    fun startLibrary(account: String, initialSelection: CommunityRoute?) {
        if (accountId == account) return
        accountId = account
        importsJob?.cancel()
        importsJob = viewModelScope.launch {
            perform("route_import_restore") {
                if (initialSelection?.id?.startsWith("import:") == true) repository.cacheDetail(account, initialSelection)
                repository.observeImports(account).collect { mutableImports.value = it }
            }
        }
    }
    fun saveImport(account: String, route: CommunityRoute, onComplete: (Boolean) -> Unit) = viewModelScope.launch {
        onComplete(perform("route_import_store") { repository.saveImport(account, route) })
    }
    fun open(account: String, route: CommunityRoute, navigate: (CommunityRoute) -> Unit) = viewModelScope.launch {
        perform("route_navigation_store") { repository.cacheDetail(account, route); navigate(route) }
    }
    fun deleteImport(account: String, id: String, onDeleted: () -> Unit = {}) = viewModelScope.launch {
        perform("route_import_delete") { repository.deleteImport(account, id); onDeleted() }
    }
    fun load(account: String, id: String, force: Boolean = false) = viewModelScope.launch {
        if (!force && mutableDetail.value?.id == id) return@launch
        mutableLoading.value = true
        perform("route_detail_load", notify = false) {
            mutableDetail.value = repository.cachedDetail(account, id)
            if (!id.startsWith("import:")) repository.detail(id).onSuccess {
                repository.cacheDetail(account, it)
                mutableDetail.value = it
            }.onFailure {
                if ((it as? RouteRequestException)?.status in setOf(403, 404)) {
                    repository.deleteCachedDetail(account, id)
                    mutableDetail.value = null
                }
                logFailure("route_detail_refresh", it)
            }
            if (mutableDetail.value == null) Log.i("PlainstrideRoutes", "route_detail_load unavailable")
            analytics.record(AnalyticsEvent("route_detail_opened", mapOf(
                AnalyticsProperty.SourceType to if (id.startsWith("import:")) "imported" else "community",
                AnalyticsProperty.Result to if (mutableDetail.value == null) "failure" else "success",
            )))
        }
        mutableLoading.value = false
    }
    fun bookmark(account: String, route: CommunityRoute, onChanged: () -> Unit) = viewModelScope.launch {
        perform("route_bookmark") {
            repository.bookmark(route.id, !route.isBookmarked).getOrThrow()
            val updated = route.copy(isBookmarked = !route.isBookmarked)
            repository.cacheDetail(account, updated)
            mutableDetail.value = updated
            onChanged()
            feedback.emit(true)
        }
    }
    fun remove(account: String, route: CommunityRoute, onDeleted: () -> Unit) = viewModelScope.launch {
        perform("route_remove") { repository.remove(route.id).getOrThrow(); repository.deleteCachedDetail(account, route.id); feedback.emit(true); onDeleted() }
    }
    private suspend fun perform(operation: String, notify: Boolean = true, block: suspend () -> Unit): Boolean {
        return try { block(); true } catch (error: Exception) {
            if (error is CancellationException) throw error
            logFailure(operation, error)
            if (notify) feedback.emit(false)
            false
        }
    }
    private fun logFailure(operation: String, error: Throwable) {
        if (error is CancellationException) throw error
        val apiError = error as? RouteRequestException
        Log.w("PlainstrideRoutes", "$operation failed type=${error.javaClass.simpleName} category=${apiError?.code} status=${apiError?.status}")
    }
}
