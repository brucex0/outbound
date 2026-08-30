# Backend Deploy

Open this when deploying or reconfiguring the GCP backend for Outbound.

## Current Deployment Shape

- Backend source lives in `backend/`.
- Runtime target is Google Cloud Run.
- The backend is now built as a standard Node service from `backend/Dockerfile`.
- Assistant chat works without a database as long as `APP_AI_KEY` is configured.
- Database-backed routes intentionally return `503` when `DATABASE_URL` is unset.
- Repo-local npm installs should use the committed `.npmrc`, which points this repo at the public npm registry instead of a machine-level override.
- Production Postgres lives on the dedicated, private Cloud SQL instance `outbound-494602:us-central1:outbound-db`.
- The database on that instance is `outbound`; the old shared Boatshare database is no longer a runtime dependency.
- The live Cloud Run service has `DATABASE_URL` configured and database-backed routes are active.
- User-uploaded avatars use the `outbound-494602-avatars` GCS bucket in `us-central1`; Cloud Run sets `AVATAR_STORAGE_BUCKET=outbound-494602-avatars` and its runtime service account has object access there. Private activity photos use `MEDIA_STORAGE_BUCKET` when set and otherwise fall back to `<project-id>.firebasestorage.app`.
- Activity photos use the private `activity-photos/<user-id>/<activity-id>/` prefix. The API validates JPEGs up to 5 MB, owns all object keys, authenticates each download, and redirects it to a 15-minute signed URL; bucket objects must not be made public. A full Cloud CDN layer remains optional until media egress justifies it.

## Local Backend Run

Use this when you want the backend plus a local Postgres instance without Docker or Homebrew:

```sh
cd backend
npm install
npm run start:local
```

What it does:

- builds the backend
- starts an embedded Postgres instance under `backend/.local/postgres`
- creates the local `outbound` database if needed
- runs `prisma db push`
- enables the schema-declared `pg_trgm` extension and trigram indexes used by connection search
- seeds training plan template rows
- starts the API with `DATABASE_URL` pointed at the local embedded database

Default local database URL:

```sh
postgresql://outbound:outbound@127.0.0.1:54329/outbound?schema=public
```

Optional overrides:

- `OUTBOUND_PG_PORT`
- `OUTBOUND_PG_USER`
- `OUTBOUND_PG_PASSWORD`
- `OUTBOUND_PG_DATABASE`
- `DATABASE_URL`

## Current GCP Project

- Project ID: `outbound-494602`
- Preferred account: `bruce.xia74@gmail.com`
- Suggested region: `us-central1`
- Suggested Cloud Run service name: `outbound-api`
- Cloud Run runtime service account: `outbound-api-runtime@outbound-494602.iam.gserviceaccount.com`

## Required APIs

Enable these before the first deploy:

- `run.googleapis.com`
- `cloudbuild.googleapis.com`
- `artifactregistry.googleapis.com`
- `secretmanager.googleapis.com`
- `sqladmin.googleapis.com`
- `compute.googleapis.com`
- `servicenetworking.googleapis.com`
- `monitoring.googleapis.com`
- `billingbudgets.googleapis.com`
- `containeranalysis.googleapis.com`

## Current DB Connection

- Dedicated Cloud SQL instance: `outbound-494602:us-central1:outbound-db`
- Database: `outbound`
- Runtime DB user: `outbound_app`
- `outbound_app` should be treated as an app-owned credential, not a human admin login
- Runtime connections use the instance's private address with `sslmode=require`, `connection_limit=5`, and `pool_timeout=10`.

## Deploy Command

From the repo root:

```sh
./scripts/deploy-backend-gcloud.sh
```

Useful overrides:

