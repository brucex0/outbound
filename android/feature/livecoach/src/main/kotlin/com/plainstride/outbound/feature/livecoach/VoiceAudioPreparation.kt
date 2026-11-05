package com.plainstride.outbound.feature.livecoach

import android.content.Context
import android.util.Log
import android.widget.Toast
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.network.AccessTokenProvider
import com.plainstride.outbound.core.network.ApiResult
import com.plainstride.outbound.feature.livecoach.audio.AudioPackSelection
import com.plainstride.outbound.feature.livecoach.audio.FixedAudioPackStore
import com.plainstride.outbound.feature.livecoach.audio.VoicePackTrust
import com.plainstride.outbound.feature.livecoach.network.LiveCoachRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

data class VoicePreparationState(
    val preparing: Boolean = false,
    val ready: Boolean = false,
    val completed: Int = 0,
    val total: Int = 0,
)

/** Fixed recordings only. Dynamic stats and planned-phrase caching keep their existing paths. */
@Singleton
class VoiceAudioPreparation @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val preferences: LiveCoachPreferencesRepository,
    private val repository: LiveCoachRepository,
    private val tokens: AccessTokenProvider,
    private val packs: FixedAudioPackStore,
    private val analytics: ProductAnalytics,
) {
    private val mutableState = MutableStateFlow(VoicePreparationState())
    val state: StateFlow<VoicePreparationState> = mutableState
    private val retryRevision = MutableStateFlow(0)
    private var job: Job? = null
    private var generation = 0

    fun activate(scope: CoroutineScope, locale: String) {
        stop()
        val activeGeneration = generation
        job = scope.launch {
            combine(
                preferences.preferences.map {
                    AudioPackSelection(locale, it.voiceProfileId, it.personaId, it.scriptStyleId)
                }.distinctUntilChanged(),
                retryRevision,
            ) { selection, revision -> selection to revision }.collectLatest { (selection, _) ->
                mutableState.value = VoicePreparationState(preparing = true)
                val ready = try {
                    withTimeoutOrNull(60_000L) {
                        val cached = packs.cachedReady(selection)
                        if (generation == activeGeneration && cached) mutableState.value = VoicePreparationState(preparing = true, ready = true)
                        val token = tokens.validAccessToken()
                        if (token != null) {
                            when (val result = repository.catalog(token, selection.locale)) {
                                is ApiResult.Success -> result.value.audioPack?.let {
                                    packs.refresh(it.manifestUrl, it.manifestVersion, VoicePackTrust.publicKeys)
                                }
                                is ApiResult.Failure -> Log.w(TAG, "operation=prepare_catalog status=${result.error.httpStatus} code=${result.error.code}")
                            }
                        } else Log.w(TAG, "operation=prepare_catalog result=no_session")
                        // A previously verified catalog can prepare/reuse files even while offline.
                        packs.prepare(selection) { completed, total ->
                            if (generation == activeGeneration) {
                                mutableState.value = VoicePreparationState(preparing = true, completed = completed, total = total)
                            }
                        }
                    } == true
                } catch (error: CancellationException) { throw error }
                catch (error: Exception) {
                    Log.w(TAG, "operation=prepare_voice type=${error.javaClass.simpleName}")
                    false
                }
                if (generation != activeGeneration) return@collectLatest
                mutableState.value = mutableState.value.copy(preparing = false, ready = ready)
                analytics.record(AnalyticsEvent("voice_audio_preparation", mapOf(
                    AnalyticsProperty.Result to if (ready) "ready" else "incomplete",
                )))
                if (!ready) Log.w(TAG, "operation=prepare_voice result=incomplete")
            }
        }
    }

    fun retry() {
        if (!mutableState.value.preparing) retryRevision.value += 1
    }

    fun activityWillStart(voiceEnabled: Boolean) {
        if (!voiceEnabled) return
        val ready = mutableState.value.ready
        analytics.record(AnalyticsEvent("voice_audio_start", mapOf(
            AnalyticsProperty.Result to if (ready) "ready" else "incomplete",
        )))
        if (!ready) {
            Toast.makeText(context, R.string.voice_audio_unavailable, Toast.LENGTH_LONG).show()
            retry() // Never awaited: missing audio must not delay activity start.
        }
    }

    fun stop() {
        generation += 1
        job?.cancel()
        job = null
        mutableState.value = VoicePreparationState()
    }

    private companion object { const val TAG = "PlainstrideVoicePack" }
}

@HiltViewModel
class VoicePreparationViewModel @Inject constructor(
    val preparation: VoiceAudioPreparation,
) : ViewModel() {
    fun activate(locale: String) = preparation.activate(viewModelScope, locale)
    override fun onCleared() { preparation.stop() }
}
