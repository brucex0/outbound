# Activity Detail iOS Parity

## Authority And Counterparts

- iOS detail shell and calculations: `ios/Outbound/Outbound/Activity/ActivityDetailView.swift`
- iOS activity models and persistence: `ios/Outbound/Outbound/Core/LocalActivityStore.swift`
- Android detail, history entry, calculations, and media presentation: `src/main/kotlin/com/plainstride/outbound/feature/activity/ActivityScreen.kt`
- Android activity mutations, share-card rendering, and analytics: `src/main/kotlin/com/plainstride/outbound/feature/activity/ActivityViewModel.kt`
- Android route renderer: `../../core/designsystem/src/main/kotlin/com/plainstride/outbound/core/designsystem/RouteMap.kt`
- Android persisted model and repository: `../../core/model/src/main/kotlin/com/plainstride/outbound/core/model/activity/SavedActivityModels.kt` and `../../core/data/src/main/kotlin/com/plainstride/outbound/core/data/ActivityRepository.kt`

## States And Transitions

- A stored activity opens through an independent ID-based detail destination from Me recent activity, History, notifications, or a Social link to the synchronized personal activity. History is never inserted as a host. System and toolbar Back return to the actual caller; local/client and server IDs resolve independently, including uncached notification targets.
- Me shows the latest three activities as lightweight rows inside the shared recent card: title, abbreviated date, rounded duration with calories when available, and trailing distance. The card exposes manual entry, Health Connect, and full-history actions with localized TalkBack labels and 48dp targets.
- The map stays full screen behind collapsed, split, and expanded information-sheet positions. Dragging the grabber snaps to the nearest position; tapping it toggles split and expanded states.
- Activities with no usable route show an accessible no-route state. Multi-segment routes preserve pause gaps; continuous routes use pace-colored segments.
- GPS-located photos produce map pins. Selecting a photo in the horizontal strip selects and centers its pin; selecting it again opens the full-screen pageable lightbox. Photos without coordinates remain visible without a misleading pin.
- Elevation and splits are hidden when source points are insufficient. Both sections are collapsed initially and fade open in place.
- Share opens the 9:16 image preview before save or system sharing. The route backdrop includes white-bordered 144-pixel circular photo thumbnails at valid, visible photo coordinates. It reuses the detail photo decoder for EXIF rotation/mirroring and aspect-fill crops, retains original files/metadata, and skips unavailable local media without blocking export. Remote-only photos remain unavailable, matching the current detail photo strip. Edit and confirmed deletion retain the existing local-first repository behavior.

## Data And Presentation Contract

- Distance, pace, elevation, split length, history summaries, and share-card values follow the account measurement preference independently of locale.
- Stats follow iOS order: Distance, Avg. Pace, Moving Time, optional walking Steps, reliable Calories, and Elev Gain.
- Calories prefer imported/persisted energy and otherwise use the shared estimator with the current private training-profile weight. Weight and calorie values never enter analytics.
- Elevation uses cumulative route distance and excludes points with invalid vertical accuracy. Owner detail opens asynchronously refresh missing/`terrain-v1` metadata through the shared `terrain-v2` service, then enqueue sync. The original route geometry, timestamps, pause boundaries, and split timing remain intact; returned heights are interpolated back onto those points. Provider attribution appears below the expanded profile. See `docs/activity-detail.md` for the shared algorithm.
- Correction is optimistic: deletion, route/metadata edits, account switches, cancellations, and concurrent correction cannot overwrite a newer local result. Offline/auth/provider/validation failures retain the last result. Upload/restore and Room persistence carry typed elevation attribution/version metadata; source altitude samples stay in the local-only original-route table.
- Splits are derived from route point timestamps and distance at the selected kilometer/mile boundary, include a useful partial final split, and show proportional pace bars plus elevation change when available.
- Private source, shoe, indoor, and cadence metadata is shown only on the stored owner's activity.
- GPX and GeoJSON export remain implemented internally but are intentionally absent from the current detail UI, matching iOS.

## Shared Resources, Analytics, And Accessibility

- English, Spanish, and Simplified Chinese copy is generated from `ios/Outbound/Outbound/Localizable.xcstrings`.
- The grabber, map, photos, lightbox close action, Edit, Share, Back, and Delete expose semantic labels; section headers remain discoverable to TalkBack.
- Opening detail emits `activity_detail_opened` with the actual bounded entry source (`history`, `me_recent`, `notification`, or `deep_link`), without emitting a History exposure. Recent-card actions emit the existing `me_destination_opened` event with a bounded destination and `entry_source=me_recent`. A displayed calculated calorie emits privacy-safe `feature_exposed(feature=completed_workout_calories)`.
- Share preview and actions emit `activity_share_previewed` and `activity_share_action` with the same bounded `source_type` and `result` values as iOS. Share previews also include the same coarse geotagged-photo `count_bucket` as iOS, excluding photo content, identifiers, and coordinates. Confirmed deletion uses the shared source/count-bucket contract.

