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
- For contextual secondary actions beside a named item (such as Change plan and End plan), use compact native bordered buttons in a leading-aligned row below the item's name. Use a filled native or shared primary button for the main next step. Avoid text-link styling for product actions; use the theme action/accent for neutral actions and semantic destructive color for destructive actions. Preserve at least 44 pt on iOS and 48 dp on Android touch targets. Let labels wrap and the row reflow naturally for large text, narrow screens, and longer translations. Use a full-width primary next step only when the layout explicitly needs it.

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
