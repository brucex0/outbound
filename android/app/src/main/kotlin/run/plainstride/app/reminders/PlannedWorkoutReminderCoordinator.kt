package run.plainstride.app.reminders

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.LocalDate
import java.time.LocalDateTime
import javax.inject.Inject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import run.plainstride.feature.today.CachedResource
import run.plainstride.feature.today.TodayRepository

/** Keeps the one local reminder aligned with the next incomplete planned workout. */
class PlannedWorkoutReminderCoordinator @Inject constructor(
    @ApplicationContext private val context: Context,
    private val repository: TodayRepository,
    private val scheduler: WorkoutReminderScheduler,
) {
    private var observation: Job? = null

    fun observe(scope: CoroutineScope, accountId: String, localeTag: String) {
        observation?.cancel()
        observation = scope.launch {
            repository.observePlanning(accountId, localeTag).collectLatest { resource ->
                val preferences = context.getSharedPreferences(WorkoutReminderScheduler.PREFS, Context.MODE_PRIVATE)
                if (!preferences.getBoolean(WorkoutReminderScheduler.ENABLED, false)) return@collectLatest
                val hour = preferences.getInt(WorkoutReminderScheduler.HOUR, 7)
                val minute = preferences.getInt(WorkoutReminderScheduler.MINUTE, 0)
                val now = LocalDateTime.now()
                val plan = (resource as? CachedResource.Available)?.value ?: return@collectLatest
                val workout = (listOfNotNull(plan.today) + plan.upcoming).firstOrNull {
                    it.status != "completed" && runCatching {
                        LocalDate.parse(it.scheduledDate).atTime(hour, minute).isAfter(now)
                    }.getOrDefault(false)
                }
                if (workout == null) scheduler.cancel()
                else scheduler.schedule(hour, minute, LocalDate.parse(workout.scheduledDate), workout.id)
            }
        }
    }
}
