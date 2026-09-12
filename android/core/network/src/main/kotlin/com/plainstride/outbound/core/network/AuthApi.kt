package com.plainstride.outbound.core.network

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST

@Serializable
data class GoogleSignInRequest(
    val identityToken: String,
    val platform: String = "android",
    val deviceLabel: String? = null,
    val termsVersion: Int,
)

@Serializable
data class GoogleLinkRedemptionRequest(
    val identityToken: String,
    val code: String,
    val platform: String = "android",
    val deviceLabel: String? = null,
    val termsVersion: Int,
)

@Serializable data class RefreshRequest(val refreshToken: String)
@Serializable data class LogoutRequest(val refreshToken: String? = null)
@Serializable data class GoogleCredentialRequest(val identityToken: String)
@Serializable data class GoogleDeletionRequest(val provider: String = "google", val identityToken: String)

@Serializable
data class SessionUserDto(
    val id: String,
    val username: String? = null,
    val displayName: String? = null,
    val avatarUrl: String? = null,
    val email: String? = null,
    val onboardingStatus: String? = null,
    val onboardingCompleted: Boolean = false,
    val termsAcceptedVersion: Int = 0,
)

@Serializable
data class SessionResponseDto(
    val accessToken: String,
    val accessTokenExpiresAt: String,
    val refreshToken: String,
    val refreshTokenExpiresAt: String,
    val refreshRecovery: Boolean = false,
    val currentTermsVersion: Int,
    val user: SessionUserDto,
)

@Serializable data class LinkIdentityResponse(val linked: Boolean)
@Serializable data class DeleteAccountResponse(val deleted: Boolean)
@Serializable data class LogoutResponse(val loggedOut: Boolean)
@Serializable data class LinkedIdentityDto(val provider: String, val email: String? = null, val linkedAt: String)
@Serializable data class LinkedIdentitiesResponse(val identities: List<LinkedIdentityDto>)

interface AuthApiService {
    @POST("v1/auth/google") suspend fun signIn(@Body body: GoogleSignInRequest): Response<SessionResponseDto>
    @POST("v1/auth/refresh") suspend fun refresh(@Body body: RefreshRequest): Response<SessionResponseDto>
    @POST("v1/auth/logout") suspend fun logout(
        @Header("Authorization") authorization: String?,
        @Body body: LogoutRequest,
    ): Response<LogoutResponse>
    @POST("v1/auth/link/google") suspend fun linkGoogle(
        @Header("Authorization") authorization: String,
        @Body body: GoogleCredentialRequest,
    ): Response<LinkIdentityResponse>
    @POST("v1/auth/link-intents/redeem/google") suspend fun redeemGoogleLink(
        @Body body: GoogleLinkRedemptionRequest,
    ): Response<SessionResponseDto>
    @GET("v1/auth/me/identities") suspend fun identities(
        @Header("Authorization") authorization: String,
    ): Response<LinkedIdentitiesResponse>
    @DELETE("v1/auth/me") suspend fun deleteAccount(
        @Header("Authorization") authorization: String,
        @Body body: GoogleDeletionRequest,
    ): Response<DeleteAccountResponse>
}

fun createAuthApi(baseUrl: String, client: OkHttpClient): AuthApiService = Retrofit.Builder()
    .baseUrl(baseUrl.ensureTrailingSlash())
    .client(client)
    .addConverterFactory(PlainstrideJson.asConverterFactory("application/json".toMediaType()))
    .build()
    .create(AuthApiService::class.java)

private fun String.ensureTrailingSlash() = if (endsWith('/')) this else "$this/"
