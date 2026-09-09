# Discovery Tooltips

Open this when adding or changing a short, anchored discovery tooltip in the iOS app.

## Framework

- `Core/TooltipCoordinator.swift` is the app-scoped scheduler and persistence owner.
- `AppTooltip` defines each tooltip's stable ID, analytics name, priority, delay, and lifetime presentation limit.
- `coordinatedTooltip(_:isEligible:text:arrowEdge:)` attaches a definition to its visible anchor.
- The coordinator batches simultaneous candidates, shows the highest priority candidate, and never presents two tooltips at once.
- Discovery tips share a global budget of one presentation per calendar day. Contextual tips are exempt because they appear only after a qualifying action, but they still never overlap another tooltip.
- Leaving a surface withdraws its candidate without acknowledging it, so it remains eligible on a later visit.
- Existing `*_discovery_tip_dismissed_v1` values are honored when migrating older tooltips.

## Add A Tooltip

1. Add one `AppTooltip` static definition with a unique stable ID. Choose the discovery budget for general feature education or contextual for help unlocked by the current workflow. Use a higher priority only when the feature is more important at the same moment.
2. Attach `.coordinatedTooltip(...)` directly to the control that the popover should point to.
3. Make `isEligible` describe both product eligibility and anchor visibility. Do not add separate presentation state, counters, delays, or `UserDefaults` keys in the feature view.
4. Localize `text` in `Localizable.xcstrings` for English, Simplified Chinese, and Spanish.
5. If tapping the control while its tip is visible opens another presentation, call `dismiss(_:outcome:)` first and allow the native popover dismissal animation to finish before opening the next sheet or menu.

`feature_exposed` is emitted when the coordinator actually presents a tip. Dismissal outcomes use the privacy-safe `activity_configuration_changed` contract and include only the stable tooltip ID.
