package run.plainstride.feature.onboarding

import javax.inject.Inject
import run.plainstride.feature.health.HealthConnectRepository
import run.plainstride.feature.health.HealthConnectResult

interface HealthProfileImporter { suspend fun import(accountId:String): Result<ImportedHealthProfile> }

/** Replaced by the Health Connect implementation when that platform capability is installed. */
class UnavailableHealthProfileImporter @Inject constructor() : HealthProfileImporter {
    override suspend fun import(accountId:String): Result<ImportedHealthProfile> = Result.failure(HealthProfileUnavailableException)
}

class HealthConnectProfileImporter @Inject constructor(private val importer: run.plainstride.feature.health.HealthActivityImporter) : HealthProfileImporter {
    override suspend fun import(accountId:String): Result<ImportedHealthProfile> = when (val result = importer.import(accountId)) {
        is HealthConnectResult.Success -> {
            val sessions = result.value
            Result.success(ImportedHealthProfile(
                trainingProfile = TrainingProfileInput(null, null, null, null),
                recentSessionsPerWeek = (sessions.size / HealthConnectRepository.ONBOARDING_IMPORT_WEEKS.toDouble()).toInt().coerceAtLeast(0),
                comfortableMinutes = sessions.map { java.time.Duration.between(it.startTime, it.endTime).toMinutes().toInt() }.sorted().let { values -> values.getOrNull(values.size / 2) },
            ))
        }
        is HealthConnectResult.PermissionRequired -> Result.failure(HealthProfileUnavailableException)
        is HealthConnectResult.Unavailable -> Result.failure(HealthProfileUnavailableException)
        is HealthConnectResult.Failure -> Result.failure(HealthProfileUnavailableException)
    }
}

data object HealthProfileUnavailableException : Exception()
