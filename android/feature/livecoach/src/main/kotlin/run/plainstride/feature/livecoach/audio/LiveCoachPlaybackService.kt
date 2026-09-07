package run.plainstride.feature.livecoach.audio

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import run.plainstride.feature.livecoach.R

@AndroidEntryPoint
class LiveCoachPlaybackService : Service() {
    @Inject lateinit var output: CoachAudioOutput
    override fun onCreate() { super.onCreate(); createChannel() }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> { output.stop(); stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(); return START_NOT_STICKY }
            ACTION_PAUSE -> output.stop()
        }
        startForeground(NOTIFICATION_ID, notification(intent?.action == ACTION_PAUSE))
        return START_STICKY
    }
    override fun onDestroy() { output.stop(); super.onDestroy() }
    override fun onBind(intent: Intent?): IBinder? = null
    private fun createChannel() { getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(CHANNEL_ID, getString(R.string.live_coach_channel_name), NotificationManager.IMPORTANCE_LOW)) }
    private fun notification(paused: Boolean) = NotificationCompat.Builder(this, CHANNEL_ID)
        .setSmallIcon(android.R.drawable.ic_btn_speak_now)
        .setContentTitle(getString(R.string.live_coach_notification_title))
        .setContentText(getString(if (paused) R.string.live_coach_notification_paused else R.string.live_coach_notification_active))
        .setOngoing(!paused)
        .setOnlyAlertOnce(true)
        .addAction(0, getString(if (paused) R.string.live_coach_notification_active else R.string.live_coach_notification_paused), serviceIntent(if (paused) ACTION_START else ACTION_PAUSE, 1))
        .addAction(0, getString(android.R.string.cancel), serviceIntent(ACTION_STOP, 2)).build()
    private fun serviceIntent(action: String, code: Int) = PendingIntent.getService(this, code, Intent(this, LiveCoachPlaybackService::class.java).setAction(action), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    companion object {
        private const val CHANNEL_ID = "live_coach_playback"; private const val NOTIFICATION_ID = 2401
        private const val ACTION_START = "run.plainstride.livecoach.START"; private const val ACTION_PAUSE = "run.plainstride.livecoach.PAUSE"; private const val ACTION_STOP = "run.plainstride.livecoach.STOP"
        fun startIntent(context: Context) = Intent(context, LiveCoachPlaybackService::class.java).setAction(ACTION_START)
        fun pauseIntent(context: Context) = Intent(context, LiveCoachPlaybackService::class.java).setAction(ACTION_PAUSE)
        fun stopIntent(context: Context) = Intent(context, LiveCoachPlaybackService::class.java).setAction(ACTION_STOP)
    }
}
