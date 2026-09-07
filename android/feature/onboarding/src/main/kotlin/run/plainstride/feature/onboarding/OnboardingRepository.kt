package run.plainstride.feature.onboarding

/** Network/data boundary. Implementations must scope all reads and writes to [OnboardingAccount.id]. */
interface OnboardingRepository {
    suspend fun currentAccount(): OnboardingAccount
    suspend fun updateIdentity(displayName: String, username: String, contactEmail: String?): Result<OnboardingAccount>
    suspend fun updateTrainingProfile(input: TrainingProfileInput): Result<Unit>
    suspend fun importHealthProfile(): Result<ImportedHealthProfile>
    suspend fun completeOnboarding(input: RunnerProfileInput): Result<Unit>
}
