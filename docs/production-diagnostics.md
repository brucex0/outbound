# Production Logs And Database Diagnostics

Open this when diagnosing a production request, user account, activity, live-coach session, or entitlement. Use the log-to-database correlation workflow below; Cloud Run request logs intentionally do not contain usernames.

## Production Identifiers

- Google Cloud project: `outbound-494602`
- Operator account: `bruce.xia74@gmail.com`
- Region: `us-central1`
- Cloud Run service: `outbound-api`
- Cloud SQL instance: `outbound-494602:us-central1:outbound-db`
- Database: `outbound`
- Runtime database user: `outbound_app`
- Database URL secret: `outbound-database-url`
- Runtime service account: `outbound-api-runtime@outbound-494602.iam.gserviceaccount.com`
- Reusable scratch job: `outbound-db-query-once`

The database has private IP only. A laptop-side Cloud SQL Auth Proxy cannot reach it without a route into the project VPC. Run production database diagnostics as a Cloud Run Job attached to `default/default` with `private-ranges-only` egress.

## Credentials And IAM

Use the existing Google login for `bruce.xia74@gmail.com`. If it is not already authenticated, the human owner must complete:

```sh
$HOME/google-cloud-sdk/bin/gcloud auth login bruce.xia74@gmail.com
```

Never ask an agent to collect the Google password, MFA code, database password, access token, or secret value in chat.

Minimum access by task:

| Task | Human/operator access | Runtime identity access |
| --- | --- | --- |
| Read Cloud Run logs | `roles/logging.viewer` | None |
| Inspect services and jobs | `roles/run.viewer` | None |
| Configure and execute the scratch job | `roles/run.developer` plus `roles/iam.serviceAccountUser` on the runtime service account | Existing VPC access |
| Mount the database secret in the job | The human does not need the plaintext secret | `roles/secretmanager.secretAccessor` for `outbound-database-url` |

The current `outbound_app` database credential is application-owned and can write. A diagnostic is read-only because its code performs only bounded `find*`, `count`, or `SELECT` operations—not because the credential is technically read-only. Never run Prisma mutations, DDL, `prisma db push`, seed commands, or SQL other than `SELECT` in a diagnostic job.

Human access to the plaintext secret through `roles/secretmanager.secretAccessor` is not required or recommended. Mount the secret by reference in Cloud Run instead. Never print `DATABASE_URL`, pass it as an ordinary environment value, store it in a temporary file, or commit it.

## Read Server Logs

Confirm the active identity:

```sh
$HOME/google-cloud-sdk/bin/gcloud auth list \
  --filter='status:ACTIVE' \
  --format='value(account)'
```

For general recent logs, use the repository helper:

```sh
LOG_FRESHNESS=6h LOG_LIMIT=500 ./scripts/monitor-backend-logs.sh recent
./scripts/monitor-backend-logs.sh recent-errors
```

For a live-coach incident, convert the runner's local time to an explicit UTC range and query request logs directly:

```sh
$HOME/google-cloud-sdk/bin/gcloud logging read \
  'resource.type="cloud_run_revision" AND resource.labels.service_name="outbound-api" AND timestamp>="START_UTC" AND timestamp<="END_UTC" AND (httpRequest.requestUrl:"/v1/live-coach" OR textPayload:"[live-coach]")' \
  --project=outbound-494602 \
  --account=bruce.xia74@gmail.com \
  --order=asc \
  --limit=1000 \
  --format='csv[no-heading](timestamp,httpRequest.requestMethod,httpRequest.status,httpRequest.latency,httpRequest.responseSize,httpRequest.requestUrl)'
```

Use the first successful `POST /v1/live-coach/sessions` as the session start. Copy the opaque session ID from later URLs such as `/v1/live-coach/sessions/SESSION_ID/cues/stream`. Do not infer the user from IP address, display name, or request timing.

Useful signals:

- `201` on `/sessions` means the phone created a server session.
- Repeated `200` cue requests with very small responses and sub-100 ms latency usually mean metadata/fallback responses, not generated audio.
- `4xx` points to authentication, validation, entitlement, or session-state rejection.
- `5xx` or `[live-coach] request failed` points to backend/provider failure.
- Request logs identify paths and status but not the authenticated username; resolve ownership through the database.

## Read The Production Database

Use the existing `outbound-db-query-once` job. Treat it as scratch state: inspect its command before every execution because another operator may have changed it.

```sh
$HOME/google-cloud-sdk/bin/gcloud run jobs describe outbound-db-query-once \
  --project=outbound-494602 \
  --region=us-central1 \
  --account=bruce.xia74@gmail.com \
  --format=yaml
```

Before executing, verify all of the following:

- the image is the immutable digest used by the active `outbound-api` revision;
- `DATABASE_URL` references `outbound-database-url:latest` rather than containing a value;
- the service account is `outbound-api-runtime@outbound-494602.iam.gserviceaccount.com`;
- networking is `default/default` with `private-ranges-only` egress;
- retries are zero;
- the command contains only bounded Prisma reads or `SELECT` statements;
- the username match is exact. Display names are not unique.

Get the current production image without guessing a tag:

```sh
PRODUCTION_IMAGE="$($HOME/google-cloud-sdk/bin/gcloud run services describe outbound-api \
  --project=outbound-494602 \
  --region=us-central1 \
  --account=bruce.xia74@gmail.com \
  --format='value(spec.template.spec.containers[0].image)')"
```

