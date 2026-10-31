package com.plainstride.outbound.feature.social

import android.app.Application
import android.content.Context
import androidx.test.runner.AndroidJUnitRunner
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.testing.HiltTestApplication
import dagger.hilt.components.SingletonComponent
import javax.inject.Named
import okhttp3.OkHttpClient

class ProfileTestRunner : AndroidJUnitRunner() {
    override fun newApplication(cl: ClassLoader, className: String, context: Context): Application =
        super.newApplication(cl, HiltTestApplication::class.java.name, context)
}

// The real avatar still renders; null fixture URLs avoid all network requests.
@Module
@InstallIn(SingletonComponent::class)
object ProfileTestNetworkModule {
    @Provides fun httpClient(): OkHttpClient = OkHttpClient()
    @Provides @Named("apiBaseUrl") fun apiBaseUrl(): String = "https://example.invalid/"
}
