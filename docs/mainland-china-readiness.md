# Mainland China Readiness

Open this when evaluating a mainland China launch, replacing Firebase Auth, adding China-specific login methods, or planning Android push delivery without Google Play services.

## Current Decision

- Mainland China is not a current launch target.
- Chinese users living outside mainland China use the standard product, localization, authentication, backend, and notification architecture.
- Do not add WeChat login, Chinese SMS login, China-specific hosting, or Android OEM push SDKs until mainland distribution becomes an explicit product goal.
- Keep new authentication and notification code modular enough that provider-specific implementations can be added later without changing product feature logic.

## Why Mainland Requires Separate Planning

Adding a China-friendly login button would not make the product reliable by itself. The complete path must be evaluated:

1. App-store distribution and required registrations.
2. Identity-provider availability.
3. App-to-backend connectivity and latency.
4. Email or SMS delivery.
5. Push delivery, especially on Android devices without Google Play services.
6. Data residency, privacy disclosures, SDK compliance, and other applicable regulatory requirements.
7. The complete live-coaching path from the regional Plainstride deployment through its selected AI endpoint, fixed-audio CDN, and operational monitoring.

A mainland launch should therefore be treated as a market/infrastructure project rather than a localized authentication feature.

## Authentication Findings

### First-Party Authentication

The iOS authentication path no longer contacts Firebase or Google. Native Sign in with Apple credentials go directly to the Plainstride backend, which verifies Apple and issues first-party sessions. This removes the former client-to-Google authentication dependency.

This does not complete mainland readiness: Apple reachability, API hosting, ICP and distribution work, media delivery, privacy compliance, and notification routing still require separate validation.

### Legacy Firebase Auth

- The backend can temporarily accept existing beta Firebase ID tokens when `AUTH_ACCEPT_LEGACY_FIREBASE=true`.
- This compatibility path is not used by the current iOS client and should be disabled after beta identities are reset or legacy traffic ends.

### Future Provider Authentication

Plainstride can add other providers to the same first-party session boundary:

- Apple: the iOS app obtains the Apple identity token and authorization code; the backend verifies the token and creates an Outbound session.
- Google: the native Google SDK obtains an ID token; the backend verifies it and creates an Outbound session. Google login remains unsuitable as the only mainland option.
- Email: a short verification code issued through an email provider is preferable to owning passwords and password-reset flows.
- Guest mode: local-first use can avoid blocking recording and onboarding on account creation, with sign-in deferred until cloud or social features are requested.
- WeChat: requires a verified WeChat Open Platform account, an approved mobile app, native SDK integration, and server-side exchange of the temporary authorization code. Keep the AppSecret on the server.
- Chinese phone numbers: dependable SMS generally requires a China-capable provider, business verification, approved message templates, consent/privacy work, abuse controls, and delivery testing by carrier.

The implemented session system uses short-lived access tokens, rotating refresh tokens, device-only Keychain storage, hashed refresh-token records, session revocation, and provider-neutral identities. Future provider linking must prove both identities and cannot rely only on email equality.

## Backend Availability

- Authentication changes do not help if the production API cannot be reached reliably.
- Before committing to mainland support, test the complete production API from multiple mainland networks and carriers, including login, token refresh, planning, activity sync, media, social, and live-sharing paths.
- Decide hosting, domain, CDN, data-location, and operational requirements only after measuring the current Cloud Run deployment from the target market and obtaining appropriate legal/compliance guidance.
- Live coaching now has a provider-neutral server router, but locale does not select market or authorize a mainland route. A future mainland route must explicitly validate provider terms/availability, deployed region, data handling, app-to-Plainstride latency, Plainstride-to-provider latency, fixed-pack delivery, and applicable distribution requirements before it becomes eligible.

## Push Notification Findings

Authentication and push delivery are independent decisions.

- iOS uses Apple Push Notification service (APNs), either directly or through a relay.
- Global Android can use Firebase Cloud Messaging (FCM).
- FCM requires compatible Google Play services and is not a complete mainland Android solution.
- Mainland Android commonly requires manufacturer channels such as Huawei/Honor, Xiaomi, OPPO, and vivo, or an aggregation service such as Tencent Push Notification Service.

Keep notification product logic provider-neutral. A device registration should identify at least the user, platform, delivery provider, provider token, locale, app version, preferences, and disabled/revoked state. A backend notification router should choose APNs, FCM, or a future mainland provider without exposing that choice to social, safety, planning, or reminder features.

## Recommended Revisit Sequence

When mainland China becomes an explicit target:

1. Define iOS/Android distribution goals and expected device mix.
2. Get legal and operational guidance for distribution, hosting, data, third-party SDKs, and messaging.
3. Measure the existing backend and login paths from representative mainland networks.
4. Validate the complete live-coaching route and fixed-audio CDN from representative networks; add a mainland provider route only after its eligibility facts and operational policy are approved.
5. Select at least one mainland-appropriate login path, likely Apple plus email for iOS and WeChat or verified phone/email options where justified.
6. Implement provider-neutral notification registration and routing.
7. Add Android manufacturer push channels directly or through an evaluated aggregator.
8. Test signup, refresh, account recovery, API access, live-coaching audio, notification delivery, and account deletion on real devices and carriers before launch.

## Primary References

- Apple: [Verifying a user](https://developer.apple.com/documentation/signinwithapple/verifying-a-user)
- Apple: [Setting up a remote notification server](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server)
- Google: [Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios/sign-in)
- Firebase: [Custom authentication on Apple platforms](https://firebase.google.com/docs/auth/ios/custom-auth)
- Firebase: [FCM requirements for Android](https://firebase.google.com/docs/cloud-messaging/android/get-started)
- WeChat Open Platform mirror: [Mobile application WeChat login guide](https://wdk-docs.github.io/wxopen-docs/mobile/login/guide.html)
- Tencent Cloud: [TPNS manufacturer channel integration](https://cloud.tencent.com/document/product/548/61135)
