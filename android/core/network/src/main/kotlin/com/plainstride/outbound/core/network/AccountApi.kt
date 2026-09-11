package com.plainstride.outbound.core.network

import kotlinx.serialization.Serializable
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.PATCH
import retrofit2.http.PUT

@Serializable data class AccountDto(
    val id: String,
    val username: String? = null,
    val displayName: String? = null,
    val avatarUrl: String? = null,
    val normalizedEmail: String? = null,
    val contactEmail: String? = null,
    val bio: String? = null,
    val contactPhone: String? = null,
    val onboardingCompleted: Boolean? = null,
)
@Serializable data class UpdateAccountRequest(val username: String? = null, val displayName: String, val bio: String? = null, val contactEmail: String? = null, val contactPhone: String? = null)

@Serializable data class GuideSelectionDto(
    val coachPersonaId: String = "coach_default",
    val voiceProfileId: String = "voice_default",
    val theme: String = "victoryGold",
    val intensity: String = "balanced",
    val nudgeFrequency: String = "normal",
    val coachingContract: String = "responsive",
)
@Serializable data class GearPreferenceDto(
    val id: String,
    val kind: String,
    val purpose: String,
    val name: String,
    val brand: String,
    val model: String,
    val startedAt: String,
    val retiredAt: String? = null,
    val distanceLimitM: Double,
    val notes: String,
)
@Serializable data class MusicSelectionDto(val id: String, val title: String, val subtitle: String, val category: String)
@Serializable data class MusicPreferencesDto(
    val selectedQuickPickId: String? = null,
    val selectedCustomItems: List<MusicSelectionDto> = emptyList(),
    val isDisabled: Boolean = false,
    val repeatsQueue: Boolean = false,
    val shufflesQueue: Boolean = false,
)
@Serializable data class UserPreferencesDto(
    val schemaVersion: Int = 1,
    val measurementUnitSystem: String = "metric",
    val temperatureUnit: String = "celsius",
    val voiceGuideEnabled: Boolean = true,
    val appearanceMode: String = "system",
    val guideSelection: GuideSelectionDto = GuideSelectionDto(),
    val shoes: List<GearPreferenceDto> = emptyList(),
    val defaultShoeId: String? = null,
    val music: MusicPreferencesDto = MusicPreferencesDto(),
    val preferredSessionPage: String = "map",
    val preferredLaunchGoalMode: String? = null,
)
@Serializable data class UserPreferencesResponseDto(
    val contractVersion: Int,
    val preferences: UserPreferencesDto? = null,
    val updatedAt: String? = null,
)

interface AccountApiService {
    @GET("v1/auth/me") suspend fun currentAccount(@Header("Authorization") authorization: String): Response<AccountDto>
    @PATCH("v1/auth/me") suspend fun updateAccount(@Header("Authorization") authorization: String, @Body body: UpdateAccountRequest): Response<AccountDto>
    @GET("v1/auth/me/preferences") suspend fun preferences(@Header("Authorization") authorization: String): Response<UserPreferencesResponseDto>
    @PUT("v1/auth/me/preferences") suspend fun updatePreferences(@Header("Authorization") authorization: String, @Body body: UserPreferencesDto): Response<UserPreferencesResponseDto>
}

fun createAccountApi(baseUrl: String, client: OkHttpClient): AccountApiService = Retrofit.Builder()
    .baseUrl(if (baseUrl.endsWith('/')) baseUrl else "$baseUrl/")
    .client(client)
    .addConverterFactory(PlainstrideJson.asConverterFactory("application/json".toMediaType()))
    .build()
    .create(AccountApiService::class.java)
