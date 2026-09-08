package com.plainstride.outbound.feature.livecoach

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import com.plainstride.outbound.feature.livecoach.network.DefaultLiveCoachRepository
import com.plainstride.outbound.feature.livecoach.network.LiveCoachRepository
import com.plainstride.outbound.feature.livecoach.audio.FixedAudioPackStore
import com.plainstride.outbound.feature.livecoach.audio.VerifiedAudioPackStore
import com.plainstride.outbound.feature.livecoach.audio.AndroidCoachAudioOutput
import com.plainstride.outbound.feature.livecoach.audio.CoachAudioOutput
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class LiveCoachModule {
    @Binds @Singleton abstract fun repository(implementation: DefaultLiveCoachRepository): LiveCoachRepository
    @Binds @Singleton abstract fun audioPack(implementation: VerifiedAudioPackStore): FixedAudioPackStore
    @Binds @Singleton abstract fun audioOutput(implementation: AndroidCoachAudioOutput): CoachAudioOutput
    @Binds @Singleton abstract fun preferences(implementation: DataStoreLiveCoachPreferences): LiveCoachPreferencesRepository
}
