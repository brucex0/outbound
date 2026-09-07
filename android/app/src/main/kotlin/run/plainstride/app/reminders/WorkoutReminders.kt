package run.plainstride.app.reminders

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import dagger.hilt.android.AndroidEntryPoint
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.Duration
import java.time.ZonedDateTime
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import run.plainstride.app.MainActivity
import run.plainstride.app.R

class WorkoutReminderScheduler @Inject constructor(@ApplicationContext private val context: Context) {
    fun schedule(hour: Int, minute: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(ENABLED, true).putInt(HOUR, hour).putInt(MINUTE, minute).apply()
        val trigger = next(hour, minute)
        val alarm = context.getSystemService(AlarmManager::class.java)
        if (Build.VERSION.SDK_INT < 31 || alarm.canScheduleExactAlarms()) {
            alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, trigger.toInstant().toEpochMilli(), pending(context))
        } else {
            val delay = Duration.between(ZonedDateTime.now(), trigger).toMillis().coerceAtLeast(0)
            WorkManager.getInstance(context).enqueueUniqueWork(WORK, ExistingWorkPolicy.REPLACE, OneTimeWorkRequestBuilder<WorkoutReminderWorker>().setInitialDelay(delay, TimeUnit.MILLISECONDS).build())
        }
    }

    fun cancel() {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(ENABLED, false).apply()
        context.getSystemService(AlarmManager::class.java).cancel(pending(context))
        WorkManager.getInstance(context).cancelUniqueWork(WORK)
    }

    fun restore() {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (prefs.getBoolean(ENABLED, false)) schedule(prefs.getInt(HOUR, 7), prefs.getInt(MINUTE, 0))
    }

    private fun next(hour: Int, minute: Int): ZonedDateTime = ZonedDateTime.now().let { now ->
        now.withHour(hour).withMinute(minute).withSecond(0).withNano(0).let { if (it.isAfter(now)) it else it.plusDays(1) }
    }

    companion object {
        const val PREFS = "workout_reminder"
        const val ENABLED = "enabled"
        const val HOUR = "hour"
        const val MINUTE = "minute"
        const val WORK = "daily_workout_reminder"
        fun pending(context: Context) = PendingIntent.getBroadcast(context, 70, Intent(context, WorkoutReminderReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
}

@AndroidEntryPoint
class WorkoutReminderReceiver : BroadcastReceiver() {
    @Inject lateinit var scheduler: WorkoutReminderScheduler
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_TIMEZONE_CHANGED || intent.action == Intent.ACTION_TIME_CHANGED) scheduler.restore()
        else { showReminder(context); scheduler.restore() }
    }
}

@HiltWorker
class WorkoutReminderWorker @AssistedInject constructor(@Assisted context: Context, @Assisted parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    override suspend fun doWork(): Result { showReminder(applicationContext); WorkoutReminderScheduler(applicationContext).restore(); return Result.success() }
}

private fun showReminder(context: Context) {
    val manager = context.getSystemService(NotificationManager::class.java)
    manager.createNotificationChannel(NotificationChannel("workout_reminders", context.getString(R.string.reminder_channel), NotificationManager.IMPORTANCE_DEFAULT))
    val open = PendingIntent.getActivity(context, 71, Intent(context, MainActivity::class.java).apply { data = android.net.Uri.parse("plainstride://notification/today"); flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    if (NotificationManagerCompat.from(context).areNotificationsEnabled()) manager.notify(71, NotificationCompat.Builder(context, "workout_reminders").setSmallIcon(R.drawable.ic_notification).setContentTitle(context.getString(R.string.reminder_title)).setContentText(context.getString(R.string.reminder_body)).setContentIntent(open).setAutoCancel(true).build())
}
