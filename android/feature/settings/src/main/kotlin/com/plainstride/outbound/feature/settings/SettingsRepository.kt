package com.plainstride.outbound.feature.settings

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import com.plainstride.outbound.core.auth.SessionCoordinator
import com.plainstride.outbound.core.designsystem.PlainstrideThemeId
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.network.AccountApiService
import com.plainstride.outbound.core.network.AccountDto
import com.plainstride.outbound.core.network.ApiResult
import com.plainstride.outbound.core.network.PlanningApiService
import com.plainstride.outbound.core.network.UpdateAccountRequest
import com.plainstride.outbound.core.network.UserPreferencesDto
import com.plainstride.outbound.core.network.apiCall

enum class MeasurementSystem(val wireValue: String) { Metric("metric"), Imperial("imperial") }
enum class TemperatureUnit(val wireValue: String) { Celsius("celsius"), Fahrenheit("fahrenheit") }
enum class AppearanceMode(val wireValue: String) { System("system"), Light("light"), Dark("dark") }

data class SettingsPreferences(
    val measurement: MeasurementSystem,
    val temperature: TemperatureUnit,
    val appearance: AppearanceMode,
    val theme: PlainstrideThemeId,
    val saveActivityPhotosToAlbum: Boolean = true,
)

data class MeSummary(
    val phase: String? = null,
    val weeklyMinutes: Int? = null,
    val weeklyDistanceMeters: Double? = null,
    val consistencyPercent: Int? = null,
)

interface SettingsRepository {
    val preferences: Flow<SettingsPreferences>
    suspend fun refresh(): Result<Pair<AccountDto, MeSummary?>>
    suspend fun updateProfile(displayName: String, username: String?, contactEmail: String?): Result<AccountDto>
    suspend fun setMeasurement(value: MeasurementSystem): Result<Unit>
    suspend fun setTemperature(value: TemperatureUnit): Result<Unit>
    suspend fun setAppearance(value: AppearanceMode): Result<Unit>
    suspend fun setTheme(value: PlainstrideThemeId): Result<Unit>
    suspend fun setSaveActivityPhotosToAlbum(value: Boolean): Result<Unit>
}

