package com.plainstride.outbound.feature.livecoach

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import com.plainstride.outbound.feature.livecoach.network.CoachingContract

data class LiveCoachPreferences(
    val enabled: Boolean = false,
    val personaId: String = "plainstride_supportive_v1",
    val voiceProfileId: String = "plainstride_warm_1",
    val scriptStyleId: String = "standard",
    val contract: CoachingContract = CoachingContract.Responsive,
)

interface LiveCoachPreferencesRepository {
    val preferences: Flow<LiveCoachPreferences>
    suspend fun save(value: LiveCoachPreferences)
}

@Singleton class DataStoreLiveCoachPreferences @Inject constructor(private val store: DataStore<Preferences>) : LiveCoachPreferencesRepository {
    override val preferences = store.data.map { values -> LiveCoachPreferences(
        enabled = values[Enabled] == "true", personaId = values[Persona] ?: "plainstride_supportive_v1",
        voiceProfileId = values[Voice] ?: "plainstride_warm_1", scriptStyleId = values[Style] ?: "standard",
        contract = CoachingContract.entries.firstOrNull { it.name == values[Contract] } ?: CoachingContract.Responsive,
    ) }
    override suspend fun save(value: LiveCoachPreferences) { store.edit { it[Enabled] = value.enabled.toString(); it[Persona] = value.personaId; it[Voice] = value.voiceProfileId; it[Style] = value.scriptStyleId; it[Contract] = value.contract.name } }
    private companion object { val Enabled = stringPreferencesKey("live_coach_enabled_v1"); val Persona = stringPreferencesKey("live_coach_persona_v1"); val Voice = stringPreferencesKey("live_coach_voice_v1"); val Style = stringPreferencesKey("live_coach_style_v1"); val Contract = stringPreferencesKey("live_coach_contract_v1") }
}
