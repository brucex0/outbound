# In-App and Push Notifications

Open this when changing notification creation, delivery, device registration, foreground behavior, or tap routing.

## Product Contract

- The backend notification record is the source of truth. Push is a best-effort delivery channel, not a second inbox.
- The durable inbox currently receives `connectionRequest`, `connectionAccepted`, `cheer`, `comment`, `runInvitation`, `invitationAccepted`, `activityEventJoined`, `circleInvitation`, `circleInvitationAccepted`, `circleCheer`, `circleWeeklyGoalCompleted`, `circleOwnershipTransferred`, and `liveCheerInvitation` records. Push delivery remains type-dependent; a durable record does not imply that an OS push is enabled for that type.
- Circle object IDs route to an invitation or Circle. Optional Cheer/completion creation respects the per-Circle mute preference, while membership-critical state remains visible.
- The in-app destination is named Notification Center and remains available when push permission is denied or delivery fails.
- Foreground push notifications use the system banner, sound, and badge. Tapping a connection request selects Social and opens Connections; other pushes open Notification Center.
- Apple Health foreground scans are silent. When new workouts are found, one local-only Notification Center item appears and opens the import review on demand; health details are never sent to the notification backend.
- Every delivered Social push uses the same event-specific, share-safe message as the inbox (for example, who accepted a connection or commented). Generic copy is only a client fallback for a malformed payload with no usable message. Do not put private plan, health, readiness, location, or cycle data in a push payload.
- Device tokens are user-scoped, may move between accounts, and are removed when Firebase reports them invalid or unregistered.

## Backend Contract

### Register a device

`PUT /v1/notifications/devices`

```json
{
  "token": "FCM registration token",
  "platform": "android",
  "appBundle": "com.plainstride.outbound",
  "locale": "en_US"
}
```

`platform` accepts `ios` or `android`. The operation is authenticated and idempotent by FCM registration token. It updates ownership, locale, enabled state, and `lastSeenAt`.

### Remove a device

`DELETE /v1/notifications/devices/:token`

Only the authenticated owner can remove the token.

### Delivery payload

Firebase Admin routes each registered device by platform. iOS receives the APNs sound and badge payload through FCM; Android receives a high-priority FCM notification on the `social` channel. Both receive visible notification content plus these string data fields:

| Field | Meaning |
| --- | --- |
| `notificationId` | Durable `SocialNotification.id` |
| `type` | Notification routing category |
| `objectId` | Related connection, post, invitation, or event ID |
| `destination` | Currently `social.notifications` |

Creating the inbox record succeeds independently of push. Delivery errors are logged, while invalid tokens are deleted automatically.

### Inspect production delivery failures

Push failures are written to the Cloud Run logs with the prefix `[push]`. In Google Cloud Console, open **Logging > Logs Explorer**, select the `outbound-api` Cloud Run service, and filter for:

```text
resource.type="cloud_run_revision"
resource.labels.service_name="outbound-api"
textPayload:"[push]"
```

Or use:

```bash
gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="outbound-api" AND textPayload:"[push]"' \
  --project=outbound-494602 \
  --freshness=24h \
  --limit=100 \
  --format=json
```

Delivery logs contain only platform, a stable category (`invalid_token`, `credentials`, `rate_limited`, `provider_unavailable`, `invalid_payload`, or `unknown`), retryability, and aggregate counts. Registration tokens, user IDs, provider error messages, notification text, and object IDs are intentionally omitted. Invalid or unregistered tokens are deleted automatically.

## Android Contract

- The app creates the `social` notification channel before token registration and uses notification importance appropriate for invitations and responses.
- FCM token refresh registers the replacement token after authentication. Sign-out removes the current token when connectivity permits; server ownership also moves idempotently if the same token later registers to another account.
- Permission denial never removes the durable in-app inbox. Android 13 and later request `POST_NOTIFICATIONS` only from contextual notification education UI.
- Taps use the same bounded `type`, `objectId`, and `destination` routing contract as iOS. Push payloads never contain health, plan, readiness, location, route, or cycle data.

## iOS Contract