Configure a bounded username/session diagnostic. Replace `EXACT_USERNAME`; replace `EXACT_SESSION_ID` with the ID found in request logs, or set it to an empty string to return the ten most recent sessions. Keep the result projection small and exclude tokens, route coordinates, prompts, audio, health samples, and raw compiled context.

```sh
DIAGNOSTIC_USERNAME='EXACT_USERNAME'
DIAGNOSTIC_SESSION_ID='EXACT_SESSION_ID'

read -r -d '' DIAGNOSTIC_JS <<'JS' || true
const { PrismaClient } = require("@prisma/client");
const prisma = new PrismaClient();
(async () => {
  const username = process.env.DIAGNOSTIC_USERNAME;
  const sessionId = process.env.DIAGNOSTIC_SESSION_ID;
  const user = await prisma.user.findUnique({
    where: { username },
    select: { id: true, username: true, displayName: true, createdAt: true },
  });
  console.log("USER " + JSON.stringify(user));
  if (!user) return;
  const sessions = await prisma.liveCoachSession.findMany({
    where: { userId: user.id, ...(sessionId ? { id: sessionId } : {}) },
    orderBy: { createdAt: "desc" },
    take: 10,
    select: {
      id: true, createdAt: true, endedAt: true, status: true,
      locale: true, coachingContract: true, effectiveAudioMode: true,
      accessReason: true, plannerStatus: true, dynamicCueCount: true,
      cues: {
        orderBy: { createdAt: "asc" },
        take: 100,
        select: {
          createdAt: true, moment: true, source: true,
          resultCategory: true, latencyBucket: true,
        },
      },
    },
  });
  console.log("SESSIONS " + JSON.stringify(sessions));
  const entitlements = await prisma.featureEntitlement.findMany({
    where: { userId: user.id },
    select: {
      capability: true, source: true, status: true,
      startsAt: true, expiresAt: true, createdAt: true, updatedAt: true,
    },
  });
  console.log("ENTITLEMENTS " + JSON.stringify(entitlements));
  const usage = await prisma.featureUsagePeriod.findMany({
    where: { userId: user.id },
    select: {
      capability: true, periodKey: true, reservedCount: true,
      successfulCount: true, limitSnapshot: true, updatedAt: true,
    },
  });
  console.log("USAGE " + JSON.stringify(usage));
})().finally(() => prisma.$disconnect());
JS

$HOME/google-cloud-sdk/bin/gcloud run jobs update outbound-db-query-once \
  --project=outbound-494602 \
  --region=us-central1 \
  --account=bruce.xia74@gmail.com \
  --image="$PRODUCTION_IMAGE" \
  --command=node \
  --args="^|^-e|$DIAGNOSTIC_JS" \
  --set-env-vars="DIAGNOSTIC_USERNAME=$DIAGNOSTIC_USERNAME,DIAGNOSTIC_SESSION_ID=$DIAGNOSTIC_SESSION_ID" \
  --set-secrets=DATABASE_URL=outbound-database-url:latest \
  --service-account=outbound-api-runtime@outbound-494602.iam.gserviceaccount.com \
  --network=default \
  --subnet=default \
  --vpc-egress=private-ranges-only \
  --max-retries=0 \
  --task-timeout=300s

EXECUTION="$($HOME/google-cloud-sdk/bin/gcloud run jobs execute outbound-db-query-once \
  --project=outbound-494602 \
  --region=us-central1 \
  --account=bruce.xia74@gmail.com \
  --wait \
  --format='value(metadata.name)')"

$HOME/google-cloud-sdk/bin/gcloud beta run jobs executions logs read "$EXECUTION" \
  --project=outbound-494602 \
  --region=us-central1 \
  --account=bruce.xia74@gmail.com \
  --limit=200 \
  --format='value(timestamp,textPayload)'
```

Cloud Run Job startup can take several minutes. A quiet `--wait` period is normal. If the job fails, read that execution's logs before changing the query.

## Live-Coach Interpretation

Read these database fields together:

| Field | Meaning |
| --- | --- |
| `effectiveAudioMode=dynamic` | The session was allowed to request generated server audio. |
| `effectiveAudioMode=fixed_only` | The session could use only reviewed cached/fixed guidance. |
| `accessReason=entitlement_required` | Dynamic access was rejected by access policy. |
| `plannerStatus=fallback` | The dynamic plan was not generated; deterministic guidance was used. |
| `source=cached_fallback`, `resultCategory=unavailable` | The server could not return a matching playable cached asset for that cue. |
| `dynamicCueCount=0` | No dynamic cue completed successfully. |
| `successfulCount` at `limitSnapshot` | The trial allowance is exhausted when paywall enforcement is enabled; it must not restrict open access while the paywall is disabled. |

Duplicate cue rows a fraction of a second apart usually mean the client submitted the same detected moment more than once with different request IDs. Note this separately from the audio-access failure.

## Safety Rules

- Start with logs, then query only the exact user/session needed.
- Prefer exact username or the session ID from logs; never rely on display name alone.
- Use UTC timestamps in Cloud Logging and include the user's timezone in the incident summary.
- Do not log or retrieve authentication tokens, raw locations, route blobs, health samples, prompts, generated text, or audio.
- Do not expose secret values. A secret name is safe to document; its value is not.
- Do not execute a scratch job until its current command has been reviewed.
- Do not reuse `outbound-db-push`, seed jobs, or migration jobs for diagnostics.
- Report the production revision name, session ID, bounded findings, and a code-level explanation when available.
