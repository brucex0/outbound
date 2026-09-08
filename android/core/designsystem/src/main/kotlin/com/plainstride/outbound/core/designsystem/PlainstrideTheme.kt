package com.plainstride.outbound.core.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/** Stable theme identifiers shared with iOS and account preferences. */
enum class PlainstrideThemeId(val serializedName: String) {
    VictoryGold("victoryGold"), Indigo("indigo"), Ocean("ocean"), Forest("forest"),
    Rose("rose"), Aurora("aurora"), ElectricLime("electricLime"), NeonPulse("neonPulse");

    companion object {
        fun fromSerializedName(value: String?): PlainstrideThemeId = when (value) {
            "sunset", "solarFlare" -> VictoryGold
            else -> entries.firstOrNull { it.serializedName == value } ?: VictoryGold
        }
    }
}

@Immutable
data class PlainstrideThemeColors(
    val accent: Color,
    val secondary: Color,
    val action: Color,
    val heroGradient: List<Color>,
    val glow: Color,
    val heroForeground: Color,
)

private data class AdaptiveThemeColors(val light: PlainstrideThemeColors, val dark: PlainstrideThemeColors)

private fun colors(
    accent: Color, secondary: Color, action: Color, heroStart: Color,
    heroMiddle: Color = accent, heroEnd: Color = secondary, heroForeground: Color = Color.White,
) = PlainstrideThemeColors(accent, secondary, action, listOf(heroStart, heroMiddle, heroEnd), secondary.copy(alpha = 0.34f), heroForeground)

private val ThemePalettes = mapOf(
    PlainstrideThemeId.VictoryGold to AdaptiveThemeColors(
        colors(Color(0xFFD18200), Color(0xFFFFC41F), Color(0xFF8C5200), Color(0xFFFFF099), heroEnd = Color(0xFFE88C00), heroForeground = Color(0xFF291A03)),
        colors(Color(0xFFFFB821), Color(0xFFFFD659), Color(0xFFC27A08), Color(0xFFE8B32E), heroEnd = Color(0xFFBA6900), heroForeground = Color(0xFF211400))),
    PlainstrideThemeId.Indigo to AdaptiveThemeColors(
        colors(Color(0xFF4740C7), Color(0xFF8061EB), Color(0xFF1F9485), Color(0xFF2E2994)),
        colors(Color(0xFF857AFF), Color(0xFFB39EFF), Color(0xFF3BC2AD), Color(0xFF383085))),
    PlainstrideThemeId.Ocean to AdaptiveThemeColors(
        colors(Color(0xFF087DBF), Color(0xFF00ABB3), Color(0xFF056EB3), Color(0xFF034D9C)),
        colors(Color(0xFF38ADF2), Color(0xFF2ED6E0), Color(0xFF269CE6), Color(0xFF053D7A))),
    PlainstrideThemeId.Forest to AdaptiveThemeColors(
        colors(Color(0xFF128259), Color(0xFF5EA82E), Color(0xFF0A6E4A), Color(0xFF084F3D)),
        colors(Color(0xFF3DB87D), Color(0xFF8FD657), Color(0xFF2EA169), Color(0xFF084230))),
    PlainstrideThemeId.Rose to AdaptiveThemeColors(
        colors(Color(0xFFC7336E), Color(0xFFF06E7A), Color(0xFFAD2159), Color(0xFF911A52)),
        colors(Color(0xFFFF639C), Color(0xFFFF91A3), Color(0xFFE3477D), Color(0xFF751240))),
    PlainstrideThemeId.Aurora to AdaptiveThemeColors(
        colors(Color(0xFF0DABAB), Color(0xFFA33BDE), Color(0xFF0A7A96), Color(0xFFA33BDE), Color(0xFF0AB8B3), Color(0xFFE859B0)),
        colors(Color(0xFF3BE0CF), Color(0xFFC470FF), Color(0xFF26ABBF), Color(0xFFC470FF), Color(0xFF0F9C9E), Color(0xFFC43D96))),
    PlainstrideThemeId.ElectricLime to AdaptiveThemeColors(
        colors(Color(0xFF6BB80A), Color(0xFF089E63), Color(0xFF057345), Color(0xFFBFF02E), heroForeground = Color(0xFF291A03)),
        colors(Color(0xFFA6F22E), Color(0xFF2ED18A), Color(0xFF1FA661), Color(0xFF96C91A), heroForeground = Color(0xFF211400))),
    PlainstrideThemeId.NeonPulse to AdaptiveThemeColors(
        colors(Color(0xFFD614AD), Color(0xFF662EF0), Color(0xFF871AC7), Color(0xFFFF2EB3)),
        colors(Color(0xFFFF40D4), Color(0xFF9466FF), Color(0xFFB542F5), Color(0xFFD61799))),
)

val LocalPlainstrideThemeColors = staticCompositionLocalOf { ThemePalettes.getValue(PlainstrideThemeId.VictoryGold).dark }

fun plainstrideThemeColors(theme: PlainstrideThemeId, darkTheme: Boolean): PlainstrideThemeColors {
    val palette = ThemePalettes.getValue(theme)
    return if (darkTheme) palette.dark else palette.light
}

@Composable
fun PlainstrideTheme(
    theme: PlainstrideThemeId = PlainstrideThemeId.VictoryGold,
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val brand = plainstrideThemeColors(theme, darkTheme)
    val materialColors = if (darkTheme) {
        darkColorScheme(primary = brand.action, onPrimary = brand.heroForeground, secondary = brand.secondary, tertiary = brand.accent,
            background = Color(0xFF101512), surface = Color(0xFF171D19), onSurface = Color(0xFFE0E6E1))
    } else {
        lightColorScheme(primary = brand.action, onPrimary = brand.heroForeground, secondary = brand.secondary, tertiary = brand.accent,
            background = Color(0xFFF8FAF7), surface = Color.White, onSurface = Color(0xFF18201C))
    }
    CompositionLocalProvider(LocalPlainstrideThemeColors provides brand) {
        MaterialTheme(colorScheme = materialColors, content = content)
    }
}