- `PushNotificationCoordinator` owns authorization, APNs/FCM registration, backend synchronization, and pending tap state.
- `AppDelegate` bridges APNs and Firebase Messaging callbacks and presents system banners in the foreground.
- Registration occurs after authentication and retries on foreground activation.
- The app icon badge is preserved when the app becomes active and is cleared after Notification Center marks durable Social notifications read.
- A notification tap records its durable ID and type. The app selects Social and routes connection requests directly to Connections; other types open Notification Center, refresh its durable items, and route to the matching detail when present.
- The in-app bell counts unresolved actionable durable notifications, whether read or unread, plus one actionable item when Apple Health imports await review. Cheers and informational updates do not inflate it.
- Circle inbox rows render localized client copy from the semantic type and actor rather than displaying server-authored English. The Circle MVP is complete without push; adding Circle types to OS delivery remains subject to a later notification rollout.
- `push_notification_opened` records the share-safe notification type and selected destination (`connections` or `notifications`).
- User-facing permission text is provided by the system. Any future custom permission primer must use localized strings.

## Notification Center Presentation Policy

The clients centralize classification, ranking, aggregation eligibility, and destination selection in a notification presentation policy. Views do not independently reinterpret raw type strings. Sections always appear in this order:

1. **Needs you**: unresolved actions or genuinely time-sensitive invitations.
2. **Updates**: substantive state changes and conversations.
3. **Cheers & milestones**: encouragement and completed shared goals.

Within **Needs you**, `liveCheerInvitation` sorts first because the type itself identifies an active, expiring live session. On iOS, the single Apple Health batch follows live invitations. Remaining actionable items sort newest first. The payload does not currently expose event start times or invitation expiry, so clients must not infer starting-soon or expiring-soon priority for other types. **Updates** and **Cheers & milestones** sort newest first. The server still returns at most 50 durable records.

### Type, tier, and routing table

| Type/source | Current source | Tier | iOS destination | Android destination |
| --- | --- | --- | --- | --- |
| `liveCheerInvitation` | Backend durable | Needs you, live-first | Authorized live Cheer follower | Live sharing/follower |
| `connectionRequest` | Backend durable | Needs you | Connections | Connections |
| `runInvitation` | Backend durable | Needs you | Activity-event invitation actions | Social invitation |
| `circleInvitation` | Backend durable | Needs you | Circle invitation actions | Social invitation |
| `groupRunInvitation` | Route-only/future | Needs you | Generic notification detail until a standalone safe group-session destination exists | Live group run |
| Apple Health import candidates | iOS local-only batch | Needs you, after live | Import review | Not applicable; no synthetic Health Connect inbox item |
| `connectionAccepted` | Backend durable | Updates | Connections | Connections |
| `comment` | Backend durable | Updates | Shared activity/post | Shared activity/post |
| `invitationAccepted` | Backend durable | Updates | Activity event when locally available, otherwise generic detail | Activity event |
| `activityEventJoined` | Backend durable | Updates | Activity event when locally available, otherwise generic detail | Activity event |
| `circleInvitationAccepted` | Backend durable | Updates | Circle when locally available, otherwise generic detail | Circle |
| `circleOwnershipTransferred` | Backend durable | Updates | Circle when locally available, otherwise generic detail | Circle |
| `activity` | Route-only/future | Updates | Generic notification detail | Activity history/detail |
| `groupRunStarted` / `groupRunUpdated` | Route-only/future | Updates | Generic notification detail until a standalone safe group-session destination exists | Live group run |
| `liveShare` / `liveShareStarted` / `liveShareUpdated` | Route-only/future | Updates | Authorized live follower | Live sharing/follower |
| `cheer` | Backend durable | Cheers & milestones | Shared activity/post | Shared activity/post |
| `circleCheer` | Backend durable | Cheers & milestones | Circle when locally available, otherwise generic detail | Circle |
| `circleWeeklyGoalCompleted` | Backend durable | Cheers & milestones | Circle when locally available, otherwise generic detail | Circle |
| Unknown future durable type | Future backend | Updates | Generic notification detail | Generic notification detail |
| `local_workout_reminder` | OS-only local schedule | Outside inbox | Today/start context | Platform reminder destination; never durable inbox data |

An unknown type is never filtered out. It receives the default **Updates** classification, renders the backend's existing share-safe message, and opens a generic detail destination. A missing object ID also degrades to generic detail instead of crashing.

### Read, resolution, aggregation, and attention

