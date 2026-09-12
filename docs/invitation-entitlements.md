# Invitations And Earned Entitlements

Open this when changing Plainstride Plus capability gates, referral rewards, contribution codes, or reward qualification.

## Paid Capability Contract

Plainstride Plus is one user-facing bundle backed by separate server capabilities:

- `ai_planning_dynamic`: Gemini-backed plan evaluation; users without access retain deterministic, safety-bounded plan adjustments.
- `live_coach_dynamic`: generated live-coaching plans and speech; users without access retain the reviewed fixed audio pack.
- `live_cheer_voice`: original voice cheers during live sharing; basic live location sharing remains free.

The backend is authoritative. A live-sharing session snapshots voice-cheer access at creation so expiration cannot interrupt an active run.

## Personal Invitation Rewards

- Existing `ReferralLink` codes are each user's permanent personal invitation code.
- Referral share copy tells recipients who install the app to return to the original message and tap the link again. The web invitation landing page repeats these steps because App Store installation does not preserve the referral URL.
- A new account can claim one inviter during its first seven days.
- The invitee immediately receives 14 days of Plus.
- The inviter receives 14 days after the invitee saves an activity lasting at least 10 minutes.
- Claims and grants are idempotent. Self-referrals and inviter changes are rejected.

## Client Surfaces

- Me contains separate entries for Plainstride Plus, Rewards Center, and My invitation code on iOS and Android.
- Rewards Center shows active earned or granted Plus capabilities. RevenueCat-only access remains on the separate Plus subscription screen.
- Rewards Center links to a dedicated code-redemption screen instead of embedding redemption fields in the reward summary.
- My invitation code owns the permanent personal code, share action, and qualified and pending invitation counts.

## Contribution Codes

Entitlement codes are high-entropy, stored only as SHA-256 digests, and grant a bounded Plus duration. Codes have a label, expiration, redemption limit, and revocation status. Issue one from `backend/` with:

```bash
npm run rewards:issue-code -- <label> [durationDays] [maxRedemptions]
```

The command prints the redeemable code once. Do not place codes in logs, analytics, or support transcripts.

## Grant Composition

`FeatureEntitlement` stores current effective access. `EntitlementGrantLedger` records immutable referral, contribution, and manual admin grants. Earned durations extend the active `earned_plus` expiration instead of replacing subscription, founding, promotional, or independently revocable admin grants.

RevenueCat store purchases use the independent `revenuecat` source. Its `plainstride_pro` entitlement grants the same capability bundle, but never replaces or shortens earned, founding, contribution, or admin access. See `docs/subscriptions.md` for purchase and reconciliation setup.

## API

- `GET /v1/rewards`: personal code, referral counts, claim state, and effective capability access.
- `POST /v1/rewards/referrals/claim`: claim a personal invitation code.
- `POST /v1/rewards/codes/redeem`: redeem a contribution entitlement code.
- Existing `POST /v1/social/referrals/:code/claim` uses the same reward service for universal-link compatibility.

## Rewards Administration API

All routes below require a valid Plainstride bearer token whose account email appears in the comma-separated `REWARDS_ADMIN_EMAILS` environment variable. An empty allowlist denies every admin request. Use verified first-party sign-in for the portal; never embed a shared admin token in browser code.

- `GET /v1/admin/rewards/me`: verify the current administrator.
- `GET /v1/admin/rewards/summary`: dashboard counts.
- `GET /v1/admin/rewards/codes`: list and filter contribution codes without exposing code material.
- `POST /v1/admin/rewards/codes`: issue a code with label, duration, redemption limit, expiration, and required reason. The plaintext code is returned once.
- `PATCH /v1/admin/rewards/codes/:id`: update a code label, expiration, or redemption limit without exposing its digest.
- `POST /v1/admin/rewards/codes/:id/revoke`: prevent future redemption.
- `POST /v1/admin/rewards/codes/:id/activate`: reactivate a non-expired code.
- `GET /v1/admin/rewards/redemptions`: inspect code usage.
- `GET /v1/admin/rewards/referrals`: inspect pending and qualified referrals.
- `GET /v1/admin/rewards/users` and `GET /v1/admin/rewards/users/:id`: find a user and inspect reward state.
- `POST /v1/admin/rewards/users/:id/grants`: grant bounded or permanent Plus access.
- `POST /v1/admin/rewards/users/:userId/entitlements/:entitlementId/revoke`: revoke one effective grant.
- `GET /v1/admin/rewards/audit`: inspect the immutable operator audit trail.

List endpoints accept bounded `limit` and `offset` pagination. Mutation bodies require a human-readable `reason`. Issuance, status changes, grants, and revocations are committed atomically with an `AdminRewardAuditEvent`. Audit metadata excludes plaintext reward codes.

Revoking an entitlement code blocks future use but deliberately leaves prior grants intact. Revoke an already-issued user entitlement separately when required.

Example issuance body:

```json
{
  "label": "September contributor",
  "durationDays": 90,
  "maxRedemptions": 1,
  "expiresAt": "2026-10-01T00:00:00.000Z",
  "reason": "Reward approved documentation contribution"
}
```

## Analytics And Privacy

The client records only reward-surface exposure, bounded code type, success/failure, share source, and bounded Me destination. Codes, user IDs, campaign labels, grant references, and expiration timestamps are excluded.

## Database Rebuild

This project uses Prisma schema push rather than checked-in migrations. Rebuild local data after adopting this schema:

```bash
cd backend
npm run db:rebuild
```
