# Garmin Integration Direction

Open when planning Garmin account linking, activity import, training export, or a Connect IQ companion.

## Decision and status

- Bruce chose to document the companion options and **focus on Garmin integration first**. A Connect IQ watch app is deferred.
- Recommended sequence: Garmin Connect activity import, then export of Plainstride training workouts. This sequence is a proposal, not an approved detailed design or a claim of partner access.
- Bruce confirmed that Plainstride has no Garmin API access yet. Approval and credentials are outstanding; no application submission was verified. No Garmin cloud integration or Connect IQ app was implemented in this task. Existing Garmin-via-Apple-Health imports are a separate path.

## Access prerequisite

**First prerequisite:** apply for Garmin Connect Developer Program Business Starter access and establish the actual entitlement, user limit, delivery contract, and credentials before committing to an implementation schedule. Prepare Plainstride's activity-import and training-export use cases, privacy policy, account-linking/disconnect description, and expected initial user count for that request.

Public sources checked November 21, 2026:

- [Program overview](https://developer.garmin.com/gc-developer-program/overview/) advertises Business Starter access to Activity and Training, limited users, push-only delivery, and no historical backfill. Confirm the applicable commercial terms and limits with Garmin; the public page does not establish Plainstride's eligibility or approval.
- [Starter access request](https://www.garmin.com/en-US/forms/StarterGarminConnectDeveloperAccess/) exists, but requires JavaScript. Form submission and the full required fields were not verified.
- [Program FAQ](https://developer.garmin.com/gc-developer-program/enterprise/program-faq/) describes OAuth 2.0, distinguishes the Garmin Connect API and Connect IQ programs, and places detailed integration documentation behind approval.

Do not invent endpoint URLs, payloads, token lifetimes, webhook authentication, retry guarantees, or supported training semantics from these public descriptions. A Business Starter import must not promise historical Garmin activity import; reassess if Garmin grants a different delivery tier.

## Recommended phases

### 1. Account linking and new activity import

- After access, verify the approved API documentation and sandbox/sample delivery. Define supported sports and required versus optional metrics before building the adapter.
- Implement explicit per-account consent and a connected-source surface with connection state, last sync/result, retry guidance, and disconnect. Explain which workout data is imported, how it informs guidance, and any lack of backfill.
- Keep credentials server-side, encrypted at rest; follow Garmin's verified token refresh/revocation contract. Handle expired/revoked consent and account deletion. Disconnect must stop new processing, invalidate pending deliveries, and remove stored credentials; decide and disclose whether previously imported activities remain or are deleted.
- Persist accepted deliveries durably before acknowledging them according to the verified contract. Retry processing independently, tolerate duplicates/out-of-order deliveries, and use stable account/provider activity identity for idempotent ingestion. Define update/deletion behavior and safe diagnostics without raw health payloads or tokens.
- Normalize into the canonical activity pipeline rather than creating a second history store. Preserve activity/planning/statistics reconciliation and downstream consumers, including Circle contribution rules.
- Resolve **Garmin cloud + HealthKit duplicates** before enabling both paths: the same Garmin activity can already arrive as `garminViaHealth`. Different provider identifiers cannot be assumed equal. Prefer verified shared provenance; define conservative fallback matching and conflict handling, source precedence, enrichment, and deletion behavior. Do not merge activities solely because dates or durations resemble one another.
- Acceptance details still to decide: automatic import versus selection, supported sports/metrics/routes, freshness expectations, update reconciliation, duplicate confirmation UX, and treatment of disconnected/reconnected accounts. Account linking alone is not end-to-end import acceptance.

### 2. Training workout export

- Validate Garmin Training API capabilities and device support against Plainstride's actual prescriptions: warm-up/cooldown, interval repeats, time/distance targets, effort/pace bands, run/walk, and scheduled dates/timezones.
- Start with a bounded supported subset; make unsupported semantics visible rather than silently weakening a workout. Decide whether export is explicit or automatic, which calendar horizon is sent, and how edits, reschedules, deletion, retries, and disconnect affect already-exported workouts.
- Persist durable export identity and revision mappings so retries do not duplicate workouts. Avoid import/export loops. A returned activity must not earn exact planned-workout completion from a similar date/duration alone; retain the issued-prescription identity contract or leave it unassociated.
- Verify the complete path on a supported Garmin device: exported prescription, Garmin delivery/scheduling, recorded completion, cloud return, and one canonical Plainstride activity. Export acceptance and device availability are separate states.

### Implementation references

- `backend/src/routes/activities.ts`: existing import-source identity, transaction locking, canonical activity ingestion and reconciliation. Its current source allowlist includes `garminViaHealth`, not a verified direct-Garmin source contract; direct ingestion needs an explicit adapter/model decision.
- `backend/prisma/schema.prisma`: canonical `Activity` and existing source/recording identity fields. Define connection, durable delivery, provider identity and export mappings only after the partner contract is known.
- [Activity repository](activity-repository.md) and [performed-workout receipts](performed-workout-sync.md): canonical identity adoption, durable acknowledgements, revision ordering, exact completion association and transaction lock order. Reuse these guarantees for cloud ingestion; do not infer prescription credit from imported workout metrics.
- `backend/src/routes/planning.ts`, `backend/src/services/planning/types.ts`: existing today/state/suggestion responses and structured workout blocks. [Account calendar](account-calendar.md) owns logical schedule dates and account timezone handling.
- [Device integration](device-integration.md): existing HealthKit foundation and source attribution. [Backend architecture](backend-architecture.md): domain boundaries. [Product analytics](product-analytics.md): event/privacy contract.
- Instrument bounded link/import/export/disconnect outcomes, duplicate decisions and normalized failure categories in the implementation. Exclude tokens, provider/account/activity identifiers, workout metrics, coordinates, exact dates and raw payloads. Keep operational processing identities in access-controlled durable records, not product analytics.

## Deferred Connect IQ options

Connect IQ companion distribution is separate from Garmin Connect API approval. Neither option below requires Garmin cloud integration; neither is committed work.

| Option | Smallest useful scope | Rough effort |
| --- | --- | --- |
| Offline warm-up/stretch helper | Bundle Before run and a short after-run routine; exercise, side, countdown, pause/skip and vibration. No login, sync, recording, editor, narrated audio or new illustration system. | 2–4 engineering days for a prototype; 5–8 total for a polished release candidate and submission preparation. |
| Today workout viewer | Link a Plainstride account, fetch today's summary/steps, retain an offline cache with clear date/staleness and rest/completed states. No recording or Garmin cloud API. | 10–15 engineering days for a production-ready candidate, including secure pairing and device checks. |

Estimates assume one focused engineer, a narrow supported Garmin device family and access to a real device. They include implementation and basic device validation, exclude store review/waiting time, and do not guarantee approval. Broader device coverage, artwork, audio or new training execution materially changes the scope. Cloud integration cannot be estimated responsibly until access and detailed contracts are confirmed.

- Helper content already exists in `shared/stretch/catalog.json`: 40 movements, nine templates, EN/ES/ZH instructions, durations, bilateral and equipment/floor flags. See [stretch routines](stretch-routines.md) for safety cues and timer semantics; the watch player still needs its own implementation.
- Viewer data already exists under `/v1/planning/today` and `/v1/planning/activity-suggestion`, including title, duration, effort and steps; suggestions carry cache validity metadata. Missing work includes secure device pairing/approval, appropriately scoped watch credentials, refresh/revocation, a compact response, and watch UI/cache/error states. Existing phone sessions are not a ready-made watch-pairing flow.
