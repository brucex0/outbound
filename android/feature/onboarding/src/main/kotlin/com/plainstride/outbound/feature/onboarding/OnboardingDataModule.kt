package com.plainstride.outbound.feature.onboarding

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
abstract class OnboardingDataModule {
    @Binds abstract fun onboardingRepository(implementation: DefaultOnboardingRepository): OnboardingRepository
    @Binds abstract fun healthProfileImporter(implementation: HealthConnectProfileImporter): HealthProfileImporter
}
