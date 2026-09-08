package com.plainstride.outbound.feature.settings

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
abstract class SettingsDataModule {
    @Binds abstract fun settingsRepository(implementation: DefaultSettingsRepository): SettingsRepository
}
