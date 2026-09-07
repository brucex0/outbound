package run.plainstride.app.reminders

import android.content.Context
import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import run.plainstride.core.analytics.AnalyticsEvent
import run.plainstride.core.analytics.AnalyticsProperty
import run.plainstride.core.analytics.ProductAnalytics

@HiltViewModel
class ReminderViewModel @Inject constructor(@ApplicationContext context: Context, private val scheduler: WorkoutReminderScheduler, private val analytics: ProductAnalytics) : ViewModel() {
    private val preferences = context.getSharedPreferences(WorkoutReminderScheduler.PREFS, Context.MODE_PRIVATE)
    private val mutableEnabled = MutableStateFlow(preferences.getBoolean(WorkoutReminderScheduler.ENABLED, false))
    val enabled = mutableEnabled.asStateFlow()
    fun setEnabled(enabled: Boolean) { if (enabled) scheduler.schedule(7, 0) else scheduler.cancel(); mutableEnabled.value = enabled; analytics.record(AnalyticsEvent("workout_reminder_changed", mapOf(AnalyticsProperty.Enabled to enabled))) }
}
