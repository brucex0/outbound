package run.plainstride.core.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFF1F6B4F),
    onPrimary = Color.White,
    secondary = Color(0xFF53645B),
    background = Color(0xFFF8FAF7),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF18201C),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF83D5AD),
    onPrimary = Color(0xFF003824),
    secondary = Color(0xFFB7CCBF),
    background = Color(0xFF101512),
    surface = Color(0xFF171D19),
    onSurface = Color(0xFFE0E6E1),
)

@Composable
fun PlainstrideTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content,
    )
}
