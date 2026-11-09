# Design system

Read before changing iOS or Android UI. This is the entry point; [themes.md](themes.md) owns palette roles, appearance behavior, and theme verification. [activity-launch-live-ux.md](activity-launch-live-ux.md) owns launch/live controls.

## Implementation rules

- Reuse or extend shared components before creating feature-local styling.
- iOS: `ios/Outbound/Outbound/DesignSystem/OutboundDesignSystem.swift` owns `OutboundSpacing`, `OutboundRadius`, `OutboundPalette`, adaptive themes, cards, and primary buttons. Use semantic SwiftUI text styles. Read the reactive `outboundTheme` environment for theme-dependent rendering.
- Android: `android/core/designsystem/` owns shared Compose UI. Use `MaterialTheme.colorScheme`, `MaterialTheme.typography`, and `LocalPlainstrideThemeColors` for their intended roles. Keep palette definitions in `PlainstrideTheme.kt`.
- Do not introduce literal RGB/hex colors in feature UI. Semantic chart, route, sport, safety, or asset colors can be exceptions with a specific reason; never recolor destructive/warning meaning to match a theme.
- Preserve platform conventions and readable foreground/background pairings. Android has no shared spacing scale today; reuse existing shared components and keep feature dimensions consistent rather than inventing token APIs.
- Localize display strings and accessibility labels. Use text-only launch option pills and icon-only sport selectors with localized labels. Transient API feedback uses toasts.
- For paired contextual secondary actions beside a named item (such as Change plan and End plan), place a compact, leading-aligned text row directly below that item's name. Keep the actions text-only without pills, borders, or icons; use the theme accent for the neutral action and the semantic destructive color for destructive actions. Preserve at least 44 pt on iOS and 48 dp on Android touch targets. Let labels wrap and the row reflow naturally for large text, narrow screens, and longer translations. Reserve full width for a primary next step when the flow has one.

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