- `PROJECT_ID`
- `GCLOUD_ACCOUNT`
- `REGION`
- `SERVICE`
- `RUNTIME_SERVICE_ACCOUNT`
- `CLOUD_SQL_INSTANCE`
- `CLOUD_RUN_CONCURRENCY`
- `CLOUD_RUN_MIN_INSTANCES`
- `CLOUD_RUN_MAX_INSTANCES`
- `SOURCE_DIR`
- `GCLOUD_BIN`
- `RUN_LOCAL_BUILD=0`
- `RUN_HEALTH_CHECK=0`
- `ALLOW_DIRTY_BACKEND=1`

The script runs a local backend build first, deploys `backend/` to Cloud Run with the dedicated identity, private VPC egress, Secret Manager bindings, concurrency 100, scale-to-zero enabled, and a one-instance ceiling, then prints the service URL and checks `/health`. The health probe retries transient HTTP and connection failures five times at five-second intervals by default; override `HEALTH_CHECK_RETRIES` or `HEALTH_CHECK_RETRY_DELAY_SECONDS` when needed. These are the pre-release minimal-cost defaults; raise the minimum and maximum through the documented overrides when public-release traffic requires it.

Raw command equivalent:

```sh
$HOME/google-cloud-sdk/bin/gcloud run deploy outbound-api \
  --project=outbound-494602 \
  --account=bruce.xia74@gmail.com \
  --region=us-central1 \
  --source=backend \
  --allow-unauthenticated \
  --service-account=outbound-api-runtime@outbound-494602.iam.gserviceaccount.com \
  --network=default --subnet=default --vpc-egress=private-ranges-only \
  --concurrency=100 --min=0 --max=1 \
  --update-secrets=DATABASE_URL=outbound-database-url:latest,APP_AI_KEY=outbound-app-ai-key:latest,RESEND_API_KEY=outbound-resend-api-key:latest \
  --update-env-vars='FEEDBACK_EMAIL_FROM=Plainstride <info@plainstride.com>'
```

Notes:

- Do not pass `backend/.env` to `--env-vars-file`. That flag expects YAML or JSON map syntax, not dotenv format.
- Keep Cloud Run env and secret wiring on the service itself, then redeploy code with `--source=backend`.

## Live Coaching Audio Rollout

The deploy script defaults live coaching to `disabled`, enables only `en` and `zh-Hans` for the fixed-audio pilot, wires Alibaba routing to workspace `ws-i638drcm5lthrc29`, and keeps dynamic rollout at zero. Once provisioned, it binds `ALIBABA_AI_API_KEY` from Secret Manager entry `outbound-alibaba-ai-api-key`. Because server audio remains disabled, a code deploy cannot begin AI traffic by itself.

The same script forwards the enabled persona/voice allowlists, per-contract cue limits, cue validity/provider deadline, route-policy version, and Alibaba endpoint identity/region. The approved dated model and six product-to-provider voice mappings live inside the backend adapter; deployment values are explicit emergency/experiment overrides. See `docs/live-coach-operations.md` for the current mapping and increment `LIVE_COACH_CONFIG_VERSION` when a fresh rollout cohort assignment is intended.

Operational sequence:

1. Store the active key in Secret Manager as `outbound-alibaba-ai-api-key` and grant only the Cloud Run runtime identity access.
2. The scripts default to the configured workspace-specific Singapore endpoints. Dynamic cues use `qwen3-omni-flash-2025-12-01`; fixed assets use `qwen3-tts-instruct-flash-2026-01-26` through the workspace `/api/v1` endpoint and the complete instruction-capable six-voice `en`/`es`/`zh-Hans` map. Use deployment overrides only for a separately reviewed change.
3. Validate one request with `./scripts/generate-live-coach-audio.sh --smoke`.
4. Inspect the catalog with `./scripts/generate-live-coach-audio.sh --list`, then generate the 468 content-addressed review assets with `./scripts/generate-live-coach-audio.sh`.
5. Listen to every review WAV and mark every manifest entry approved. The active key ID is `live-coach-audio-2026-v1`; its public PEM is in the iOS plist and its private PEM is in Secret Manager as `outbound-live-coach-manifest-private-key`. Publish explicitly with `npm run live-coach:publish-audio -- --review-manifest PATH --approved` after loading the private key through a protected file or process environment.
6. Configure the immutable HTTPS manifest/asset URLs and set `LIVE_COACH_AUDIO_PACK_PUBLISHED=true`.
7. Deploy `fixed_only`, verify device playback and rollback, then deploy `dynamic` with a 0% rollout before raising the deterministic percentage.

