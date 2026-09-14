# Rewards Administration Portal

Open this when deploying, configuring, operating, or changing the Plainstride rewards administration portal.

## Shape

- The backend serves the administration portal at `/admin`, with feature controls at `/admin/feature-controls` and rewards operations at `/admin/rewards`; it does not require a separate hosting project.
- Google Identity Services supplies a verified Google ID token. The portal exchanges it at `POST /v1/auth/google` for a first-party Plainstride access/refresh session.
- The access token remains in memory. The rotating refresh token is scoped to the browser tab with `sessionStorage` and is cleared on sign-out or when the tab closes.
- `GET /v1/admin/rewards/me` verifies the signed-in identity against `REWARDS_ADMIN_EMAILS` before the portal loads any administrative data.
- An authenticated but unapproved Google account receives no reward data and no administrative capability.

## Required Production Configuration

Create a Google OAuth 2.0 client of type **Web application** and add every production hostname used to open the portal as an authorized JavaScript origin. Cloud Run may expose both a legacy hashed service URL and a project-number service URL; both remain stable across ordinary revision deploys and should be registered once when both are used. For the production service these are:

```text
https://outbound-api-2hr6sz3bxa-uc.a.run.app
https://outbound-api-186140050970.us-central1.run.app
```

Deploying a new revision does not require updating these origins. Revisit the OAuth client only when adding or changing the service hostname, custom domain, project, or region.

The production deploy profile defaults the administrator allowlist to `GCLOUD_ACCOUNT` and uses Plainstride's web/server OAuth client. Override all three values when deploying another environment or changing the administrator:

```bash
REWARDS_ADMIN_EMAILS='approved.admin@example.com' \
REWARDS_ADMIN_GOOGLE_CLIENT_ID='WEB_CLIENT_ID.apps.googleusercontent.com' \
GOOGLE_AUTH_CLIENT_IDS='EXISTING_IOS_CLIENT_ID,EXISTING_ANDROID_SERVER_CLIENT_ID,WEB_CLIENT_ID.apps.googleusercontent.com' \
./scripts/deploy-backend-gcloud.sh
```

Rules:

- `REWARDS_ADMIN_EMAILS` is a comma-separated allowlist of verified Google account emails. Keep it narrow and require MFA on each account.
- `REWARDS_ADMIN_GOOGLE_CLIENT_ID` is public browser configuration, not a secret.
- The same web client ID must also appear in `GOOGLE_AUTH_CLIENT_IDS`, because the backend validates the ID token audience.
- Production startup fails when an admin allowlist is present but the portal client ID is missing or absent from the backend audience allowlist.
- Do not configure a client secret for browser code and do not add a shared administrator token.

After deployment, open the portal landing page:

```text
https://API_SERVICE_HOST/admin
```

## Operator Workflows

- Overview: inspect active codes, redemptions, entitlements, referral states, and user totals.
- Feature controls (a top-level administration page): inspect the current Plus paywall state and enable or disable entitlement enforcement. A change requires a reason and exact confirmation, takes effect immediately, and appears in the rewards audit history.
- Codes: filter, issue, edit, revoke, and reactivate contribution codes. A newly issued plaintext code appears once and is never recoverable from the API.
- Redemptions and referrals: paginate current code usage and referral qualification status.
- Users: search by username, name, or email; inspect entitlement and grant history; create bounded or permanent Plus grants.
- Revocation: supply a reason and type `REVOKE` before an effective entitlement can be revoked.
- Audit: filter the immutable mutation history by actor or target.

## Security And Privacy

- The portal is same-origin with the API and sends first-party bearer sessions over HTTPS.
- HTML and configuration responses are not cached. Security headers deny framing, disable unused browser capabilities, and restrict scripts, frames, connections, and styles to the portal and Google Identity Services.
- API responses and user-provided fields are escaped before HTML rendering.
- Mutations require a human-readable reason and the backend writes the authoritative audit record atomically with the change.
- Portal operational telemetry is allowlisted to page, operation, and success/failure values. It excludes account IDs, user IDs, emails, code material, campaign labels, grant references, reasons, exact expiration values, and raw errors.
- Do not paste one-time codes into logs, analytics, issue trackers, or support transcripts.

## Build-Only Verification

From `backend/`:

```bash
npm install
npm run build
```

This compiles both the backend route and browser client into `dist/`. The production container includes those compiled assets automatically.
