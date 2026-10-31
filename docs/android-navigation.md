# Android Navigation Ownership

Open when adding a destination, changing a link/notification entry point, or investigating Back/restoration behavior.

## Contract

- Always navigate with the entity ID (plus bounded context). The destination resolves that ID from its account-scoped cache first, then refreshes from the network; it never requires an object or selected state supplied by its caller. Persist a newly fetched snapshot for later offline/restored entry.
- Push the requested page directly over its actual caller. Do not insert or render a tab/list as a host for an entity page.
- Toolbar Back and system Back pop the same destination; neither switches a detail into a list.
- Social, Today, and Me remain the three primary tabs. Detail pages hide the primary toolbar and retain the caller's saved tab/list state.
- A cold link uses the shell's normal launch/restored root as the fallback caller; it does not manufacture Social, History, or a route-library entry.
- Pickers, comments, photo/share previews, confirmations, Group creation/composition, and Today route selection are explicit contextual flows. They may preserve their real owner underneath, but cannot serve as implicit anchors for external detail entry.

## Implementation

- `android/app/.../AppDetailRoutes.kt` owns route patterns and encoded route builders. Navigation arguments contain identity plus bounded source/mode values.
- `PlainstrideApp.kt` registers pages and dispatches in-app, notification, connection-link, and Group-invite entry points to those routes. `MainActivity` consumes notification intents and saves only pending links across recreation, preventing a consumed launch link from being replayed above a restored nested page. The inbox has no competing automatic deep-link handler.
- Connections is a reusable destination, not a Social-hosted dialog. Me, Social, Trusted Contacts, and notifications open the same page with the corresponding `connections_opened` entry source. QR scanning and personal QR navigation preserve Connections as their real caller.
- Personal activity History is a list destination. Server-only activities retain a known local identity or use their server ID when no client activity ID exists, including activities from other supported sources. `ActivityDetailDestination` loads by local/client or server ID and returns directly to its caller; loading it does not emit `activity_history_opened`. Missing local activities can fetch by server ID without loading History.
- Social post, profile, Group, event, and invitation pages use destination-scoped ViewModels. A profile loads by person ID or opaque connection code. Search/feed/contact taps persist their already-exposed share-safe preview in the account cache (`social.profile-preview/<personId>/und`) before navigating. The current profile API refreshes basic identity and connection state for self, accepted, pending, and unconnected people; cached previews preserve offline/restored presentation. Recognitions remain subject to the backend's connection/privacy rules. Opening a nested activity/profile/event does not clear the calling destination's state.
- Events, Groups (including invitation context), invitations, posts, and connection-code previews use account-cache snapshots under `social.detail.*`; profile snapshots remain under `social.profile-preview`. Cached content renders while HTTP refresh runs. Known forbidden/not-found responses clear visible content; transient failures retain a usable cached page.
- Group invitations resolve to the canonical Group page with an invitation ID; Group-invite token resolvers replace themselves with the Group route. Event invitation actions remain on their independent destination.
- Community route detail loads by route ID, using an account-scoped cached snapshot for offline fallback. Imported routes are stored in the existing account cache under `routes.imported/library/und`, remain device-local, and resolve by their `import:` ID. Existing account-cache cleanup removes these rows alongside other account caches; no Room schema change or migration is required.
- Route library screens only browse/select; they navigate to the shared detail page. Today retains its explicit selection mode. Successful bookmark/removal refreshes the source library; deletion returns to the real caller.
- Safety/live and informational notification details resolve their route ID independently. Informational inbox snapshots use `inbox.detail/<id>/und`; live follower and Group-run snapshots remain bounded in memory, without adding persistent location storage. Viewing a Group-run does not replace another active participation, and its leave action addresses the viewed session. Group-run links render the session alone, without Safety settings as a host. These details carry their kind/ID in the back stack rather than shell selection variables. Warm/cold `group_run` links use the same live-group destination as inbox taps.

## Diagnostics And Analytics

- Unavailable entity pages retain Back and retry; they do not silently redirect to a host page. Handled load failures log operation, exception/API category, and available HTTP status without entity IDs, user data, URLs, or tokens.
- Existing activity, profile, connections, Group, event, invitation, and route action events retain their privacy-safe properties. Profile/detail loading does not emit Social-tab or History exposure events.
- `route_detail_opened` records only `source_type=community|imported` and `result=success|failure`; no route identity, name, geometry, or location is recorded.