Create the secret container, add the replacement key from a protected file, and grant the runtime identity access without putting the key in the command line:

```sh
$HOME/google-cloud-sdk/bin/gcloud secrets create outbound-alibaba-ai-api-key \
  --project=outbound-494602 \
  --replication-policy=automatic
$HOME/google-cloud-sdk/bin/gcloud secrets versions add outbound-alibaba-ai-api-key \
  --project=outbound-494602 \
  --data-file=/secure/path/alibaba-live-coach-api-key.txt
$HOME/google-cloud-sdk/bin/gcloud secrets add-iam-policy-binding outbound-alibaba-ai-api-key \
  --project=outbound-494602 \
  --member='serviceAccount:outbound-api-runtime@outbound-494602.iam.gserviceaccount.com' \
  --role='roles/secretmanager.secretAccessor'
```

Representative deploy environment (placeholders only):

```sh
ALIBABA_AI_API_KEY_SECRET=outbound-alibaba-ai-api-key \
ALIBABA_AI_ENABLED=true \
ALIBABA_AI_BASE_URL='https://WORKSPACE_ID.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1' \
LIVE_COACH_SERVER_AUDIO_MODE=fixed_only \
LIVE_COACH_AUDIO_PACK_PUBLISHED=true \
LIVE_COACH_AUDIO_MANIFEST_URL='https://cdn.example/live-coach/2026-08-28.1/manifest.json' \
LIVE_COACH_AUDIO_ASSET_BASE_URL='https://cdn.example/live-coach/2026-08-28.1/assets' \
./scripts/deploy-backend-gcloud.sh
```

Startup rejects enabled configurations with an incomplete pack, non-HTTPS URLs, missing secret/model/voice mappings, or prematurely enabled subscription mode. To stop new AI cost immediately while retaining reviewed fixed audio, redeploy with `LIVE_COACH_SERVER_AUDIO_MODE=fixed_only`. Use `disabled` when server audio itself must be unavailable; the iOS app never re-enables Apple speech.

Publication requires `LIVE_COACH_AUDIO_MANIFEST_SIGNING_KEY_ID=live-coach-audio-2026-v1` and the Secret Manager ES256 private PEM supplied to `LIVE_COACH_AUDIO_MANIFEST_PRIVATE_KEY` without logging it. Keep the private key outside the repo. The app verifies the signed envelope before accepting a remote manifest, then verifies each WAV by SHA-256. A missing/unknown public key or invalid signature leaves the last-known-good or bundled pack untouched.

## Secret Manager Plan

First-party authentication additionally requires `APPLE_CLIENT_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, `AUTH_ACCESS_KEY_ID`, `AUTH_ACCESS_PRIVATE_KEY`, and `AUTH_ACCESS_PUBLIC_KEYS` (a JSON map containing the current and immediately previous ES256 public keys). Store private keys in Secret Manager. Set `AUTH_ACCEPT_LEGACY_FIREBASE=true` only during beta migration.

Local stack startup generates an ephemeral ES256 access-token key pair in memory when those auth variables are not supplied. Do not create or commit development PEM files; set the environment variables explicitly only when stable local keys are required across restarts.

Never set `AUTH_ENABLE_DEBUG_PERSONAS` in production; startup deliberately fails if it is true. Local development uses the explicitly committed `backend/config/dev-auth-*.pem` fixture key, which must never be deployed.

`DATABASE_URL`, `APP_AI_KEY`, `RESEND_API_KEY`, and `ALIBABA_AI_API_KEY` are Secret Manager references on Cloud Run. Never reintroduce their values as ordinary environment variables. Set `FEEDBACK_EMAIL_FROM` to a sender on a verified mail-provider domain; `FEEDBACK_EMAIL_TO` is optional and defaults to the private product-feedback inbox.

Recommended secrets:

- `outbound-database-url`
- `outbound-app-ai-key`
- `outbound-resend-api-key`
- `outbound-alibaba-ai-api-key`

Provision first-party production authentication in one pass after downloading
the Apple `.p8` key:

```sh
APPLE_PRIVATE_KEY_FILE=/secure/path/AuthKey_8Z4P665DD3.p8 \
  ./scripts/provision-production-auth.sh