## Reference Scenarios

- Route with continuous points, route with pause segments, and no route.
- Raw/missing metadata, `terrain-v1`, current `terrain-v2`, unknown future versions, cross-platform upload/restore, provider failure, canceled request, edit/delete/account switch during correction, and reopen after offline fallback.
- Metric and imperial account preferences in English, Spanish, and Simplified Chinese.
- No photos, located and unlocated photos, missing local media, and multi-photo lightbox paging.
- No altitude, invalid vertical accuracy, full and partial final splits, imported calories, calculated calories, and unavailable calories.
- Plainstride, manual/imported, shoe-attached, indoor, cadence, and activity-event metadata.
- Collapsed, split, expanded, long-title, large-text, dark/light theme, and TalkBack traversal.

## Status And Remaining Parity Work

- The stored-owner activity-detail UI, measurement logic, route/elevation/split presentation, photos, reflection, share preview, and analytics are aligned with the current iOS hierarchy and behavior.
- Google Maps and Material controls are the documented platform substitutions for MapKit and SwiftUI controls.
- Edit opens a full-screen draft editor matching iOS's Activity → Photos → Workout Details → Gear cards, 20dp corners/spacing, inline title/date controls, three duration fields, derived plausible pace, active-shoe picker, and pinned Save Changes button. Cancel/system Back confirms dirty drafts; save stays disabled for unchanged/invalid drafts and while saving/importing. Localized decimal input follows account units and preserves the original distance precision until edited. Blank titles retain the existing title.
- Photo management matches the shared iOS review: camera/library icon actions, empty state, 104dp thumbnails, capture-context captions, full-screen paging, long-press selection, deletion, and horizontal drag reordering; TalkBack also exposes earlier/later reorder actions. Both editor and finish review use the system image document picker to read original provider files rather than potentially GPS-redacted visual-picker copies. Android 10+ requests optional `ACCESS_MEDIA_LOCATION`; denial still allows image import, without fabricated GPS. MediaStore originals are requested when available, with a diagnosed normal provider fallback; no broad gallery-read permission is added. Imported capture times determine interpolated route distance and Start/Finish context; GPS is attached only within 500m of any route sample, independent of capture-time/time-zone mismatch. New imports normalize all eight EXIF orientations into 2048px JPEGs at quality 90, retaining capture/GPS metadata and enforcing the backend's 5MB limit. Existing photos retain their bytes and metadata.
- Photo order is stored separately from capture time in Room v6 and retained on refresh. Removed remote photos use the durable activity outbox; refresh excludes pending deletions. Local saves enqueue synchronization and failures retain the draft with transient feedback. Editor and photo actions use existing privacy-safe feature/photo events with `source_type=activity_edit`.
- Room v6 creates a fresh `plainstride-v6.db` under the unreleased Android policy; no v5 data is copied. Rebuild with `cd android && ./gradlew :app:assembleDebug`. For a complete explicit development reset, use the command in `docs/android-build.md`.
- Validation for the editor: source review against iOS covered zero/invalid distance, 0–999 hours and 0–59 minutes/seconds, zero duration, unchanged rounded distance, blank titles, metric/imperial and decimal-comma input, empty/selected/reordered/imported photos, offline deletion retry, and save/discard states. Device rendering, camera/picker interaction, rotation/process recreation, TalkBack, and live sync still require manual acceptance; source review and a build do not establish exact visual/runtime parity.
- Social feed activity detail still owns a share-safe reduced payload in `feature/social`; adapting that payload to this shared map-and-sheet shell remains tracked by the Social parity manifest and is not an approved exception.
- Save Route remains reachable from Android's My Routes publishing flow, but the iOS detail-level shortcut and tooltip are still open parity work.

## Running Steps Per Minute

- Running detail uses the localized `Steps / min` label and average/maximum values.
- The shared chart decodes the private iOS/Android cadence summary and segmented samples; old summary-only activities retain statistics without a chart.
- Chart exposure records only `feature_exposed/running_cadence_summary`; exact values and samples are excluded.

- Photo-import verification: `:app:assembleDebug` passed; no tests run. Source review covered imported-only/mixed/reordered/deleted drafts, granted/denied metadata access, absent/invalid/off-route GPS, mismatched capture times, and unchanged image normalization/camera fallback. Device acceptance remains for granted/denied metadata access, local/cloud document providers, all eight EXIF orientations, near-route/off-route/no-GPS photos, mismatched capture times, save/reopen, and gallery counts for imported-only and mixed drafts.