@Singleton
class DefaultSettingsRepository @Inject constructor(
    private val dataStore: DataStore<Preferences>,
    private val accountApi: AccountApiService,
    private val planningApi: PlanningApiService,
    private val sessions: SessionCoordinator,
) : SettingsRepository {
    private val syncMutex = Mutex()
    private var serverSnapshot: UserPreferencesDto? = null
    private var cachedAccount: AccountDto? = null

    override val preferences: Flow<SettingsPreferences> = dataStore.data.map { values ->
        SettingsPreferences(
            measurement = MeasurementSystem.entries.firstOrNull { it.wireValue == values[MeasurementKey] } ?: deviceMeasurement(),
            temperature = TemperatureUnit.entries.firstOrNull { it.wireValue == values[TemperatureKey] } ?: deviceTemperature(),
            appearance = AppearanceMode.entries.firstOrNull { it.wireValue == values[AppearanceKey] } ?: AppearanceMode.System,
            theme = PlainstrideThemeId.fromSerializedName(values[ThemeKey]),
            saveActivityPhotosToAlbum = values[SaveActivityPhotosKey] ?: true,
        )
    }

    override suspend fun refresh(): Result<Pair<AccountDto, MeSummary?>> {
        val token = sessions.validAccessToken() ?: return Result.failure(SettingsException.SignedOut)
        val account = apiCall { accountApi.currentAccount("Bearer $token") }
        val remotePreferences = apiCall { accountApi.preferences("Bearer $token") }
        val planning = apiCall { planningApi.state("Bearer $token") }
        if (remotePreferences is ApiResult.Success) {
            syncMutex.withLock {
                val localDirty = dataStore.data.first()[DirtyKey] == true
                remotePreferences.value.preferences?.let { remote ->
                    serverSnapshot = remote
                    remote.takeUnless { localDirty }
                }?.let {
                    applyLocal(it)
                } ?: uploadCurrentLocked(token)
            }
        }
        return when (account) {
            is ApiResult.Success -> {
                cachedAccount = account.value
                Result.success(account.value to (planning as? ApiResult.Success)?.value?.toSummary())
            }
            is ApiResult.Failure -> Result.failure(SettingsException.RequestFailed)
        }
    }

    override suspend fun updateProfile(displayName: String, username: String?, contactEmail: String?): Result<AccountDto> {
        val token = sessions.validAccessToken() ?: return Result.failure(SettingsException.SignedOut)
        val request = UpdateAccountRequest(
            username = username?.trim()?.takeIf(String::isNotEmpty),
            displayName = displayName.trim(),
            bio = cachedAccount?.bio,
            contactEmail = contactEmail?.trim()?.takeIf(String::isNotEmpty),
            contactPhone = cachedAccount?.contactPhone,
        )
        return when (val result = apiCall { accountApi.updateAccount("Bearer $token", request) }) {
            is ApiResult.Success -> {
                cachedAccount = result.value
                Result.success(result.value)
            }
            is ApiResult.Failure -> Result.failure(SettingsException.RequestFailed)
        }
    }

    override suspend fun setMeasurement(value: MeasurementSystem) = update(MeasurementKey, value.wireValue)
    override suspend fun setTemperature(value: TemperatureUnit) = update(TemperatureKey, value.wireValue)
    override suspend fun setAppearance(value: AppearanceMode) = update(AppearanceKey, value.wireValue)
    override suspend fun setTheme(value: PlainstrideThemeId) = update(ThemeKey, value.serializedName)
    override suspend fun setSaveActivityPhotosToAlbum(value: Boolean): Result<Unit> {
        dataStore.edit { it[SaveActivityPhotosKey] = value }
        return Result.success(Unit)
    }

    private suspend fun update(key: Preferences.Key<String>, value: String): Result<Unit> {
        dataStore.edit { it[key] = value; it[DirtyKey] = true }
        val token = sessions.validAccessToken() ?: return Result.failure(SettingsException.SignedOut)
        return syncMutex.withLock { uploadCurrentLocked(token) }
    }

    private suspend fun uploadCurrentLocked(token: String): Result<Unit> {
        val local = preferencesSnapshot()
        val base = serverSnapshot ?: UserPreferencesDto()
        val body = base.copy(
            measurementUnitSystem = local.measurement.wireValue,
            temperatureUnit = local.temperature.wireValue,
            appearanceMode = local.appearance.wireValue,
            guideSelection = base.guideSelection.copy(theme = local.theme.serializedName),
        )
        return when (val result = apiCall { accountApi.updatePreferences("Bearer $token", body) }) {
            is ApiResult.Success -> {
                serverSnapshot = result.value.preferences ?: body
                dataStore.edit { it[DirtyKey] = false }
                Result.success(Unit)
            }
            is ApiResult.Failure -> Result.failure(SettingsException.RequestFailed)
        }
    }

    private suspend fun preferencesSnapshot(): SettingsPreferences = preferences.first()

    private suspend fun applyLocal(value: UserPreferencesDto) {
        dataStore.edit {
            it[MeasurementKey] = value.measurementUnitSystem
            it[TemperatureKey] = value.temperatureUnit
            it[AppearanceKey] = value.appearanceMode
            it[ThemeKey] = value.guideSelection.theme
        }
    }

    private fun PlanningState.toSummary() = MeSummary(
        phase = plan?.currentPhase,
        weeklyMinutes = athleteState?.weeklyMinutes,
        weeklyDistanceMeters = athleteState?.weeklyDistanceMeters,
        consistencyPercent = athleteState?.consistencyScore?.times(100)?.toInt()?.coerceIn(0, 100),
    )

    private fun deviceMeasurement() = if (Locale.getDefault().country in setOf("US", "LR", "MM")) MeasurementSystem.Imperial else MeasurementSystem.Metric
    private fun deviceTemperature() = if (Locale.getDefault().country in setOf("US", "BS", "BZ", "KY", "PW")) TemperatureUnit.Fahrenheit else TemperatureUnit.Celsius

    private companion object {
        val MeasurementKey = stringPreferencesKey("measurement_unit_system_v1")
        val TemperatureKey = stringPreferencesKey("temperature_unit_v1")
        val AppearanceKey = stringPreferencesKey("appearance_mode_v1")
        val ThemeKey = stringPreferencesKey("theme_v1")
        val SaveActivityPhotosKey = booleanPreferencesKey("save_activity_photos_to_album_v1")
        val DirtyKey = booleanPreferencesKey("settings_preferences_dirty_v1")
    }
}

sealed class SettingsException : Throwable() {
    data object SignedOut : SettingsException()
    data object RequestFailed : SettingsException()
}
