package run.plainstride.feature.livecoach

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import run.plainstride.feature.livecoach.network.DefaultLiveCoachRepository
import run.plainstride.feature.livecoach.network.LiveCoachRepository
import run.plainstride.feature.livecoach.audio.FixedAudioPackStore
import run.plainstride.feature.livecoach.audio.VerifiedAudioPackStore
import run.plainstride.feature.livecoach.audio.AndroidCoachAudioOutput
import run.plainstride.feature.livecoach.audio.CoachAudioOutput
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class LiveCoachModule {
    @Binds @Singleton abstract fun repository(implementation: DefaultLiveCoachRepository): LiveCoachRepository
    @Binds @Singleton abstract fun audioPack(implementation: VerifiedAudioPackStore): FixedAudioPackStore
    @Binds @Singleton abstract fun audioOutput(implementation: AndroidCoachAudioOutput): CoachAudioOutput
    @Binds @Singleton abstract fun preferences(implementation: DataStoreLiveCoachPreferences): LiveCoachPreferencesRepository
}
