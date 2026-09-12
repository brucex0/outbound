package com.plainstride.outbound.core.auth

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** Stores one authenticated AES-GCM blob so refresh rotation is committed atomically. */
class KeystoreSecureSessionStore(context: Context) : SecureSessionStore {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = false }

    override suspend fun load(): SessionCredentials? = withContext(Dispatchers.IO) {
        val encoded = preferences.getString(SESSION, null) ?: return@withContext null
        runCatching {
            val envelope = json.decodeFromString<EncryptedEnvelope>(encoded)
            val cipher = Cipher.getInstance(TRANSFORMATION).apply {
                init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, envelope.iv.decode()))
            }
            json.decodeFromString<StoredSession>(cipher.doFinal(envelope.ciphertext.decode()).decodeToString()).toCredentials()
        }.getOrElse {
            preferences.edit().remove(SESSION).commit()
            null
        }
    }

    override suspend fun replace(credentials: SessionCredentials) = withContext(Dispatchers.IO) {
        val cipher = Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, key()) }
        val plaintext = json.encodeToString(StoredSession.from(credentials)).encodeToByteArray()
        val envelope = EncryptedEnvelope(cipher.iv.encode(), cipher.doFinal(plaintext).encode())
        check(preferences.edit().putString(SESSION, json.encodeToString(envelope)).commit()) {
            "Unable to commit secure session"
        }
    }

    override suspend fun clear() = withContext(Dispatchers.IO) {
        preferences.edit().remove(SESSION).commit()
        Unit
    }

    private fun key(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build())
            generateKey()
        }
    }

    @Serializable private data class EncryptedEnvelope(val iv: String, val ciphertext: String)
    @Serializable private data class StoredSession(
        val accessToken: String,
        val accessTokenExpiresAtEpochMilliseconds: Long,
        val refreshToken: String,
        val refreshTokenExpiresAtEpochMilliseconds: Long,
        val accountId: String? = null,
        val onboardingCompleted: Boolean? = null,
        val onboardingStatus: String? = null,
    ) {
        fun toCredentials() = SessionCredentials(
            accessToken,
            accessTokenExpiresAtEpochMilliseconds,
            refreshToken,
            refreshTokenExpiresAtEpochMilliseconds,
            accountId?.let { SessionAccount(it, onboardingCompleted, onboardingStatus) },
        )
        companion object {
            fun from(value: SessionCredentials) = StoredSession(
                value.accessToken,
                value.accessTokenExpiresAtEpochMilliseconds,
                value.refreshToken,
                value.refreshTokenExpiresAtEpochMilliseconds,
                value.account?.id,
                value.account?.onboardingCompleted,
                value.account?.onboardingStatus,
            )
        }
    }

    private fun ByteArray.encode() = Base64.encodeToString(this, Base64.NO_WRAP)
    private fun String.decode() = Base64.decode(this, Base64.NO_WRAP)

    private companion object {
        const val PREFERENCES = "plainstride_secure_session"
        const val SESSION = "session_v1"
        const val KEY_ALIAS = "plainstride_refresh_session_v1"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
