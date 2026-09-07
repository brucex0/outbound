package run.plainstride.feature.today

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class TodayDataModule {
    @Binds
    @Singleton
    abstract fun todayRepository(implementation: OfflineFirstTodayRepository): TodayRepository
}
