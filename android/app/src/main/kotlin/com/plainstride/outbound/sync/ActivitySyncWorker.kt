package com.plainstride.outbound.sync

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.time.Duration
import com.plainstride.outbound.core.data.ActivityRepository
import com.plainstride.outbound.core.data.ActivitySyncScheduler

@HiltWorker
class ActivitySyncWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted parameters: WorkerParameters,
    private val activities: ActivityRepository,
) : CoroutineWorker(appContext, parameters) {
    override suspend fun doWork(): Result {
        val accountId = inputData.getString(KEY_ACCOUNT_ID)?.takeIf(String::isNotBlank) ?: return Result.failure()
        val result = activities.synchronize(accountId)
        return when {
            result.failure == "authentication_required" -> Result.failure()
            result.failure != null || result.pending > 0 -> Result.retry()
            else -> Result.success()
        }
    }

    companion object {
        const val KEY_ACCOUNT_ID = "account_id"
    }
}

class WorkManagerActivitySyncScheduler(private val context: Context) : ActivitySyncScheduler {
    override fun schedule(accountId: String) {
        if (accountId.isBlank()) return
        val request = OneTimeWorkRequestBuilder<ActivitySyncWorker>()
            .setInputData(workDataOf(ActivitySyncWorker.KEY_ACCOUNT_ID to accountId))
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, Duration.ofSeconds(30))
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            "activity-sync-$accountId",
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            request,
        )
    }
}
