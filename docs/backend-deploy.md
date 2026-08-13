# Backend Deploy

Open this when deploying or reconfiguring the GCP backend for Outbound.

## Current Deployment Shape

- Backend source lives in `backend/`.
- Runtime target is Google Cloud Run.
- The backend is now built as a standard Node service from `backend/Dockerfile`.
- Assistant chat works without a database as long as `APP_AI_KEY` is configured.
- Database-backed routes intentionally return `503` when `DATABASE_URL` is unset.
- Repo-local npm installs should use the committed `.npmrc`, which points this repo at the public npm registry instead of a machine-level override.
- Hosted Postgres currently lives on the shared Cloud SQL instance `boatshare-20260214-zxia:us-central1:boatshare-db`.
- The Outbound database on that instance is `outbound`.
- The live Cloud Run service has `DATABASE_URL` configured and database-backed routes are active.
- User-uploaded avatars use the `outbound-494602-avatars` GCS bucket in `us-central1`; Cloud Run sets `AVATAR_STORAGE_BUCKET=outbound-494602-avatars` and its runtime service account has object access there. Private activity photos use `MEDIA_STORAGE_BUCKET` when set and otherwise fall back to `<project-id>.firebasestorage.app`.
- Activity photos use the private `activity-photos/<user-id>/<activity-id>/` prefix. The API validates JPEGs up to 5 MB, owns all object keys, and proxies authenticated downloads; bucket objects must not be made public.

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
- Current Cloud Run runtime service account: `186140050970-compute@developer.gserviceaccount.com`

## Required APIs

Enable these before the first deploy:

- `run.googleapis.com`
- `cloudbuild.googleapis.com`
- `artifactregistry.googleapis.com`

Optional later, when the backend grows beyond assistant-only testing:

- `secretmanager.googleapis.com`
- `sqladmin.googleapis.com`

## Current DB Connection

- Shared Cloud SQL instance: `boatshare-20260214-zxia:us-central1:boatshare-db`
- Database: `outbound`
- Runtime DB user: `outbound_app`
- `outbound_app` should be treated as an app-owned credential, not a human admin login

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
- `SOURCE_DIR`
- `GCLOUD_BIN`
- `RUN_LOCAL_BUILD=0`
- `RUN_HEALTH_CHECK=0`
- `ALLOW_DIRTY_BACKEND=1`

The script runs a local backend build first, deploys `backend/` to Cloud Run, prints the service URL, and checks `/health`.

Raw command equivalent:

```sh
$HOME/google-cloud-sdk/bin/gcloud run deploy outbound-api \
  --project=outbound-494602 \
  --account=bruce.xia74@gmail.com \
  --region=us-central1 \
  --source=backend \
  --allow-unauthenticated
```

Notes:

- Do not pass `backend/.env` to `--env-vars-file`. That flag expects YAML or JSON map syntax, not dotenv format.
- Keep Cloud Run env and secret wiring on the service itself, then redeploy code with `--source=backend`.

## Secret Manager Plan

Goal:

- stop storing `DATABASE_URL` and API keys directly in Cloud Run env config
- keep runtime secrets machine-readable for Cloud Run without needing humans to know the values

Recommended secrets:

- `outbound-database-url`
- `outbound-app-ai-key`

Create the secrets:

```sh
printf '%s' 'postgresql://outbound_app:REDACTED@localhost/outbound?host=/cloudsql/boatshare-20260214-zxia:us-central1:boatshare-db' | \
  $HOME/google-cloud-sdk/bin/gcloud secrets create outbound-database-url \
    --project=outbound-494602 \
    --data-file=-

printf '%s' 'REDACTED_APP_AI_KEY' | \
  $HOME/google-cloud-sdk/bin/gcloud secrets create outbound-app-ai-key \
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

Grant Cloud Run access:

```sh
$HOME/google-cloud-sdk/bin/gcloud secrets add-iam-policy-binding outbound-database-url \
  --project=outbound-494602 \
  --member='serviceAccount:186140050970-compute@developer.gserviceaccount.com' \
  --role='roles/secretmanager.secretAccessor'

$HOME/google-cloud-sdk/bin/gcloud secrets add-iam-policy-binding outbound-app-ai-key \
  --project=outbound-494602 \
  --member='serviceAccount:186140050970-compute@developer.gserviceaccount.com' \
  --role='roles/secretmanager.secretAccessor'
```

Wire the Cloud Run service to secrets:

```sh
$HOME/google-cloud-sdk/bin/gcloud run services update outbound-api \
  --project=outbound-494602 \
  --region=us-central1 \
  --set-secrets=DATABASE_URL=outbound-database-url:latest,APP_AI_KEY=outbound-app-ai-key:latest
```

Wire the Cloud Run job to secrets too:

```sh
$HOME/google-cloud-sdk/bin/gcloud run jobs update outbound-db-push \
  --project=outbound-494602 \
  --region=us-central1 \
  --set-secrets=DATABASE_URL=outbound-database-url:latest
```

Before executing the schema job, update it to the same image digest as the latest ready `outbound-api` revision. A stale job image can report success while applying an older Prisma schema. The job should run `npm run db:push -- --accept-data-loss` followed by `npm run seed:training-plans` so pre-publish constraint changes are accepted and the `TrainingPlanTemplate` catalog tables are populated after schema changes.

After that, remove plaintext secret env vars from the service and job configs if they are still present.

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
- The backend serves `/.well-known/apple-app-site-association`, `/invite`, `/invite/*`, and `/live/group/:token` without API authentication.
- The iOS app declares `applinks:run.plainstride.com` and accepts live-group invitations immediately when authenticated or after the recipient signs in.
- Android App Links and Play Store fallback are intentionally deferred.

## Environment Reality Check

- The local backend can run assistant-only when `DATABASE_URL` is absent, or use the embedded Postgres workflow documented above.
- The live Cloud Run service is connected to the `outbound` Cloud SQL database, so authenticated activity, planning, personalization, safety, social, and account-deletion routes can use durable storage.
- After any Prisma schema change, deploy the API first, pin `outbound-db-push` to the new revision's exact image digest, and execute the job before relying on the changed route behavior.
- Activity history sync requires the nullable `Activity.clientData`, `clientUpdatedAt`, `deletedAt`, and `updatedAt` fields. After deploying this change, run the pinned schema job before distributing the matching iOS build. Existing activity rows are restored through the route's legacy-field adapter and are upgraded to lossless client snapshots the next time a device with a local copy synchronizes.
- Activity photo sync requires the current `Photo` columns and uniqueness constraints. Deploy the API and run the pinned schema job before distributing the matching iOS build. Uploads are idempotent by `(activityId, clientPhotoId)`; the iOS client keeps local JPEGs, retries missing uploads at launch/foreground, and downloads authenticated copies when restoring history on another device.
- The coherent companion schema adds evidence, belief, episode, conversation, context-manifest, situational-signal, action, and outcome tables. Deploy the service image and execute the pinned `outbound-db-push` job before enabling `/v1/companion` clients against that revision.
