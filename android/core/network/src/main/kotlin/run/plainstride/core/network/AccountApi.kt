package run.plainstride.core.network

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

@Serializable data class AccountDto(
    val id: String,
    val username: String? = null,
    val displayName: String? = null,
    val normalizedEmail: String? = null,
    val contactEmail: String? = null,
    val onboardingCompleted: Boolean? = null,
)
@Serializable data class UpdateAccountRequest(val username: String? = null, val displayName: String, val contactEmail: String? = null)

interface AccountApiService {
    @GET("v1/auth/me") suspend fun currentAccount(@Header("Authorization") authorization: String): Response<AccountDto>
    @PATCH("v1/auth/me") suspend fun updateAccount(@Header("Authorization") authorization: String, @Body body: UpdateAccountRequest): Response<AccountDto>
}

fun createAccountApi(baseUrl: String, client: OkHttpClient): AccountApiService = Retrofit.Builder()
    .baseUrl(if (baseUrl.endsWith('/')) baseUrl else "$baseUrl/")
    .client(client)
    .addConverterFactory(PlainstrideJson.asConverterFactory("application/json".toMediaType()))
    .build()
    .create(AccountApiService::class.java)
