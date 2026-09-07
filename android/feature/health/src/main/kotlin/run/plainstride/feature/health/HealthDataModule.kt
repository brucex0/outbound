package run.plainstride.feature.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import run.plainstride.core.analytics.ProductAnalytics
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object HealthDataModule {
    @Provides
    @Singleton
    fun healthConnectRepository(
        @ApplicationContext context: Context,
        analytics: ProductAnalytics,
    ): HealthConnectRepository {
        val client = if (HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE) {
            HealthConnectClient.getOrCreate(context)
        } else null
        return DefaultHealthConnectRepository(context, analytics, client)
    }
}
