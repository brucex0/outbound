package run.plainstride.core.model

enum class AppEnvironment { Development, Staging, Production }

interface Clock { fun nowEpochMilliseconds(): Long }

object SystemClock : Clock {
    override fun nowEpochMilliseconds(): Long = System.currentTimeMillis()
}

interface FeatureFlags { val debugIdentityEnabled: Boolean }

data class StaticFeatureFlags(
    override val debugIdentityEnabled: Boolean,
) : FeatureFlags

enum class AppLocale(val apiValue: String) {
    English("en"),
    Spanish("es"),
    SimplifiedChinese("zh-Hans"),
}