```

When the three authentication secrets and IAM bindings already exist, configure
Cloud Run, deploy, and verify health without replacing any secret versions:

```sh
CONFIGURE_ONLY=1 ./scripts/provision-production-auth.sh
```

The production defaults are Apple client ID `plainstride.outbound`, Team ID
`WT54K7D7VH`, Apple Key ID `8Z4P665DD3`, and access-token key ID
`production-v1`. Override them through the same-named environment variables.
The script deliberately refuses to overwrite existing secrets; signing-key
rotation requires overlapping current and previous public keys.

Create the secrets:

```sh
printf '%s' 'postgresql://outbound_app:REDACTED@PRIVATE_IP:5432/outbound?sslmode=require&connection_limit=5&pool_timeout=10' | \
  $HOME/google-cloud-sdk/bin/gcloud secrets create outbound-database-url \
    --project=outbound-494602 \
    --data-file=-

printf '%s' 'REDACTED_APP_AI_KEY' | \
  $HOME/google-cloud-sdk/bin/gcloud secrets create outbound-app-ai-key \
    --project=outbound-494602 \
    --data-file=-

printf '%s' 'REDACTED_RESEND_API_KEY' | \
  $HOME/google-cloud-sdk/bin/gcloud secrets create outbound-resend-api-key \
    --project=outbound-494602 \
    --data-file=-
```

If the secret already exists, add a new version instead:

```sh
printf '%s' 'SECRET_VALUE' | \
  $HOME/google-cloud-sdk/bin/gcloud secrets versions add SECRET_NAME \
    --project=outbound-494602 \
    --data-file=-
```

Grant the dedicated runtime identity access:

```sh
$HOME/google-cloud-sdk/bin/gcloud secrets add-iam-policy-binding outbound-database-url \
  --project=outbound-494602 \
  --member='serviceAccount:outbound-api-runtime@outbound-494602.iam.gserviceaccount.com' \
  --role='roles/secretmanager.secretAccessor'

$HOME/google-cloud-sdk/bin/gcloud secrets add-iam-policy-binding outbound-app-ai-key \
  --project=outbound-494602 \
  --member='serviceAccount:outbound-api-runtime@outbound-494602.iam.gserviceaccount.com' \
  --role='roles/secretmanager.secretAccessor'

$HOME/google-cloud-sdk/bin/gcloud secrets add-iam-policy-binding outbound-resend-api-key \
  --project=outbound-494602 \
  --member='serviceAccount:outbound-api-runtime@outbound-494602.iam.gserviceaccount.com' \
  --role='roles/secretmanager.secretAccessor'
```

Wire the Cloud Run service to secrets:

```sh
$HOME/google-cloud-sdk/bin/gcloud run services update outbound-api \
  --project=outbound-494602 \
  --region=us-central1 \
  --set-secrets=DATABASE_URL=outbound-database-url:latest,APP_AI_KEY=outbound-app-ai-key:latest,RESEND_API_KEY=outbound-resend-api-key:latest \
  --update-env-vars='FEEDBACK_EMAIL_FROM=Plainstride <info@plainstride.com>'
