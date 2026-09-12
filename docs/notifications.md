# In-App and Push Notifications

Open this when changing notification creation, delivery, device registration, foreground behavior, or tap routing.

## Product Contract

- The backend notification record is the source of truth. Push is a best-effort delivery channel, not a second inbox.
- V1 sends push for existing Social notification types: `connectionRequest`, `connectionAccepted`, `cheer`, `comment`, `runInvitation`, `invitationAccepted`, and `activityEventJoined`.
- Circle creates durable in-app records for `circleInvitation`, `circleInvitationAccepted`, `circleCheer`, `circleWeeklyGoalCompleted`, and `circleOwnershipTransferred`. Their object IDs route to an invitation or Circle; optional Cheer/completion delivery respects the per-Circle mute preference, while membership-critical state remains visible.
- The iOS Social notification inbox remains available when push permission is denied or delivery fails.
- Foreground notifications use the system banner, sound, and badge. Tapping a connection request selects Social and opens Connections; other pushes open the notification inbox.
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
- The app icon badge is preserved when the app becomes active and is cleared after the Social notification inbox is marked read.
- A notification tap records its durable ID and type. The app selects Social and routes connection requests directly to Connections; other types open Notifications, refresh the inbox, and route to the matching notification detail when present.
- Circle inbox rows render localized client copy from the semantic type and actor rather than displaying server-authored English. The Circle MVP is complete without push; adding Circle types to OS delivery remains subject to a later notification rollout.
- `push_notification_opened` records the share-safe notification type and selected destination (`connections` or `notifications`).
- User-facing permission text is provided by the system. Any future custom permission primer must use localized strings.

## Configuration and Rollout

1. Apply the schema: `cd backend && npm run db:push`.
2. Register both Firebase apps: iOS `plainstride.outbound` and Android `com.plainstride.outbound`. Download `google-services.json` for the Android build through the normal secret/configuration path; do not commit production credentials.
3. In Firebase Console, upload the APNs authentication key for the iOS app and ensure its App ID/provisioning profiles include Push Notifications.
4. Deploy the backend with `FIREBASE_PROJECT_ID` (or `GOOGLE_CLOUD_PROJECT`) and application-default credentials whose service account can send Firebase Cloud Messaging messages. No FCM server key belongs in source or client configuration.
5. Validate APNs and Android FCM independently on physical devices; simulators and the local Firebase Auth emulator do not provide a production delivery check.

## Local Workout Reminders

Workout reminders are an on-device feature owned by `WorkoutNotificationScheduler`. They do not use Firebase, APNs delivery, FCM tokens, backend connectivity, or the Social notification inbox.

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
- Android channel/provider support; see `docs/mainland-china-readiness.md` before choosing that architecture.
