package run.plainstride.core.assistant

import java.util.Locale

enum class VoiceSport { Run, Bike, Walk, Hike, Swim }
sealed interface ActivityVoiceCommand {
    val sport: VoiceSport
    data class Freestyle(override val sport: VoiceSport) : ActivityVoiceCommand
    data class Distance(override val sport: VoiceSport, val meters: Double) : ActivityVoiceCommand
    data class Duration(override val sport: VoiceSport, val seconds: Int) : ActivityVoiceCommand
}

object ActivityVoiceCommandParser {
    fun parse(transcript: String, locale: Locale = Locale.getDefault()): ActivityVoiceCommand? {
        val text = normalize(transcript)
        val launch = listOf("start", "begin", "go for", "set up", "do a", "inicia", "iniciar", "empieza", "prepara", "开始", "准备", "来一场").any(text::contains)
        val sport = when {
            listOf("bike", "biking", "cycle", "cycling", "ride", "bici", "bicicleta", "ciclismo", "骑行", "骑车").any(text::contains) -> VoiceSport.Bike
            listOf("walk", "walking", "caminar", "paseo", "走路", "步行").any(text::contains) -> VoiceSport.Walk
            listOf("hike", "hiking", "senderismo", "徒步").any(text::contains) -> VoiceSport.Hike
            listOf("swim", "swimming", "nadar", "natación", "游泳").any(text::contains) -> VoiceSport.Swim
            listOf("run", "running", "jog", "correr", "carrera", "跑步", "跑").any(text::contains) -> VoiceSport.Run
            launch && distance(text, locale) != null -> VoiceSport.Run
            else -> return null
        }
        distance(text, locale)?.let { return ActivityVoiceCommand.Distance(sport, it) }
        duration(text)?.let { return ActivityVoiceCommand.Duration(sport, it) }
        return ActivityVoiceCommand.Freestyle(sport).takeIf { launch }
    }

    fun hints(locale: Locale): List<String> = when (locale.language) {
        "es" -> listOf("inicia una carrera", "prepara una carrera de 5 kilómetros", "correr 30 minutos", "inicia un paseo en bicicleta")
        "zh" -> listOf("开始跑步", "准备五公里跑步", "跑三十分钟", "开始骑行")
        else -> listOf("start a run", "start a 5K run", "start a 10K run", "run for 30 minutes", "bike for 45 minutes")
    }

    private fun distance(text: String, locale: Locale): Double? {
        val match = Regex("(\\d+(?:[.,]\\d+)?)\\s*(k|km|kilometer|kilometers|kilómetro|kilómetros|公里|mile|miles|milla|millas|英里)").find(text) ?: return null
        val value = match.groupValues[1].replace(',', '.').toDoubleOrNull()?.takeIf { it > 0 } ?: return null
        val unit = match.groupValues[2]
        val meters = if (unit in listOf("mile", "miles", "milla", "millas", "英里")) value * 1609.344 else value * 1000
        return meters.takeIf { it <= 500_000 }
    }

    private fun duration(text: String): Int? {
        val match = Regex("(\\d+)\\s*(minute|minutes|minuto|minutos|分钟|hour|hours|hora|horas|小时)").find(text) ?: return null
        val value = match.groupValues[1].toIntOrNull()?.takeIf { it > 0 } ?: return null
        val seconds = value * if (match.groupValues[2] in listOf("hour", "hours", "hora", "horas", "小时")) 3600 else 60
        return seconds.takeIf { it <= 24 * 3600 }
    }

    private fun normalize(value: String): String {
        var text = value.lowercase().replace('-', ' ')
        val replacements = mapOf(
            "half an hour" to "30 minutes", "half hour" to "30 minutes", "an hour" to "1 hour", "one hour" to "1 hour",
            "media hora" to "30 minutos", "una hora" to "1 hora", "forty five" to "45", "thirty" to "30", "twenty" to "20",
            "ten" to "10", "five" to "5", "three" to "3", "cuarenta y cinco" to "45", "treinta" to "30", "veinte" to "20",
            "diez" to "10", "cinco" to "5", "tres" to "3", "三十" to "30", "二十" to "20", "五" to "5", "三" to "3",
            " kay" to " k", " kays" to " k",
        )
        replacements.forEach { (from, to) -> text = text.replace(from, to) }
        return text.replace(Regex("\\s+"), " ").trim()
    }
}

sealed interface LiveVoiceCommand {
    data object PauseWorkout : LiveVoiceCommand
    data object ResumeWorkout : LiveVoiceCommand
    data object FinishWorkout : LiveVoiceCommand
    data object ReadStats : LiveVoiceCommand
    data object PauseMusic : LiveVoiceCommand
    data object ResumeMusic : LiveVoiceCommand
    data object NextTrack : LiveVoiceCommand
}

object LiveVoiceCommandParser {
    fun parse(transcript: String): LiveVoiceCommand? {
        val text = transcript.lowercase().trim()
        return when {
            any(text, "pause music", "pausa la música", "暂停音乐") -> LiveVoiceCommand.PauseMusic
            any(text, "resume music", "play music", "reanuda la música", "播放音乐", "继续音乐") -> LiveVoiceCommand.ResumeMusic
            any(text, "next song", "skip song", "siguiente canción", "下一首") -> LiveVoiceCommand.NextTrack
            any(text, "pause workout", "pause run", "pausa el entrenamiento", "暂停运动", "暂停跑步") -> LiveVoiceCommand.PauseWorkout
            any(text, "resume workout", "resume run", "reanuda el entrenamiento", "继续运动", "继续跑步") -> LiveVoiceCommand.ResumeWorkout
            any(text, "finish workout", "end run", "termina el entrenamiento", "结束运动", "结束跑步") -> LiveVoiceCommand.FinishWorkout
            any(text, "my stats", "how am i doing", "mis estadísticas", "我的数据", "跑得怎么样") -> LiveVoiceCommand.ReadStats
            else -> null
        }
    }
    private fun any(value: String, vararg phrases: String) = phrases.any(value::contains)
}

interface LiveWorkoutVoiceActions {
    suspend fun pauseWorkout()
    suspend fun resumeWorkout()
    /** Must present the normal finish confirmation; voice never saves or discards directly. */
    suspend fun requestFinishWorkout()
    suspend fun speakCurrentStats()
    suspend fun pauseMusic()
    suspend fun resumeMusic()
    suspend fun skipMusic()
}

class LiveVoiceCommandHandler(private val actions: LiveWorkoutVoiceActions) {
    suspend fun handle(command: LiveVoiceCommand) = when (command) {
        LiveVoiceCommand.PauseWorkout -> actions.pauseWorkout()
        LiveVoiceCommand.ResumeWorkout -> actions.resumeWorkout()
        LiveVoiceCommand.FinishWorkout -> actions.requestFinishWorkout()
        LiveVoiceCommand.ReadStats -> actions.speakCurrentStats()
        LiveVoiceCommand.PauseMusic -> actions.pauseMusic()
        LiveVoiceCommand.ResumeMusic -> actions.resumeMusic()
        LiveVoiceCommand.NextTrack -> actions.skipMusic()
    }
}