```

Wire the Cloud Run job to secrets too:

```sh
$HOME/google-cloud-sdk/bin/gcloud run jobs update outbound-db-push \
  --project=outbound-494602 \
  --region=us-central1 \
  --set-secrets=DATABASE_URL=outbound-database-url:latest
```

Before executing the schema job, update it to the same image digest as the latest ready `outbound-api` revision. A stale job image can report success while applying an older Prisma schema. The job should run `npm run db:push -- --accept-data-loss` followed by `npm run seed:training-plans` so pre-publish constraint changes are accepted and the `TrainingPlanTemplate` catalog tables are populated after schema changes. `db:push` skips Prisma Client generation because the immutable runtime image already contains the generated client and runs as a non-root user.

After that, confirm the service and schema job contain `valueFrom.secretKeyRef`, not plaintext `value` entries.

Provider-side AI-key rotation is separate from Secret Manager migration: create a replacement key in the relevant AI provider, add it as a new Secret Manager version, verify the service, then revoke the old provider key. Assistant and Alibaba live-coach keys use separate secrets.

## Launch Operations

- Rate limiting is enforced in-process: 300 requests/minute per IP generally, 30/minute on auth, 20/minute on assistant/companion/guide, and 10/minute on transcription. These limits apply per warm instance; use an external shared limiter before adversarial-scale traffic.
- Run the representative health-path smoke load with `LOAD_TEST_BASE_URL=https://SERVICE_URL npm run load:smoke` from `backend/`. Override `LOAD_TEST_CONCURRENCY` and `LOAD_TEST_REQUESTS` as needed.
- Verify the uptime check, 5xx alert, Cloud SQL CPU/connections/storage alerts, and monthly budget notification after any project move.
- Restore test: clone the newest backup into a temporary instance, validate schema and representative rows, record the recovery time, then delete the temporary instance. The first drill completed August 18, 2026 using a 01:35 UTC point-in-time clone; all 10 seeded training-plan templates were present. Repeat this drill before launch after any material schema or backup-policy change.
- Owner access is currently limited to `bruce.xia74@gmail.com` and `cindyx@plainstride.com`. Both accounts must enforce MFA; keep these as emergency administrators and use narrower roles for routine work.

## Manual Schema Changes

Default rule for this repo:

- for manual schema fixes, prefer direct SQL in Cloud SQL Studio or `psql`
- do not rely on Cloud Run jobs for one-off schema debugging

Use a privileged DB login for manual DDL:

- `postgres`, if you have/reset that password
- or your own IAM DB user after granting it schema privileges

The runtime user `outbound_app` should stay focused on app access. Humans should not need to fetch its password for day-to-day schema work.

## Granting IAM DB Access

Run the following as a privileged DB user in the `outbound` database to let IAM user `bruce.xia74@gmail.com` fully administer the schema:

```sql
grant connect on database outbound to "bruce.xia74@gmail.com";

grant usage, create on schema public to "bruce.xia74@gmail.com";

grant all privileges on all tables in schema public to "bruce.xia74@gmail.com";
grant all privileges on all sequences in schema public to "bruce.xia74@gmail.com";
grant all privileges on all functions in schema public to "bruce.xia74@gmail.com";

alter default privileges for role outbound_app in schema public
grant all privileges on tables to "bruce.xia74@gmail.com";

alter default privileges for role outbound_app in schema public
grant all privileges on sequences to "bruce.xia74@gmail.com";

alter default privileges for role outbound_app in schema public
grant all privileges on functions to "bruce.xia74@gmail.com";
```

If you want the IAM user to be able to change ownership or manage privileges created by multiple roles later, use `postgres` for those operations instead of relying on grants alone.

## App Wiring

- `ios/Outbound/Outbound/Core/APIClient.swift` reads `OutboundAPIBaseURL` from `Info.plist`.
- `ios/Outbound/SupportFiles/Info.plist` is the place to point the app at a Cloud Run URL for testing.
- Default fallback remains `https://api.outbound.run/v1`, but that hostname is not currently live.