## Verification Matrix

Use manual UI checks; do not run the test suite without an explicit request.

| Entry | Required return behavior |
| --- | --- |
| Me → Connections → system/toolbar Back | Me in one step; Social/Me tab presses still work |
| Trusted Contacts → Connections → Back | Trusted Contacts; no Social entry |
| Social Feed/People → profile → post → Back → Back | Same profile, then original tab/list position |
| Connections → profile → post → Back → Back | Same profile, then Connections with its query/position |
| Me recent activity → detail → Back | Me; no History page |
| History → detail → Back | Original History position |
| Inbox → activity/post/profile/event/Group/invitation → Back | Inbox; no synthetic Social/History entry |
| Cold/warm connection and Group invite links | Requested target; no inserted Social entry |
| Social Routes / Me My Routes → route detail → Back | Actual originating library and scroll/filter state |
| Imported route → detail → Back / delete | Actual library; deleted import removed from library |
| Connections → QR / scanner → profile → Back | Actual previous page; no hidden Social host |
| Event/Group → nested event → Back | Same original detail, including its local state |
| Process recreation while on profile/activity/route/event/Group | Identity restored from route arguments; finite unavailable/retry state if data cannot load |
| Offline cached detail / unavailable or revoked target | Cached content where available, otherwise actionable retry and Back |

Build verification: `./gradlew :app:assembleDebug :app:compileReleaseKotlin` from `android/`. Record actual device checks and remaining gaps with the change; build success alone does not establish navigation or visual correctness.

## Verification Record — 2026-10-30

- Build-only checks: debug APK assembly and release Kotlin compilation; no test suite was run.
- Samsung phone, existing debug account: a warm Connections link over Me returned to Me with system Back; a contact profile returned to Connections with system Back; an unavailable profile returned to its Connections caller with the search state retained.
- Source review additionally covered canonical route registration/builders, direct inbox/link dispatch (including Group-run parity), local/server activity-ID lookup, destination-scoped nested state, pending-link recreation handling, cached/uncached route loading, summary-to-detail geometry retention, imported-list order retention and persistence-result analytics, exact invitation-ID forwarding, and share-safe pending/unconnected profile previews.
- The final preview-cache change was build-verified; it was not rechecked on device. Populated nested profile → activity returns, valid Group/event/invitation/live flows, route import/detail/deletion, process-death and offline recovery, locale/font/TalkBack presentation remain manual checks. Device interaction was stopped when the phone state changed during verification.

## Automated Navigation Regression Tests

Run only when tests are explicitly requested, on a dedicated running emulator:

```sh
ANDROID_SERIAL=emulator-5556 ./android/test-navigation.sh
```

- `navigationTest` is a separate `com.plainstride.outbound.navigationtest` APK using device-local HTTP fixtures at `127.0.0.1:18787`, synthetic credentials, its own Room database/preferences, and disabled Firebase/billing configuration. Test setup checks that package and endpoint before clearing fixture data. No production account or backend is needed.
- `NavigationInteractionTest` exercises the real app graph, callbacks, destination ViewModels, Room, and HTTP: Me/Connections/tab responsiveness, search query retention, profile → activity nesting, toolbar/system Back, warm/cold links, Group invite replacement, recreation, cached/network detail lookup, offline content, denied/missing entities, informational inbox detail, imported-route deletion, and the viewed Group-run leave action.
- The runner also runs the existing profile control tests for Connect/Sent, incoming Accept/Decline, disconnect confirmation, and processing-state controls. It requires an explicit emulator serial and checks instrumentation output because `am instrument` can exit zero on test failure.
- Recreation coverage uses `ActivityScenario.recreate()`; full OS process death, production realtime transport, map rendering, and real camera/file pickers remain separate device/manual checks.


## Verification Record — Cache-First Follow-Up

- Dedicated API 37 emulator: 21 navigation/lookup interaction tests and 5 existing profile-control tests passed using `android/test-navigation.sh`.
- Final activity identity refinement: cached and uncached server-ID cases rerun, including refresh without a client ID preserving one existing local record.
- Debug APK assembly and release Kotlin compilation passed. `bash -n android/test-navigation.sh` and `git diff --check` passed.
- No physical-phone or production-data interaction. Full process death, production realtime, camera/file-picker UI, and map rendering remain unverified by this fixture suite.
