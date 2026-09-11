package com.plainstride.outbound.reminders

import android.content.Context
import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics

@HiltViewModel
class ReminderViewModel @Inject constructor(@ApplicationContext context: Context, private val scheduler: WorkoutReminderScheduler, private val analytics: ProductAnalytics) : ViewModel() {
    private val preferences = context.getSharedPreferences(WorkoutReminderScheduler.PREFS, Context.MODE_PRIVATE)
    init { scheduler.enableByDefault() }
    private val mutableEnabled = MutableStateFlow(preferences.getBoolean(WorkoutReminderScheduler.ENABLED, true))
    val enabled = mutableEnabled.asStateFlow()
    private val mutableTime = MutableStateFlow(preferences.getInt(WorkoutReminderScheduler.HOUR,7) to preferences.getInt(WorkoutReminderScheduler.MINUTE,0));val time=mutableTime.asStateFlow()
    fun setEnabled(enabled: Boolean) { if (enabled) scheduler.schedule(mutableTime.value.first,mutableTime.value.second) else scheduler.cancel(); mutableEnabled.value = enabled; analytics.record(AnalyticsEvent("workout_reminder_changed", mapOf(AnalyticsProperty.Enabled to enabled))) }
    fun setTime(hour:Int,minute:Int){mutableTime.value=hour to minute;if(mutableEnabled.value)scheduler.schedule(hour,minute);analytics.record(AnalyticsEvent("workout_reminder_time_changed"))}
    fun sendDebugTest() { scheduler.scheduleDebugTest(); analytics.record(AnalyticsEvent("workout_reminder_debug_test")) }
}
