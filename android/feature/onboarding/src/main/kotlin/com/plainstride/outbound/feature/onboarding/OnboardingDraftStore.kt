package com.plainstride.outbound.feature.onboarding

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import javax.inject.Inject
import kotlinx.coroutines.flow.first
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class OnboardingDraftStore @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    suspend fun load(accountId: String): OnboardingDraft? = dataStore.data.first()[draftKey(accountId)]
        ?.let { runCatching { json.decodeFromString<OnboardingDraft>(it) }.getOrNull() }
        ?.takeIf { it.accountId == accountId }

    suspend fun save(draft: OnboardingDraft) {
        dataStore.edit { it[draftKey(draft.accountId)] = json.encodeToString(draft) }
    }

    suspend fun clear(accountId: String) {
        dataStore.edit { it.remove(draftKey(accountId)) }
    }

    private fun draftKey(accountId: String) = stringPreferencesKey("onboarding_draft_${accountId.safeKey()}")
    private fun String.safeKey() = fold(0x811c9dc5L) { hash, char -> (hash xor char.code.toLong()) * 0x01000193L }.toString(16)
}
