package run.plainstride.feature.social

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module @InstallIn(SingletonComponent::class)
abstract class SocialDataModule {
    @Binds @Singleton abstract fun bindSocialRepository(implementation: OfflineFirstSocialRepository): SocialRepository
}
