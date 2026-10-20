package com.jackwallner.time.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.time.R
import com.jackwallner.time.model.RunStatus

/**
 * Every colour in one place, from iOS `Theme`. Paper and ink at rest; colour
 * only where it carries meaning (on track, behind, late), and a dark surface
 * while a routine runs.
 */
@Immutable
data class Palette(
    val background: Color,
    val surface: Color,
    val raised: Color,
    val ink: Color,
    val secondary: Color,
    val hairline: Color,
    /** Text and glyphs drawn on an ink-filled control. */
    val inkInverse: Color,
    val onTrack: Color,
    val behind: Color,
    val late: Color,
    val isDark: Boolean,
) {
    fun color(status: RunStatus): Color = when (status) {
        is RunStatus.Ahead, RunStatus.OnTrack -> onTrack
        is RunStatus.Behind -> if (status.minutes >= 5) late else behind
    }

    companion object {
        private fun rgb(r: Double, g: Double, b: Double) = Color(r.toFloat(), g.toFloat(), b.toFloat())

        val light = Palette(
            background = rgb(0.965, 0.961, 0.945),
            surface = rgb(1.0, 1.0, 1.0),
            raised = rgb(0.935, 0.930, 0.912),
            ink = rgb(0.071, 0.078, 0.090),
            secondary = rgb(0.43, 0.44, 0.46),
            hairline = rgb(0.878, 0.870, 0.847),
            inkInverse = rgb(0.980, 0.975, 0.960),
            onTrack = rgb(0.08, 0.43, 0.29),
            behind = rgb(0.57, 0.31, 0.06),
            late = rgb(0.72, 0.17, 0.16),
            isDark = false,
        )

        val dark = Palette(
            background = rgb(0.043, 0.047, 0.055),
            surface = rgb(0.098, 0.106, 0.118),
            raised = rgb(0.150, 0.158, 0.172),
            ink = rgb(0.965, 0.961, 0.945),
            secondary = rgb(0.60, 0.62, 0.65),
            hairline = rgb(0.190, 0.200, 0.215),
            inkInverse = rgb(0.060, 0.065, 0.075),
            onTrack = rgb(0.16, 0.78, 0.52),
            behind = rgb(1.00, 0.62, 0.20),
            late = rgb(1.00, 0.36, 0.33),
            isDark = true,
        )

        /** The time your guesses leave out. */
        val gap = rgb(1.00, 0.62, 0.20)

        /** The run screen's canvas, always dark. */
        val night = rgb(0.035, 0.040, 0.050)
    }
}

object Metrics {
    val radius = 28.dp
    val margin = 20.dp
}

val LocalPalette = staticCompositionLocalOf { Palette.light }

/**
 * Nunito stands in for SF Rounded: a rounded variable sans bundled under the
 * OFL (assets/licenses). Weights are set on the variable axis.
 */
@OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
object Fonts {
    private val weights = listOf(FontWeight.Normal, FontWeight.Medium, FontWeight.SemiBold, FontWeight.Bold, FontWeight.ExtraBold, FontWeight.Black)

    val rounded = FontFamily(
        weights.map { Font(R.font.nunito, it, FontStyle.Normal, variationSettings = FontVariation.Settings(FontVariation.weight(it.weight))) },
    )
}

/** iOS text styles at their default sizes, in the rounded face. */
object Type {
    fun of(size: TextUnit, weight: FontWeight = FontWeight.Normal, tabular: Boolean = false, strike: Boolean = false) = TextStyle(
        fontFamily = Fonts.rounded,
        fontSize = size,
        fontWeight = weight,
        lineHeight = (size.value * 1.22f).sp,
        fontFeatureSettings = if (tabular) "tnum" else null,
        textDecoration = if (strike) TextDecoration.LineThrough else null,
    )

    fun display(size: Int, weight: FontWeight = FontWeight.ExtraBold, tabular: Boolean = false) =
        of(size.sp, weight, tabular).copy(lineHeight = (size * 1.08f).sp, letterSpacing = (-0.02f * size).sp)

    fun largeTitle(weight: FontWeight = FontWeight.Bold) = of(34.sp, weight)
    fun title(weight: FontWeight = FontWeight.Bold) = of(28.sp, weight)
    fun title2(weight: FontWeight = FontWeight.Bold) = of(22.sp, weight)
    fun title3(weight: FontWeight = FontWeight.SemiBold) = of(20.sp, weight)
    fun headline() = of(17.sp, FontWeight.Bold)
    fun body(weight: FontWeight = FontWeight.Normal) = of(17.sp, weight)
    fun subheadline(weight: FontWeight = FontWeight.Normal, tabular: Boolean = false) = of(15.sp, weight, tabular)
    fun footnote(weight: FontWeight = FontWeight.Normal, tabular: Boolean = false) = of(13.sp, weight, tabular)
    fun caption(weight: FontWeight = FontWeight.Normal) = of(12.sp, weight)
    fun caption2(weight: FontWeight = FontWeight.Normal) = of(11.sp, weight)
}

@Composable
fun ShoesOnTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val palette = if (dark) Palette.dark else Palette.light
    val scheme = if (dark) {
        darkColorScheme(primary = palette.ink, onPrimary = palette.inkInverse, background = palette.background, surface = palette.surface, onSurface = palette.ink, onBackground = palette.ink, error = palette.late)
    } else {
        lightColorScheme(primary = palette.ink, onPrimary = palette.inkInverse, background = palette.background, surface = palette.surface, onSurface = palette.ink, onBackground = palette.ink, error = palette.late)
    }
    CompositionLocalProvider(LocalPalette provides palette) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
