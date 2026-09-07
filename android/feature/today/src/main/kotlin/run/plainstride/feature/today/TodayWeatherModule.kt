package run.plainstride.feature.today

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
abstract class TodayWeatherModule {
    @Binds
    abstract fun weatherPolicy(implementation: DefaultTodayWeatherPolicy): TodayWeatherPolicy
}
