# App Themes

## Appearance Mode

- Settings → Appearance offers System, Light, and Dark modes.
- The selection is persisted in `UserDefaults` by `AppearancePreferences` and applied at the app root with SwiftUI's `preferredColorScheme`.
- Dark is the default for people who have not chosen a mode. Saved System, Light, and Dark selections remain respected. Theme colors remain a separate preference and adapt within the selected appearance.

Open this when adding, changing, or applying an app theme or editing theme discovery in Today and Settings.

## Product Rules

- Theme is an app appearance preference, not a companion identity or avatar.
- The permanent entry point is `Settings > Appearance > Theme`. It opens the same appearance chooser used by the Today discovery tip, with mode controls and rich theme previews; do not maintain a second picker presentation.
- Assistant requests such as “change app theme” open that shared appearance chooser directly.
- Today may show a discovery tip up to three times: “Want a different look? Change the mode or pick a theme that feels like you.” Its action opens the appearance chooser directly.
- Keep the list intentionally finite. The current eight themes cover restrained, natural, warm, celebratory, and high-energy personalities without categories or pagination.
- Theme changes apply immediately and persist in `UserDefaults` through `GuideCatalogStore`.

## Current Themes

| Theme | Personality | Palette direction |
| --- | --- | --- |
| Indigo | Confident, polished default | Deep indigo, violet, teal action |
| Ocean | Cool and clear | Cobalt, cyan, blue action |
| Forest | Grounded and outdoorsy | Evergreen, leaf green, green action |
| Rose | Warm and expressive | Berry, coral rose, deep rose action |
| Victory Gold | Optimistic and celebratory | Pale gold, amber, bronze action |
| Aurora | Luminous and imaginative | Violet, turquoise, pink |
| Electric Lime | Sporty and fresh | Lime, emerald, deep green action |
| Neon Pulse | Bold nighttime energy | Hot magenta, electric violet |

The picker order progresses from familiar and calm through warm and celebratory to the most visually energetic choices. Keep Indigo first as the default and preserve this progression when evaluating additions.

The retired `sunset` and `solarFlare` persisted values decode as Victory Gold.

## Theme Contract

`OutboundTheme` owns the complete visual system for each theme:

- `accentColor`: navigation tint, compact accents, selection marks, and primary swatches.
- `secondaryColor`: complementary color used to make each theme more than a monochrome tint.
- `actionColor`: readable filled-button color; it may be deeper than the accent.
- `heroGradient`: three-stop gradient for prominent themed surfaces.
- `glowColor`: restrained theme-colored shadow for hero surfaces and preview swatches.
- `heroForegroundColor`: readable content color over the actual hero gradient. Bright themes use dark foregrounds; darker themes use white.
- Dark appearance values: every palette property uses adaptive light and dark colors rather than opacity alone.

The selected theme is also injected through `EnvironmentValues.outboundTheme`. Any view whose rendering depends on a theme must read that environment value so SwiftUI refreshes it immediately. Do not read `UserDefaults` directly from a view.

## Applying Themes

- Shared companion-style cards use `OutboundCard(style: .companion)`.
- Shared filled actions use `OutboundPrimaryButton`.
- Companion explanations use `AIExplanationView`.
- Feature-specific themed elements should read `@Environment(\.outboundTheme)` and select the appropriate contract color.
- Semantic colors remain semantic. Do not theme destructive actions, warnings, map meaning, health states, or accessibility status colors.

## Adding A Theme

1. Add one `OutboundTheme` case and display name.
2. Define adaptive accent, secondary, action, and all three hero-gradient stops.
3. Verify hero foreground contrast in light and dark appearance.
4. Add an intentional glow color through the shared contract; do not add feature-local shadows.
5. Check the current-theme preview in Settings and the shared chooser's gradient preview.
6. Confirm Today, shared hero cards, buttons, tab tint, and companion explanations update without leaving the screen.
7. Keep the total list small enough to scan. Adding a theme should fill a distinct personality or color-space gap, not duplicate an existing option.

## Discovery Tip

- The Today palette tip is shown at most three times after a short delay and is anchored to a temporary palette button. Each actual presentation counts toward the limit.
- Choosing `Change appearance` permanently dismisses the tip and opens the appearance chooser, where both mode and theme can be changed.
- Dismissal is stored under `theme_discovery_tip_dismissed_v1`.
- The presentation count is stored under `theme_discovery_tip_presentation_count_v1`.
- The permanent Settings entry remains available after the temporary tip disappears.
