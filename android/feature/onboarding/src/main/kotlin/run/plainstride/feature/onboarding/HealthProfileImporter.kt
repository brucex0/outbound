package run.plainstride.feature.onboarding

import javax.inject.Inject

interface HealthProfileImporter { suspend fun import(): Result<ImportedHealthProfile> }

/** Replaced by the Health Connect implementation when that platform capability is installed. */
class UnavailableHealthProfileImporter @Inject constructor() : HealthProfileImporter {
    override suspend fun import(): Result<ImportedHealthProfile> = Result.failure(HealthProfileUnavailableException)
}

data object HealthProfileUnavailableException : Exception()
