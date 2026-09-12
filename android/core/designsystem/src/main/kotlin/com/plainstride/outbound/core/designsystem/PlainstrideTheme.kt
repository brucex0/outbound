package com.plainstride.outbound.core.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver

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
        val background = Color(0xFF101512)
        val surface = Color(0xFF171D19)
        val onSurface = Color(0xFFE0E6E1)
        darkColorScheme(
            primary = brand.action,
            onPrimary = brand.heroForeground,
            primaryContainer = brand.accent.copy(alpha = .28f).compositeOver(background),
            onPrimaryContainer = brand.accent,
            secondary = brand.secondary,
            secondaryContainer = brand.secondary.copy(alpha = .20f).compositeOver(background),
            onSecondaryContainer = brand.secondary,
            tertiary = brand.accent,
            tertiaryContainer = brand.accent.copy(alpha = .20f).compositeOver(background),
            onTertiaryContainer = brand.accent,
            background = background,
            onBackground = onSurface,
            surface = surface,
            onSurface = onSurface,
            surfaceVariant = Color(0xFF29312C),
            onSurfaceVariant = Color(0xFFBEC8C0),
            inverseSurface = Color(0xFFE0E6E1),
            inverseOnSurface = Color(0xFF28312B),
            outline = Color(0xFF89948C),
            outlineVariant = Color(0xFF3F4942),
            scrim = Color.Black,
            surfaceBright = Color(0xFF353C37),
            surfaceDim = background,
            surfaceContainerLowest = Color(0xFF0B100D),
            surfaceContainerLow = surface,
            surfaceContainer = Color(0xFF1B211D),
            surfaceContainerHigh = Color(0xFF252C27),
            surfaceContainerHighest = Color(0xFF303732),
        )
    } else {
        val background = Color(0xFFF8FAF7)
        val surface = Color.White
        val onSurface = Color(0xFF18201C)
        lightColorScheme(
            primary = brand.action,
            onPrimary = brand.heroForeground,
            primaryContainer = brand.accent.copy(alpha = .16f).compositeOver(background),
            onPrimaryContainer = brand.action,
            secondary = brand.secondary,
            secondaryContainer = brand.secondary.copy(alpha = .12f).compositeOver(background),
            onSecondaryContainer = Color(0xFF18201C),
            tertiary = brand.accent,
            tertiaryContainer = brand.accent.copy(alpha = .12f).compositeOver(background),
            onTertiaryContainer = Color(0xFF18201C),
            background = background,
            onBackground = onSurface,
            surface = surface,
            onSurface = onSurface,
            surfaceVariant = Color(0xFFE5ECE6),
            onSurfaceVariant = Color(0xFF465149),
            inverseSurface = Color(0xFF2D3630),
            inverseOnSurface = Color(0xFFEEF3EF),
            outline = Color(0xFF707A72),
            outlineVariant = Color(0xFFBFC8C0),
            scrim = Color.Black,
            surfaceBright = background,
            surfaceDim = Color(0xFFD8DDD8),
            surfaceContainerLowest = surface,
            surfaceContainerLow = Color(0xFFF2F5F1),
            surfaceContainer = Color(0xFFECEFEB),
            surfaceContainerHigh = Color(0xFFE6EAE5),
            surfaceContainerHighest = Color(0xFFE0E4DF),
        )
    }
    CompositionLocalProvider(LocalPlainstrideThemeColors provides brand) {
        MaterialTheme(colorScheme = materialColors) {
            Surface(
                modifier = Modifier.fillMaxSize(),
                color = materialColors.background,
                contentColor = materialColors.onBackground,
                content = content,
            )
        }
    }
}
