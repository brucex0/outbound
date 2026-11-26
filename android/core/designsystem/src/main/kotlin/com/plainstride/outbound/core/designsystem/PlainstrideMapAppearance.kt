package com.plainstride.outbound.core.designsystem

import com.google.android.gms.maps.GoogleMapOptions
import com.google.maps.android.compose.ComposeMapColorScheme

/** Only the basemap stays light; Compose controls keep the selected app theme. */
object PlainstrideMapAppearance {
    val colorScheme = ComposeMapColorScheme.LIGHT

    fun options(): GoogleMapOptions = GoogleMapOptions().mapColorScheme(colorScheme.value)
}
