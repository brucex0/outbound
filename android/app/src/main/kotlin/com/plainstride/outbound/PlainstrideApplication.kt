package com.plainstride.outbound

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import dagger.hilt.android.HiltAndroidApp
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import javax.inject.Inject
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.analytics.FirebaseAnalytics
import com.plainstride.outbound.notifications.PlainstrideMessagingService

@HiltAndroidApp
class PlainstrideApplication : Application(), Configuration.Provider {
    @Inject lateinit var workerFactory: HiltWorkerFactory
    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder().setWorkerFactory(workerFactory).build()
    override fun onCreate() {
        super.onCreate()
        if (FirebaseApp.getApps(this).isEmpty() && BuildConfig.FIREBASE_APPLICATION_ID.isNotBlank() && BuildConfig.FIREBASE_API_KEY.isNotBlank() && BuildConfig.FIREBASE_PROJECT_ID.isNotBlank()) {
            FirebaseApp.initializeApp(this, FirebaseOptions.Builder().setApplicationId(BuildConfig.FIREBASE_APPLICATION_ID).setApiKey(BuildConfig.FIREBASE_API_KEY).setProjectId(BuildConfig.FIREBASE_PROJECT_ID).build())
        }
        runCatching { FirebaseAnalytics.getInstance(this).setAnalyticsCollectionEnabled(false) }
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                PlainstrideMessagingService.CHANNEL_SOCIAL,
                getString(R.string.notification_channel_social),
                NotificationManager.IMPORTANCE_DEFAULT,
            ),
        )
    }
}
