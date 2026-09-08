package com.plainstride.outbound.core.music

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.flow.first
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.Base64

class SpotifySecureAuthorizationStore(context: Context) : SpotifyAuthorizationStore {
    private val preferences = context.getSharedPreferences("spotify_secure_authorization", Context.MODE_PRIVATE)
    override suspend fun load(): SpotifyAuthorization? = runCatching {
        val encrypted = preferences.getString(KEY_VALUE, null) ?: return null
        val parts = encrypted.split(':', limit = 2)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.getDecoder().decode(parts[0])))
        Json.decodeFromString<AuthorizationRecord>(String(cipher.doFinal(Base64.getDecoder().decode(parts[1])), Charsets.UTF_8)).domain()
    }.getOrNull()

    override suspend fun save(value: SpotifyAuthorization) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val ciphertext = cipher.doFinal(Json.encodeToString(AuthorizationRecord(value)).toByteArray())
        val encoded = "${Base64.getEncoder().encodeToString(cipher.iv)}:${Base64.getEncoder().encodeToString(ciphertext)}"
        check(preferences.edit().putString(KEY_VALUE, encoded).commit())
    }
    override suspend fun clear() { preferences.edit().remove(KEY_VALUE).commit() }
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    private companion object { const val KEY_ALIAS = "plainstride.spotify.authorization.v1"; const val KEY_VALUE = "value"; const val TRANSFORMATION = "AES/GCM/NoPadding" }
}

@kotlinx.serialization.Serializable
private data class AuthorizationRecord(val accessToken: String, val expiresAtEpochMs: Long, val refreshToken: String?, val scopes: Set<String>) {
    constructor(value: SpotifyAuthorization) : this(value.accessToken, value.expiresAtEpochMs, value.refreshToken, value.scopes)
    fun domain() = SpotifyAuthorization(accessToken, expiresAtEpochMs, refreshToken, scopes)
}

class MusicStateStore(private val dataStore: DataStore<Preferences>) {
    suspend fun loadQueue(): MusicQueue = dataStore.data.first()[QUEUE]?.let { runCatching { Json.decodeFromString<MusicQueue>(it) }.getOrNull() } ?: MusicQueue()
    suspend fun saveQueue(queue: MusicQueue) { dataStore.edit { it[QUEUE] = Json.encodeToString(queue) } }
    suspend fun loadPlayback(): MusicPlaybackState = dataStore.data.first()[PLAYBACK]?.let { runCatching { Json.decodeFromString<MusicPlaybackState>(it) }.getOrNull() } ?: MusicPlaybackState()
    suspend fun savePlayback(playback: MusicPlaybackState) { dataStore.edit { it[PLAYBACK] = Json.encodeToString(playback) } }
    private companion object { val QUEUE = stringPreferencesKey("spotify_queue_v1"); val PLAYBACK = stringPreferencesKey("spotify_playback_v1") }
}
