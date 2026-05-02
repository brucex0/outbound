# Backend Deploy

Open this when deploying or reconfiguring the GCP backend for Outbound.

## Current Deployment Shape

- Backend source lives in `backend/`.
- Runtime target is Google Cloud Run.
- The backend is now built as a standard Node service from `backend/Dockerfile`.
- Assistant chat works without a database as long as `APP_AI_KEY` is configured.
- Database-backed routes intentionally return `503` when `DATABASE_URL` is unset.

## Current GCP Project

- Project ID: `outbound-494602`
- Preferred account: `bruce.xia74@gmail.com`
- Suggested region: `us-central1`
- Suggested Cloud Run service name: `outbound-api`

## Required APIs

Enable these before the first deploy:

- `run.googleapis.com`
- `cloudbuild.googleapis.com`
- `artifactregistry.googleapis.com`

Optional later, when the backend grows beyond assistant-only testing:

- `secretmanager.googleapis.com`
- `sqladmin.googleapis.com`

## Deploy Command

From the repo root:

```sh
$HOME/google-cloud-sdk/bin/gcloud run deploy outbound-api \
  --project=outbound-494602 \
  --account=bruce.xia74@gmail.com \
  --region=us-central1 \
  --source=backend \
  --env-vars-file=backend/.env \
  --allow-unauthenticated
```

## App Wiring

- `ios/Outbound/Outbound/Core/APIClient.swift` reads `OutboundAPIBaseURL` from `Info.plist`.
- `ios/Outbound/SupportFiles/Info.plist` is the place to point the app at a Cloud Run URL for testing.
- Default fallback remains `https://api.outbound.run/v1`, but that hostname is not currently live.

## Assistant-Only Reality Check

- Current local backend env has `APP_AI_KEY`.
- Current local backend env does not define `DATABASE_URL`.
- That means the first useful cloud deployment is assistant-focused, not full social/activity sync yet.
