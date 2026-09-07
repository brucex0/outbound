package run.plainstride.core.database

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.byteArrayPreferencesKey
import androidx.datastore.preferences.core.edit
import kotlinx.coroutines.flow.first

interface TransactionRunner {
    suspend fun <T> inTransaction(block: suspend () -> T): T
}

interface DurableStateStore {
    suspend fun read(key: String): ByteArray?
    suspend fun write(key: String, value: ByteArray)
    suspend fun remove(key: String)
}

class DataStoreDurableStateStore(
    private val dataStore: DataStore<Preferences>,
) : DurableStateStore {
    override suspend fun read(key: String): ByteArray? =
        dataStore.data.first()[preferenceKey(key)]

    override suspend fun write(key: String, value: ByteArray) {
        dataStore.edit { preferences ->
            preferences[preferenceKey(key)] = value
        }
    }

    override suspend fun remove(key: String) {
        dataStore.edit { preferences ->
            preferences.remove(preferenceKey(key))
        }
    }

    private fun preferenceKey(key: String): Preferences.Key<ByteArray> {
        require(KEY_FORMAT.matches(key)) { "Durable state keys must be semantic identifiers." }
        return byteArrayPreferencesKey(key)
    }

    private companion object {
        val KEY_FORMAT = Regex("[a-z][a-z0-9_.-]{1,79}")
    }
}
