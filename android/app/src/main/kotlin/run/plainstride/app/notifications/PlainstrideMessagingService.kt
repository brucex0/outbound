package run.plainstride.app.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import run.plainstride.app.MainActivity
import run.plainstride.app.R

class PlainstrideMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        getSharedPreferences(PREFERENCES, MODE_PRIVATE).edit().putString(TOKEN, token).apply()
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val type = message.data["type"]?.take(48) ?: return
        val objectId = message.data["objectId"]?.take(160).orEmpty()
        val notificationId = message.data["notificationId"]?.take(160).orEmpty()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL_SOCIAL, getString(R.string.notification_channel_social), NotificationManager.IMPORTANCE_DEFAULT))
        val destination = message.data["targetType"]?.takeIf { it in setOf("invitation","event") } ?: when (type) {
            "connectionRequest", "connectionAccepted" -> "connections"
            "cheer", "comment" -> "activity"
            "runInvitation" -> "invitation"
            "invitationAccepted", "activityEventJoined" -> "event"
            "circleInvitation" -> "invitation"
            "circleInvitationAccepted", "circleCheer", "circleWeeklyGoalCompleted", "circleOwnershipTransferred" -> "circle"
            "groupRunInvitation", "groupRunStarted", "groupRunUpdated" -> "group"
            "liveShare", "liveShareStarted", "liveShareUpdated" -> "live"
            else -> "inbox"
        }
        val intent = Intent(this, MainActivity::class.java).apply {
            data = Uri.Builder().scheme("plainstride").authority("notification").appendPath(destination).appendQueryParameter("id", objectId).appendQueryParameter("notification", notificationId).build()
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pending = PendingIntent.getActivity(this, notificationId.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        if (message.notification == null) return
        manager.notify(notificationId.hashCode(), NotificationCompat.Builder(this, CHANNEL_SOCIAL).setSmallIcon(R.drawable.ic_notification).setContentTitle(getString(R.string.app_name)).setContentText(getString(R.string.notification_generic_body)).setVisibility(NotificationCompat.VISIBILITY_PRIVATE).setAutoCancel(true).setContentIntent(pending).build())
    }

    companion object { const val PREFERENCES="push_registration"; const val TOKEN="fcm_token"; const val CHANNEL_SOCIAL="social" }
}
