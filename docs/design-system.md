# Design system

Read before changing iOS or Android UI. This is the entry point; [themes.md](themes.md) owns palette roles, appearance behavior, and theme verification. [activity-launch-live-ux.md](activity-launch-live-ux.md) owns launch/live controls.

## Implementation rules

- Reuse or extend shared components before creating feature-local styling.
- iOS: `ios/Outbound/Outbound/DesignSystem/OutboundDesignSystem.swift` owns `OutboundSpacing`, `OutboundRadius`, `OutboundPalette`, adaptive themes, cards, and primary buttons. Use semantic SwiftUI text styles. Read the reactive `outboundTheme` environment for theme-dependent rendering.
- Android: `android/core/designsystem/` owns shared Compose UI. Use `MaterialTheme.colorScheme`, `MaterialTheme.typography`, and `LocalPlainstrideThemeColors` for their intended roles. Keep palette definitions in `PlainstrideTheme.kt`.
- Do not introduce literal RGB/hex colors in feature UI. Semantic chart, route, sport, safety, or asset colors can be exceptions with a specific reason; never recolor destructive/warning meaning to match a theme.
- Avoid line separators and dividers in new or redesigned app surfaces; use spacing and hierarchy to group content.
- Buttons are content-sized by default, including primary actions. Use full width only for an explicit layout need; preserve accessible hit targets without stretching the filled visual.
- iOS bordered buttons use `.buttonBorderShape(.roundedRectangle(radius: OutboundRadius.control))` to match the shared primary button's control radius; avoid the smaller implicit system radius. Apply minimum touch-target height to the button, outside its label, so native padding does not inflate the visible control.
- Text/menu actions must accept taps throughout their allocated label row, including transparent spacers and padding. On iOS, apply `.outboundTapTarget()` **inside** a `Button`, `NavigationLink`, or `Menu` label after its layout modifiers; it supplies a rectangular hit shape and a minimum 44 × 44 pt target without making compact controls full width. For an existing full-row action, keep its expanding frame/spacer inside that label. Never put one hit shape around a container with several independent actions. Keep native menu items native. Android Material menu items/buttons already own their padded target; custom rows must put `clickable` on the whole row and provide at least 48 dp.
- Preserve platform conventions and readable foreground/background pairings. Android has no shared spacing scale today; reuse existing shared components and keep feature dimensions consistent rather than inventing token APIs.
- Localize display strings and accessibility labels. Today uses icon-only circular launch controls and sport selectors with localized accessibility labels and state. Standalone setup and manual goal options retain text-only pills. Transient API feedback uses toasts.
- For contextual secondary actions beside a named item (such as Change plan and End plan), use compact neutral secondary buttons in a leading-aligned row below the item's name. Use a filled native or shared primary button for the main next step. Avoid text-link styling for product actions; use the documented neutral or action foreground/surface pair and semantic destructive color for destructive actions. Preserve at least 44 pt on iOS and 48 dp on Android touch targets. Let labels wrap and the row reflow naturally for large text, narrow screens, and longer translations. Use a full-width primary next step only when the layout explicitly needs it.

## iOS control contrast

- Use `OutboundButtonStyle(.secondary)` for secondary product actions and `OutboundButtonStyle(.primary)` for filled primary actions. Use `OutboundButtonStyle(.choice(isSelected:))` for native choice controls instead of expressing selection with an accent tint.
- Secondary controls use primary ink on an opaque neutral system surface; filled/selected controls use the theme `actionColor` / `actionForegroundColor` pair. The style delegates to native buttons for activation, control size, border shape, pressed and disabled treatment. Secondary neutral fill uses the native prominent renderer so a translucent accent wash cannot expose an unreadable hero background. Destructive roles retain their native semantic styling and requested prominence.
- Custom filled controls use the same action pair. Informative badges, initials, and glyph surfaces use primary ink with an opaque neutral surface, including when placed on hero cards. Accent is still appropriate for decorative marks, progress, borders, navigation tint, and theme previews; do not put accent text on an accent wash or assume white is readable on every action fill.
- Keep existing layout, labels, actions, and selection cues; continue to use checkmarks/selected accessibility traits. This style-only correction reuses existing analytics events and does not add new product behavior or strings.

### Shared style catalog

| Button family | Use | Foreground / surface | Layout |
| --- | --- | --- | --- |
| `.primary` | Main next step | Theme action foreground / action fill | Native size/shape; `OutboundPrimaryButton` supplies compact or expanded layout when explicitly needed |
| `.secondary` | Supporting product action | Primary ink / opaque neutral surface | Native size/shape, content-sized by default |
| `.quiet` | Explicit text-only contextual action | Primary ink, or the containing hero card's foreground / clear | Compact semantic label, existing card alignment, minimum 44 pt target |
| `.choice(isSelected:)` | Single/multiple selection | Selected action pair; unselected neutral pair | Native shape/size; `OutboundGoalPresetButton` supplies capsule/checkmark/reflow/44 pt layout |

Destructive meaning is a native `Button` role, retained across these families. Toolbar items, menu contents, system links, and semantic state controls remain native. Today's explicit text-only card actions map to `.quiet`; this does not change their layout or navigation. Filled primary and pill layout wrappers consume `OutboundButtonKind`'s same surface/foreground resolver rather than defining competing styles.

