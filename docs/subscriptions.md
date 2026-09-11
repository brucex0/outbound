# RevenueCat Subscriptions

Open this when configuring, releasing, or troubleshooting Plainstride Plus purchases on iOS or Android.

## Ownership

- Apple and Google own checkout and billing. RevenueCat normalizes store transactions and the subscription lifecycle.
- The RevenueCat App User ID is the opaque Plainstride account UUID. Never send email, name, workout, health, location, or coaching data.
- The RevenueCat entitlement identifier is `plainstride_pro` unless `REVENUECAT_PLUS_ENTITLEMENT_ID` explicitly overrides it on the backend.
- RevenueCat subscription state becomes the backend `revenuecat` grant for `ai_planning_dynamic`, `live_coach_dynamic`, and `live_cheer_voice`.
- The Plainstride backend remains the capability authority. Founding access, trials, referrals, contribution codes, and admin grants stay independent.

## Dashboard And Store Setup

1. Create one RevenueCat project with Apple and Google Play apps.
2. Create the `plainstride_pro` entitlement.
3. Create the `monthly`, `yearly`, and `lifetime` products in the RevenueCat Test Store. Before production, create their platform equivalents in App Store Connect and Google Play Console. `lifetime` is a non-consumable; `monthly` and `yearly` are auto-renewing subscriptions.
4. Attach every platform's `monthly`, `yearly`, and `lifetime` products to `plainstride_pro`. Add them to the Current Offering using the standard Monthly, Annual, and Lifetime package types. The hosted paywall reads that Current Offering, so no product IDs or prices are hard-coded in either client.
5. Configure and publish the RevenueCat paywall for the Current Offering, including localized terms and restore behavior. The clients use RevenueCat's localized, remotely configured paywall and its default paywall fallback.
6. Configure Customer Center in RevenueCat. It is shown only after the local `plainstride_pro` entitlement is active; dismissing it triggers backend reconciliation so cancellation, restore, and product-change results reach capability gates promptly.
7. Configure App Store credentials and the Google Play service account in RevenueCat.
8. Add a production webhook at `https://outbound-api-186140050970.us-central1.run.app/webhooks/revenuecat`, enable HMAC signing, and include production events.
9. Store the HMAC secret as `REVENUECAT_WEBHOOK_SIGNING_SECRET` and a RevenueCat v1 secret API key as `REVENUECAT_SECRET_API_KEY` in Cloud Run. Never add either secret to the clients or Git.

## Client Configuration

- iOS reads the public Apple SDK key from the `REVENUECAT_PUBLIC_SDK_KEY` build setting, exposed to the app as `RevenueCatPublicSDKKey` in `Info.plist`.
- Android Debug reads the supplied Test Store key by default and permits an override through `PLAINSTRIDE_REVENUECAT_DEBUG_PUBLIC_SDK_KEY`; Release reads the production Google key from `PLAINSTRIDE_REVENUECAT_PUBLIC_SDK_KEY`.
- These are public, platform-specific SDK keys, not RevenueCat secret API keys.
- The supplied `test_` key is compiled only into Debug builds. Release builds must use separate `appl_` and `goog_` keys; never ship the Test Store key. When a Release key is absent, RevenueCat is not configured and purchase UI remains hidden.
- Configure only after authentication with the known Plainstride account UUID. Do not call RevenueCat logout; purchase surfaces are unavailable while Plainstride is signed out, and the next account is selected with RevenueCat login. This avoids anonymous customers and cross-account entitlement transfer.
- iOS implementation lives in `Core/Subscriptions/RevenueCatSubscriptionStore.swift` and `App/RewardsCenterView.swift`; Android uses `subscriptions/RevenueCatCoordinator.kt` and `RewardsScreen.kt`. Both subscribe to customer-info updates, check `plainstride_pro`, present RevenueCat's hosted paywall, handle purchase/restore completion, and route active customers to Customer Center.

## Reconciliation

- Purchase and restore completion call `POST /v1/rewards/subscription/reconcile`, then refresh the normal rewards status.
- RevenueCat webhooks are verified over the raw body with `X-RevenueCat-Webhook-Signature` and a five-minute timestamp tolerance.
- Every accepted webhook fetches canonical customer state from `GET /v1/subscribers/{app_user_id}` before updating the backend grant.
- Reconciliation is idempotent. An absent or expired `plainstride_pro` entitlement expires only the `revenuecat` grant; other grant sources remain untouched.

## Release Gate

- Test new purchase, renewal, cancellation, billing retry/grace period, refund, restore, account switch, and cross-platform access in store sandboxes.
- Confirm the webhook test reaches the backend and a purchase activates all three Plus capabilities.
- Confirm removing the store entitlement expires only the `revenuecat` source.
- Do not enable `LIVE_COACH_ACCESS_MODE=subscription_required` or expose the purchase UI in a store build until the matching dashboard products, paywall, client public key, backend secret key, and signed webhook are configured.
