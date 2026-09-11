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
import retrofit2.http.POST

@Serializable data class RewardsReferralDto(
    val code: String,
    val shareURL: String,
    val claimStatus: String? = null,
    val qualifiedCount: Int,
    val pendingCount: Int,
)
@Serializable data class CapabilityEntitlementDto(
    val capability: String,
    val allowed: Boolean,
    val expiresAt: String? = null,
    val sources: List<String> = emptyList(),
)
@Serializable data class RewardsStatusDto(
    val referral: RewardsReferralDto,
    val entitlements: List<CapabilityEntitlementDto>,
)
@Serializable data class RewardCodeRequestDto(val code: String)
@Serializable data class RewardRedemptionDto(
    val claimed: Boolean? = null,
    val redeemed: Boolean? = null,
    val rewardDays: Int? = null,
    val durationDays: Int? = null,
    val bundle: String? = null,
)

interface RewardsApiService {
    @GET("v1/rewards") suspend fun status(@Header("Authorization") authorization: String): Response<RewardsStatusDto>
    @POST("v1/rewards/referrals/claim") suspend fun claimInvitation(@Header("Authorization") authorization: String, @Body body: RewardCodeRequestDto): Response<RewardRedemptionDto>
    @POST("v1/rewards/codes/redeem") suspend fun redeemEntitlement(@Header("Authorization") authorization: String, @Body body: RewardCodeRequestDto): Response<RewardRedemptionDto>
}

fun createRewardsApi(baseUrl: String, client: OkHttpClient): RewardsApiService = Retrofit.Builder()
    .baseUrl(if (baseUrl.endsWith('/')) baseUrl else "$baseUrl/")
    .client(client)
    .addConverterFactory(PlainstrideJson.asConverterFactory("application/json".toMediaType()))
    .build()
    .create(RewardsApiService::class.java)