## Public Invite Links

- Canonical invite host: `https://run.plainstride.com`.
- Map that host to the `outbound-api` Cloud Run service and set `PUBLIC_WEB_BASE_URL=https://run.plainstride.com`.
- The same service serves the Plainstride marketing homepage at `/`, beta support at `/support`, and the public privacy policy at `/privacy`.
- Set `IOS_APP_STORE_URL` to the final App Store listing URL when App Store Connect assigns the numeric app ID. Until then, the checked-in default opens an App Store search for Plainstride.
- Set `ANDROID_PLAY_STORE_URL` to the production Play Store listing. Set `IOS_BETA_URL` and `ANDROID_BETA_URL` to TestFlight and Google Play testing enrollment links when those programs are active; omitted beta URLs are not shown.
- For Android App Links, set `ANDROID_PACKAGE_NAME` and comma-separated `ANDROID_SHA256_CERT_FINGERPRINTS` for every beta/production signing certificate that may open the canonical host.
- The backend serves `/.well-known/apple-app-site-association`, `/.well-known/assetlinks.json`, `/invite`, `/invite/*`, and `/live/group/:token` without API authentication.
- The iOS app declares `applinks:run.plainstride.com` and accepts live-group invitations immediately when authenticated or after the recipient signs in.
- The referral URL stays canonical across platforms and release channels. Installed apps claim it through Universal Links/App Links; otherwise the landing page shows the matching production store and any configured beta enrollment destination.

## Environment Reality Check

- The local backend can run assistant-only when `DATABASE_URL` is absent, or use the embedded Postgres workflow documented above.
- The live Cloud Run service is connected to the `outbound` Cloud SQL database, so authenticated activity, planning, personalization, safety, social, and account-deletion routes can use durable storage.
- After any Prisma schema change, deploy the API first, pin `outbound-db-push` to the new revision's exact image digest, and execute the job before relying on the changed route behavior.
- Fuzzy connection search requires the schema-declared `pg_trgm` extension and `User` trigram indexes. The route falls back to literal matching while the extension is absent; execute the pinned schema job to enable fuzzy results after deploying the matching image.
- Activity history sync requires the nullable `Activity.clientData`, `clientUpdatedAt`, `deletedAt`, and `updatedAt` fields. After deploying this change, run the pinned schema job before distributing the matching iOS build. Existing activity rows are restored through the route's legacy-field adapter and are upgraded to lossless client snapshots the next time a device with a local copy synchronizes.
- Activity photo sync requires the current `Photo` columns and uniqueness constraints. Deploy the API and run the pinned schema job before distributing the matching iOS build. Uploads are idempotent by `(activityId, clientPhotoId)`; the iOS client keeps local JPEGs, retries missing uploads at launch/foreground, and downloads authenticated copies when restoring history on another device.
- The coherent companion schema adds evidence, belief, episode, conversation, context-manifest, situational-signal, action, and outcome tables. Deploy the service image and execute the pinned `outbound-db-push` job before enabling `/v1/companion` clients against that revision.
- Live coaching adds session, metadata-only cue, entitlement, and usage-period tables and replaces the legacy guide persona/voice columns with stable product IDs. Run the pinned schema job with the documented pre-publish data-loss acceptance before enabling `/v1/live-coach`; no compatibility migration for pre-launch guide rows is maintained.
- Social workout presence adds `ActiveWorkoutPresence`. Deploy the API and run the pinned schema job before distributing the matching iOS build; the connection list treats missing or expired presence as inactive, so stale sessions fail closed.
- Cross-device settings add the one-to-one `UserPreferences` row and authenticated `GET`/`PUT /v1/auth/me/preferences`. Deploy the API and execute the pinned schema job before distributing the matching iOS build so a first client upload cannot reach a runtime with the old Prisma schema.
