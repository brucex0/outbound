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
- A new account can claim one inviter during its first seven days.
- The invitee immediately receives 14 days of Plus.
- The inviter receives 14 days after the invitee saves an activity lasting at least 10 minutes.
- Claims and grants are idempotent. Self-referrals and inviter changes are rejected.

## Contribution Codes

Entitlement codes are high-entropy, stored only as SHA-256 digests, and grant a bounded Plus duration. Codes have a label, expiration, redemption limit, and revocation status. Issue one from `backend/` with:

```bash
npm run rewards:issue-code -- <label> [durationDays] [maxRedemptions]
```

The command prints the redeemable code once. Do not place codes in logs, analytics, or support transcripts.

## Grant Composition

`FeatureEntitlement` stores current effective access. `EntitlementGrantLedger` records immutable referral and contribution grants. Earned durations extend the active `earned_plus` expiration instead of replacing subscription, founding, or promotional grants.

## API

- `GET /v1/rewards`: personal code, referral counts, claim state, and effective capability access.
- `POST /v1/rewards/referrals/claim`: claim a personal invitation code.
- `POST /v1/rewards/codes/redeem`: redeem a contribution entitlement code.
- Existing `POST /v1/social/referrals/:code/claim` uses the same reward service for universal-link compatibility.

## Analytics And Privacy

The client records only reward-surface exposure, bounded code type, success/failure, and share source. Codes, user IDs, campaign labels, grant references, and expiration timestamps are excluded.

## Database Rebuild

This project uses Prisma schema push rather than checked-in migrations. Rebuild local data after adopting this schema:

```bash
cd backend
npm run db:rebuild
```
