# In-App and Push Notifications

Open this when changing notification creation, delivery, device registration, foreground behavior, or tap routing.

## Product Contract

- The backend notification record is the source of truth. Push is a best-effort delivery channel, not a second inbox.
- V1 sends push for existing Social notification types: `connectionRequest`, `connectionAccepted`, `cheer`, `comment`, `runInvitation`, `invitationAccepted`, and `activityEventJoined`.
- The iOS Social notification inbox remains available when push permission is denied or delivery fails.
- Foreground notifications use the system banner, sound, and badge. Tapping a push selects Social and opens the notification inbox.
- Push text contains the same share-safe message as the inbox. Do not put private plan, health, readiness, location, or cycle data in a push payload.
- Device tokens are user-scoped, may move between accounts, and are removed when Firebase reports them invalid or unregistered.

## Backend Contract

### Register a device

`PUT /v1/notifications/devices`

```json
{
  "token": "FCM registration token",
  "platform": "ios",
  "appBundle": "plainstride.outbound",
  "locale": "en_US"
}
```

The operation is authenticated and idempotent by token. It updates ownership, locale, enabled state, and `lastSeenAt`.

### Remove a device

`DELETE /v1/notifications/devices/:token`

Only the authenticated owner can remove the token.

### Delivery payload

Firebase Admin sends visible notification content plus these string data fields:

| Field | Meaning |
| --- | --- |
| `notificationId` | Durable `SocialNotification.id` |
| `type` | Notification routing category |
| `objectId` | Related connection, post, invitation, or event ID |
| `destination` | Currently `social.notifications` |

Creating the inbox record succeeds independently of push. Delivery errors are logged, while invalid tokens are deleted automatically.

## iOS Contract

- `PushNotificationCoordinator` owns authorization, APNs/FCM registration, backend synchronization, and pending tap state.
- `AppDelegate` bridges APNs and Firebase Messaging callbacks and presents system banners in the foreground.
- Registration occurs after authentication and retries on foreground activation.
- A notification tap sets `pendingNotificationID`; the app selects Social, opens Notifications, refreshes the inbox, and routes to the matching notification detail when present.
- User-facing permission text is provided by the system. Any future custom permission primer must use localized strings.

## Configuration and Rollout

1. Apply the schema: `cd backend && npm run db:push`.
2. In Firebase Console, upload the APNs authentication key for the iOS app `plainstride.outbound`.
3. Ensure the Apple Developer App ID and provisioning profiles include Push Notifications.
4. Deploy the backend with Firebase/Google application-default credentials that can send Firebase Cloud Messaging messages.
5. Validate on a physical device; the simulator and local Firebase Auth emulator do not provide a production delivery check.

## Deferred Scope

- Per-category and quiet-hour preferences.
- Scheduled workout and motivation reminders.
- Delivery/open analytics and an outbox worker with retries.
- Notification Service Extension media or mutable content.
- Android channel/provider support; see `docs/mainland-china-readiness.md` before choosing that architecture.