- Opening Notification Center marks durable records read. Reading is presentation state only; it does not accept, decline, cancel, or otherwise resolve an invitation.
- Existing mutations remain the authority for resolution. Handled connection, activity-event, and Circle invitations delete their matching durable notification. Activity-event invitations are omitted from Notification Center once the event has ended. Read actionable records continue to count in the in-app attention badge until the backend removes them.
- Repeated `cheer` records collapse only when they share the same non-empty post ID. Repeated `circleCheer` records collapse only when they share the same non-empty Circle ID. The newest real notification supplies the visible message, actor/avatar, date, and tap destination; the row adds only a localized count of additional records. Notifications with missing object IDs never aggregate.
- `circleWeeklyGoalCompleted` is already deduplicated by its backend key. The iOS Health import card remains a single local batch with its real candidate count.
- iOS push sets the app-icon badge only for actionable durable types (`liveCheerInvitation`, `connectionRequest`, `runInvitation`, `circleInvitation`, and future `groupRunInvitation`). Informational pushes leave the current system badge unchanged. Opening Notification Center clears the system badge after marking records read; the in-app bell continues to show unresolved actionable attention.
- Android's prominent in-app bell uses the same actionable policy. OS launcher dots remain platform-controlled delivery affordances rather than a second inbox count.

### Analytics

The provider-neutral contract records `notification_center_opened`, one `notification_section_exposed` event per visible tier, and `notification_action_selected`. Properties are bounded to section (`needs_you`, `updates`, or `cheers_milestones`), category (`actionable`, `update`, `support`, or the local `health_import` category), single/aggregated/batched selection, and coarse count bucket. Notification copy, actor names, object IDs, titles, and health details are never analytics properties. There is no aggregation-expansion event because aggregated rows do not expose a separate expansion control.

## Configuration and Rollout

1. Apply the schema: `cd backend && npm run db:push`.
2. Register both Firebase apps: iOS `plainstride.outbound` and Android `com.plainstride.outbound`. Download `google-services.json` for the Android build through the normal secret/configuration path; do not commit production credentials.
3. In Firebase Console, upload the APNs authentication key for the iOS app and ensure its App ID/provisioning profiles include Push Notifications.
4. Deploy the backend with `FIREBASE_PROJECT_ID` (or `GOOGLE_CLOUD_PROJECT`) and application-default credentials whose service account can send Firebase Cloud Messaging messages. No FCM server key belongs in source or client configuration.
5. Validate APNs and Android FCM independently on physical devices; simulators and the local Firebase Auth emulator do not provide a production delivery check.

## Local Workout Reminders

Workout reminders are an on-device feature owned by `WorkoutNotificationScheduler`. They do not use Firebase, APNs delivery, FCM tokens, backend connectivity, or Notification Center.

- Reminders default to enabled at 6:00 AM for new installations. Existing explicit reminder choices are preserved.
- On first entry into the authenticated app experience, the enabled default requests notification authorization once. Denial turns reminders off; later app activation does not repeatedly request permission.
- The runner can change the local reminder time in Settings. The scheduler maintains a rolling 14-day set from backend-scheduled workouts or the current and next cached template weeks, and replaces requests idempotently with stable `plainstride.workout.*` identifiers.
- Only planned workout days are eligible. Rest days, optional/rest entries, removed workouts, and completed days are silent. There is never a missed-workout debt or make-up reminder.
- The scheduler reconciles after app activation, account changes, plan refresh/change/removal, reminder preference changes, locale-sensitive plan refreshes, and local activity saves. A qualifying activity on the same calendar day cancels the remaining reminder for that day.
- Lock-screen copy is concise, localized English, Spanish, or Simplified Chinese, and excludes readiness, health, cycle, location, and private plan details. Taps route to Today and the matching start-confirmation context when the cached workout is still available; otherwise they land safely on Today.
- Local reminder payloads use `type = local_workout_reminder` and remain distinct from durable Social payloads. Social authorization, foreground presentation, APNs registration, FCM token registration, and Social tap routing remain owned by `PushNotificationCoordinator` and `AppDelegate`.
- Debug builds show authorization status, the pending-request count, the next reminder time, and a `Send test notification in 10 seconds` action in Workout reminder settings. The test action validates local iOS presentation independently from plan scheduling.

### Local Reminder Analytics

The provider-neutral event contract records setting enabled/disabled, permission result, schedule/cancel outcome with bounded non-sensitive reasons, notification opened, and workout started from a local reminder. It does not claim delivery, log notification text, plan details, health data, or exact scheduled timestamps.

### Platform Limitations

iOS Focus modes, notification settings, Scheduled Summary, device power state, and user-level notification choices can delay, summarize, or suppress a local notification. The app treats a scheduled request as a request only and does not infer delivery from it.

## Deferred Scope

- Per-category and quiet-hour preferences beyond the single workout reminder time.
- Motivation notifications.
- Delivery analytics and an outbox worker with retries.
- Notification Service Extension media or mutable content.
- Additional non-FCM Android providers; see `docs/mainland-china-readiness.md` before choosing that architecture.
