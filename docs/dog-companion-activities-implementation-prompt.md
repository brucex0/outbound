# Dog Companion Activities Implementation Prompt

Use this prompt to implement `With dog` end to end. The canonical product rules are in `docs/dog-companion-activities.md`; that document is authoritative if this handoff is ambiguous.

## Prompt

Implement Plainstride's `With dog` activity context across backend, iOS, and Android.

Start by reading `AGENTS.md`, `docs/INDEX.md`, `docs/dog-companion-activities.md`, `docs/activity-launch-live-ux.md`, `docs/ios-architecture.md`, `docs/product-analytics.md`, `docs/localization.md`, `docs/android-port.md`, and `docs/android-build.md`. Inspect the current code before editing; do not assume the file list below is exhaustive.

### Non-negotiable product behavior

- `With dog` is optional context for Run, Walk, Hike, and Bike. It is not a new `ActivityType`, goal mode, or training plan.
- Represent it as the optional typed value `companionType: null | "dog"` across all durable and network contracts.
- Preserve the original sport, goals, structured phases, metrics, auto-pause, plan completion, progress classification, race modeling, and calorie behavior.
- Add one paw-icon `With dog` control to the existing setup settings row. Do not add another setup screen or require a pet profile.
- Retain the value across eligible sport/goal changes, countdown cancellation, active recording, process recovery, and phone/watch handoff. Clear it with a temporary toast if setup changes to an incompatible sport. Reset it after Save or Discard.
- Surface a compact paw treatment in countdown/live context, saved history, activity detail, and share-safe Social cards without displacing primary metrics.
- All recorded metrics describe the person. Do not infer or display dog metrics or provide veterinary, safety, health, hydration, temperature, or fitness advice about the dog.
- Imported and manual activities remain untagged in V1.

### Backend

- Add nullable `companionType` to the canonical Prisma `Activity` model and create the migration. Do not backfill old rows.
- Extend the activity create/update validator in `backend/src/routes/activities.ts` with the strict optional value `dog`; reject unknown values.
- Persist and return the field in canonical activity responses, `legacyClientData`, client restore payloads, and the share-safe Social/activity DTOs that render activity cards or details.
- Ensure idempotent re-upload preserves the value and that omission from an older client does not unexpectedly erase an already stored value during conflict resolution.
- Do not add pet identity fields or include companion context in location-sharing payloads, route records, recognition rules, planning inputs, or live presence.
- Check generated Prisma types and all DTO selectors after the schema change.

Likely backend areas include:

- `backend/prisma/schema.prisma` and a focused migration
- `backend/src/routes/activities.ts`
- Social activity serializers/selectors in `backend/src/routes/social.ts`
- Any shared activity or Circle summaries that intentionally render the paw marker

### iOS

- Add a small Codable/Hashable companion type with the single V1 case `dog`; use an optional value on session and saved-activity models.
- Thread it through `RecordView` prepared/active state, `ActiveSessionJournal`, recovery, `ActivityPersistence`, `SavedActivity`, `ActivityStore`, `ActivityUploadRequest`, sync snapshots, and remote restoration.
- Update every explicit `SavedActivity` reconstruction/copy path so edits, sync-state updates, photo changes, HealthKit references, and remote merges cannot drop the value.
- Add the localized paw control to the existing horizontal launch settings row in `Activity/RecordView.swift`. Match the established control styling, selection semantics, and 44-point target.
- Eligibility must use the resolved activity type for Planned and Curated sessions. Retain across eligible changes; clear incompatible state with the existing temporary toast pattern.
- Preserve the context in iPhone/Apple Watch session handoff and recovery metadata. A standalone Watch start does not need a new dog-selection UI in V1, but a phone-configured session must not lose the value.
- Add compact paw context to countdown/live status, recent activity/history, `ActivityDetailView`, and share-safe Social rendering. Avoid duplicating the label where the title already clearly says Dog walk/run/hike/ride.
- Generate localized dog titles only for freestyle activities. Preserve planned and curated workout titles, and never change the canonical activity type.
- Update `Localizable.xcstrings` with natural English, Spanish, and Simplified Chinese strings. Do not hard-code display text.

Likely iOS areas include:

- `ios/Outbound/Outbound/Activity/RecordView.swift`
- `ios/Outbound/Outbound/Core/ActiveSessionJournal.swift`
- `ios/Outbound/Outbound/Core/LocalActivityStore.swift`
- `ios/Outbound/Outbound/Activity/ActivityStore.swift`
- `ios/Outbound/Outbound/Core/APIClient.swift`
- `ios/Outbound/Outbound/Activity/ActivityHistoryView.swift`
- `ios/Outbound/Outbound/Activity/ActivityDetailView.swift`
- `ios/Outbound/Outbound/Activity/PostRunSummaryView.swift`
- share/Social activity card renderers and phone/watch session contracts
- `ios/Outbound/Outbound/Localizable.xcstrings`

### Android

- Add the same optional serialized companion type to recording launch/session state, active-session journal/database state, saved activities, repository DTO parsing, upload/export, and restore paths.
- Add the paw control to the existing Today recording setup with Material/Plainstride theming, a 48-dp target, localized selected semantics, and TalkBack support.
- Match iOS eligibility, retention, incompatible-sport clearing, Save/Discard reset, live marker, history/detail marker, and share-safe Social behavior.
- Persist the value through process recreation and phone/Wear handoff. Wear does not need a standalone selector in V1, but it must preserve phone-configured metadata.
- Add natural English, Spanish, and Simplified Chinese resources. Avoid hard-coded display strings.

Likely Android areas include:

- `android/feature/today/`
- `android/feature/recording/`
- `android/core/model/.../activity/`
- `android/core/data/ActivityRepository.kt` and recorded-activity factories/export
- `android/core/database/ActiveSessionJournal.kt`
- `android/feature/activity/`
- phone/Wear session contracts and relevant string resources

### Analytics and privacy

- Extend the shared typed analytics allowlist with `dog_companion_enabled`.
- Include the boolean only on `activity_started` and `activity_saved`.
- Reuse `activity_configuration_changed` with bounded companion on/off values and `feature_exposed` with `feature=dog_companion`; do not emit an event for every render or tap beyond the established contracts.
- Update iOS and Android event/property schemas together so neither platform silently drops or rejects the property.
- Never log or analyze dog names, images, free text, routes, coordinates, or pet-health data.

### Data and compatibility rules

- Missing companion data decodes as `null` everywhere.
- The repository's pre-publish data policy allows a clean schema/model change, but no destructive reset should be necessary for this nullable field.
- Preserve unknown future read values safely where the platform contract permits, but never send an unsupported value.
- Verify server-created, iOS-created, and Android-created activity payloads round-trip without losing the context.
- Do not derive the value from localized titles and do not place it only inside opaque client JSON.

### Verification

- Do not run the test suite unless the user explicitly asks. Perform build-only/static verification appropriate to each affected component.
- Build the backend and run schema/type generation or validation required by the repository.
- Build the iOS app with code signing disabled using the documented command.
- Build the affected Android debug variants/modules using `docs/android-build.md`.
- Run `git diff --check`.
- Manually or through existing non-test previews/debug fixtures verify: each eligible sport; Planned and Curated resolution; incompatible sport clearing; countdown cancel; Save/Discard reset; force-quit recovery; phone/watch or phone/Wear continuity; history/detail/Social paw rendering; offline save and later sync; server round-trip; EN/ES/zh-CN; large text; VoiceOver/TalkBack; dark mode; and no change to plan completion or sport progress.

### Documentation and commits

- Update `docs/dog-companion-activities.md`, `docs/activity-launch-live-ux.md`, `docs/ios-architecture.md`, Android parity docs, and API/data documentation if implementation details change.
- Follow `AGENTS.md` commit discipline. Commit backend, iOS, and Android work separately with `[BE]`, `[iOS]`, and `[Droid]` prefixes; do not combine platform scopes.
- Keep unrelated working-tree changes and agent metadata out of every commit.

When finished, report the behavior delivered, files changed, migration and compatibility handling, localization coverage, analytics changes, verification commands/results, commit hashes by scope, and any genuine remaining blocker. Do not claim completion if any client can lose `companionType` during recovery, copying, sync, or cross-device handoff.
