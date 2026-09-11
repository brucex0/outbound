# Activity Detail iOS Parity

## Authority And Counterparts

- iOS detail shell and calculations: `ios/Outbound/Outbound/Activity/ActivityDetailView.swift`
- iOS activity models and persistence: `ios/Outbound/Outbound/Core/LocalActivityStore.swift`
- Android detail, history entry, calculations, and media presentation: `src/main/kotlin/com/plainstride/outbound/feature/activity/ActivityScreen.kt`
- Android activity mutations, share-card rendering, and analytics: `src/main/kotlin/com/plainstride/outbound/feature/activity/ActivityViewModel.kt`
- Android route renderer: `../../core/designsystem/src/main/kotlin/com/plainstride/outbound/core/designsystem/RouteMap.kt`
- Android persisted model and repository: `../../core/model/src/main/kotlin/com/plainstride/outbound/core/model/activity/SavedActivityModels.kt` and `../../core/data/src/main/kotlin/com/plainstride/outbound/core/data/ActivityRepository.kt`

## States And Transitions

- A stored activity opens from Me recent activity, activity history, notification, or a Social link to the synchronized personal activity.
- Me shows the latest three activities as lightweight rows inside the shared recent card: title, abbreviated date, rounded duration with calories when available, and trailing distance. The card exposes manual entry, Health Connect, and full-history actions with localized TalkBack labels and 48dp targets.
- The map stays full screen behind collapsed, split, and expanded information-sheet positions. Dragging the grabber snaps to the nearest position; tapping it toggles split and expanded states.
- Activities with no usable route show an accessible no-route state. Multi-segment routes preserve pause gaps; continuous routes use pace-colored segments.
- GPS-located photos produce map pins. Selecting a photo in the horizontal strip selects and centers its pin; selecting it again opens the full-screen pageable lightbox. Photos without coordinates remain visible without a misleading pin.
- Elevation and splits are hidden when source points are insufficient. Both sections are collapsed initially and fade open in place.
- Share opens the 9:16 image preview before save or system sharing. Edit and confirmed deletion retain the existing local-first repository behavior.

## Data And Presentation Contract

- Distance, pace, elevation, split length, history summaries, and share-card values follow the account measurement preference independently of locale.
- Stats follow iOS order: Distance, Avg. Pace, Moving Time, optional walking Steps, reliable Calories, and Elev Gain.
- Calories prefer imported/persisted energy and otherwise use the shared estimator with the current private training-profile weight. Weight and calorie values never enter analytics.
- Elevation uses cumulative route distance and excludes points with invalid vertical accuracy.
- Splits are derived from route point timestamps and distance at the selected kilometer/mile boundary, include a useful partial final split, and show proportional pace bars plus elevation change when available.
- Private source, shoe, indoor, and cadence metadata is shown only on the stored owner's activity.
- GPX and GeoJSON export remain implemented internally but are intentionally absent from the current detail UI, matching iOS.

## Shared Resources, Analytics, And Accessibility

- English, Spanish, and Simplified Chinese copy is generated from `ios/Outbound/Outbound/Localizable.xcstrings`.
- The grabber, map, photos, lightbox close action, Edit, Share, Back, and Delete expose semantic labels; section headers remain discoverable to TalkBack.
- Opening detail emits `activity_detail_opened`. Recent-card actions emit the existing `me_destination_opened` event with a bounded destination and `entry_source=me_recent`. A displayed calculated calorie emits privacy-safe `feature_exposed(feature=completed_workout_calories)`.
- Share preview and actions emit `activity_share_previewed` and `activity_share_action` with the same bounded `source_type` and `result` values as iOS. Confirmed deletion uses the shared source/count-bucket contract.

## Reference Scenarios

- Route with continuous points, route with pause segments, and no route.
- Metric and imperial account preferences in English, Spanish, and Simplified Chinese.
- No photos, located and unlocated photos, missing local media, and multi-photo lightbox paging.
- No altitude, invalid vertical accuracy, full and partial final splits, imported calories, calculated calories, and unavailable calories.
- Plainstride, manual/imported, shoe-attached, indoor, cadence, and activity-event metadata.
- Collapsed, split, expanded, long-title, large-text, dark/light theme, and TalkBack traversal.

## Status And Remaining Parity Work

- The stored-owner activity-detail UI, measurement logic, route/elevation/split presentation, photos, reflection, share preview, and analytics are aligned with the current iOS hierarchy and behavior.
- Google Maps and Material controls are the documented platform substitutions for MapKit and SwiftUI controls.
- The iOS editor additionally changes date, distance, duration, shoes, and photo order/capture; Android's existing edit action currently changes only the title. This remains an open activity-edit parity defect rather than an approved exception.
- Social feed activity detail still owns a share-safe reduced payload in `feature/social`; adapting that payload to this shared map-and-sheet shell remains tracked by the Social parity manifest and is not an approved exception.
- Save Route remains reachable from Android's My Routes publishing flow, but the iOS detail-level shortcut and tooltip are still open parity work.