`OutboundTextStyle` and `.outboundTextStyle(_:)` provide semantic Dynamic Type roles. Color is intentionally separate, so typography cannot overwrite a selected, hero, or destructive foreground. `outboundSurfaceForeground` supplies primary ink by default and the explicit hero foreground within companion cards; shared explanation prose and quiet actions consume that context.

| Text role | Semantic font | Use |
| --- | --- | --- |
| `.title` | Title 2, semibold | Page/content title below native navigation |
| `.sectionHeading` | Headline | Section title |
| `.body` | Body | Main reading content |
| `.supporting` | Subheadline | Supporting detail |
| `.caption` | Caption | Metadata and short context |
| `.metric` | Title 3, semibold, monospaced digits | Numeric summary |
| `.button` | Headline | Standard primary label |
| `.compactButton` | Subheadline, semibold | Compact action/choice label |

Use these roles for new shared/product text, retaining contextual emphasis where needed. Native navigation titles, native toolbar/menu labels, and intentionally specialized sport/recording metrics keep their platform or feature typography. Existing unrelated page text is not restyled in the contrast audit. Shared primary, choice and quiet labels plus representative touched launch/onboarding controls and plan/group supporting text adopt the catalog without changing their prior semantic sizes.

### Contrast audit coverage — 2026-11-26

- Source inventory covered native bordered/prominent styles and custom accent/action fills, accent washes, and selected foreground/background pairs throughout iOS Swift sources. Updated auth/onboarding and plan intake; Today/activity setup, goal/manual/photo sheets and launch controls; route planning and community route actions; plans/adjustments/completion and Progress; social/groups/connections; profile/avatar and companion/unread badges; live-session controls and saved-activity completion.
- Preserved explicit semantic effort, safety cheer, relay participation/sharing/challenge state tints, route/map start meaning, charts, decorative theme/hero gradients, root navigation tint, and diagnostic/fixture controls. The widget setup tutorial's fixed blue controls do not inherit gold tint. These exceptions are not a claim that every semantic palette has received a separate accessibility audit.
- Exact action-palette luminance calculations across all eight themes and both appearances give at least 5.07:1 for the black/white foreground selected by `actionForegroundColor`; white alone falls to 2.21:1. This checks opaque palette pairs only, not native rendering, materials, disabled opacity, or photography.
- Source review and the added-line design-system checker cover this change. Physical-device visual checks across themes/appearances, largest accessibility text and narrow widths, screen-reader behavior, and interaction/state flows remain unverified until checked on device. No simulator runtime or test suite is required or implied by this audit.

## Goal preset choices

- iOS route-distance and manual Distance, Time, and Calories editors use `OutboundGoalPresetButton` in `OutboundGoalPresetFlow`.
- Keep semantic subheadline text at its Dynamic Type size; wrap labels and reflow choices at narrow widths instead of shrinking text or fixing the pill height.
- Apply compact visible padding and capsule fill before the minimum 44 × 44 pt touch target. Do not combine the preset with native bordered-button padding.
- Unselected choices use primary text on a neutral system background. Selected choices use the theme action/foreground pair plus a checkmark and selected accessibility trait. Route-distance presets retain their draft-only shortcut semantics.
- Styling does not change goal values, conversions, draft/apply/cancel behavior, or existing analytics.

## UI review checklist

Include the results in the completion report; mark unperformed checks explicitly.

- [ ] Shared components and tokens reused; new shared styles belong in the design system.
- [ ] Colors use the documented semantic roles; any checker suppression has a narrow, justified reason.
- [ ] Typography, spacing, corner radii, and hierarchy match neighboring screens.
- [ ] Light and dark appearance checked, including a bright and dark theme; theme changes refresh immediately.
- [ ] Large text/font scaling and a narrow screen checked for clipping, wrapping, scrolling, and reachable actions.
- [ ] Controls have accessible names, sufficient touch targets, and readable contrast; meaning does not rely on color alone.
- [ ] Strings localized; long translations considered; loading, empty, error, and offline states reviewed where affected.
- [ ] Relevant feature contract followed; changed screens visually inspected. Build success alone is not visual verification.
- [ ] Automated design check passes; exceptions and remaining verification limits reported.

## Automated guardrails

Run from the repository root against the commit before your changes:

```sh
python3 scripts/check-design-system.py --base main
```

The GitHub design-system workflow runs the same check on pull requests and pushes to main. It checks added Swift/Kotlin lines for literal RGB/hex color constructors outside the canonical palette files, and Android feature code for new Material color-scheme factories. Existing untouched violations are not baselined into a large cleanup task. Shared palette files still require manual review.

For an intentional semantic/asset color, put `// design-system-allow: <specific reason>` on the same line or immediately preceding line. Reviewers must verify the reason; do not use blanket file exemptions. The check rejects empty reasons.

These are focused text checks, not a Swift/Kotlin parser: multiline constructors and aliases can escape detection. They do not establish accessibility, layout quality, component reuse, localization, or visual parity. Those remain checklist responsibilities. Extend checks only where a reliable rule can distinguish violations from valid platform/semantic styling.
