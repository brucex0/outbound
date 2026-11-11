# Performed-workout receipts and sync

Open for planned recording attribution, offline completion, effective Today variants or activity upload retries.

## Current contract

- `performed-workout-v1` is a private server-issued reference: issuance ID/hash, original workout/plan-version IDs, optional retained edit ID/result revision, and `performedAsIssued`. Clients never invent a server revision.
- Immutable `WorkoutPrescriptionRevision` rows retain the exact canonical executable snapshot actually returned by Plan Details/planning state or Today, including read-time recovery/daily variants. Registration occurs at these launchable response boundaries under the planning-user lock; unseen intermediate mutations need no synthetic historical receipts. Same snapshot/provenance reuses its row. Eligibility/provenance participates in identity; earlier receipts are never relabeled.
- An edit reference is attached only when its retained effective recipe matches the issued current recipe. A later companion/daily mutation can issue a new non-edit recipe while the older edited receipt remains valid. A legitimate older cached recipe can complete after refill, direct edit or plan replacement; ownership stays on the original row/version.
- The saved local activity must retain the reference before Save succeeds and place it in private `clientData.performedWorkoutReference` in the existing upload outbox. Numeric `sessionEffortRating` remains optional/private. Optional `plannedWorkoutCompletionQuality` carries categorical suitability separately. No second completion queue or ordinary-run inference is used.
- Existing local setup goal/target/effort changes remain allowed where the owning UI permits them. Keep valid slot attribution but set `performedAsIssued=false` when the performed recipe changes. This explicitly prevents unchanged-prescription credit without claiming a new server revision. A different activity modality cannot earn unchanged running credit.

## Atomic reconciliation and history

- Lock order: planning-user advisory lock, then recording/import identity and activity rows. Every activity create, update, import deduplication and recording-session deduplication reconciles the receipt before committing. Activity, social activity record and completion association all succeed or roll back together.
- Nullable unique `WorkoutCompletion.activityId` permits one immutable canonical activity association. Retries reuse that completion; another workout, issued revision, edit linkage or performed-variant declaration cannot reassign it. Missing optional metadata preserves an existing association. Unknown unlinked manual/best-effort completion records are preserved separately; a reference alone is insufficient to guess which old physical recording they described.
- Actual duration, end time, distance, energy, heart rate/pace and reported effort come from the canonical saved activity. Prescribed target calories come from the retained receipt, so a performed500cal goal stays500 after a later300cal edit. Existing explicit completion quality is not erased by a default retry.
- Completion retires replacements only in the original plan/optional-slot scope. An inactive-plan receipt does not complete, supersede or enqueue reassessment for its replacement active plan. Actual saved activity remains available to normal history/load reads.
- `programmeExposureEligible` and `sourceExposureEligible` are distinct. Unchanged generic prescribed work can advance its ladder; authored re-entry work can advance only its own run/walk ladder. Effective recovery, explicit edits and locally changed recipes earn neither. Existing issued-dose/signature, adequate-duration, distinct-ID, fresh-readiness and exposure-clock guards still apply.

## Privacy and diagnostics

- The ledger, snapshots, reference hashes and ownership links are private planning/activity data. They are excluded from public activity/share/reflection projections and analytics. No receipt is placed in reflection prose.
- Expected conflicts return409 `performed_workout_conflict` and log only operation/category. Successful reconciliation logs bounded recorded/replayed, as-issued/local-variant and progression availability categories; no identifiers, hashes, exact ratings, activity measurements or text are logged.
- Both clients retain the receipt and categorical suitability in the local activity before acknowledging Save. Existing activity outboxes upload them privately; finish-review no longer uses a separate best-effort completion call. This does not establish native offline/relaunch delivery or authenticated deployed sync without runtime verification.

## Local schema/build verification

From `backend/`:

```sh
npm run db:generate
npm run build
```

The schema adds the immutable revision ledger, optional completion receipt/declaration and a unique canonical activity link. For a **dedicated local development database**, explicitly select its localhost `DATABASE_URL`, then use `npm run db:rebuild` to reset/reseed the current model. Do not point that reset command at a shared/production database. Existing synthetic caches/plans can be recreated; there is no historical receipt reader or inferred backfill.

The implementation worktree uses a private generated Prisma client (`node_modules/@prisma/client` and `.prisma`) while sharing other dependency links, so generation cannot overwrite frozen review checkouts. Those dependency files are untracked and never committed.

`/tmp/plainstride-issuance-demo.mjs` starts/stops its own isolated PostgreSQL database on localhost55462, pushes this schema, uses synthetic accounts and exercises real HTTP routes/services. Output is `/tmp/plainstride-issuance-output.jsonl`; build/generation logs are `/tmp/plainstride-issuance-build.log` and `/tmp/plainstride-issuance-prisma-generate.log`. It does not load production configuration or call model/providers. No existing test suite was run.

## iOS transport checkpoint

- Planning state and canonical Today decode the optional receipt into `SuggestedSession` and `SessionWorkoutReference`. `SessionWorkoutRecoverySnapshot` retains it across recording recovery. Existing local goal edits keep slot identity but mark `performedAsIssued=false`; choosing a different-sport route still drops the original workout identity.
- `SavedActivity` custom encoding/decoding, all enrichment/correction copies and private `ActivityClientExtras` preserve receipt and suitability independently of reflection. Missing receipts stay unknown; no historical cached recipe is guessed. Refresh/recreate synthetic cached plans to receive current receipts.
- The existing `-OutboundDebugPostRunSummary -OutboundDebugReceiptRoundtrip` route extends the production local-save/copy/encode roundtrip. `-OutboundDebugRunningPlan -OutboundDebugReceiptRoundtrip` with the synthetic response as Documents `planning-fixture.json` additionally traverses production API conversion, intent/recovery serialization, actual local persistence and private extras for as-issued and locally changed goals. These routes never upload and delete only their own synthetic local activity. They are prepared for native QA; actual UI/relaunch execution remains pending while the Mac is locked.
- Build: Apple Silicon simulator `Outbound.app` at `/tmp/outbound-durable-receipts-ios/Build/Products/Debug-iphonesimulator/Outbound.app`; log `/tmp/plainstride-durable-ios-build.log`. The bounded headless Swift demonstration extracts the production reference models, reads a real synthetic backend response and verifies identity/declaration serialization only: `/tmp/plainstride-durable-swift-reference.swift` and `-output.txt`. It does **not** execute the full native converter/coordinator/outbox chain.
- The response is `/tmp/plainstride-durable-client-planning.json`, emitted by `/tmp/plainstride-durable-client-fixture.mjs` using real services and an isolated localhost55466 database (stopped after output). No provider, production action or existing test suite is used.

## Android transport checkpoint

- Canonical Today receipts use the shared production `ActivitySuggestion.toWorkoutLaunchIntent` and `WorkoutLaunchIntent.toRecordingLaunch` conversions. Recording configuration serialization retains them for recovery. Different-sport route selection still removes attribution. Ordinary/manual unreferenced sessions remain neutral.
- Actual `RecordingViewModel.saveFinished` stores receipt and categorical suitability alongside optional numeric effort before returning success. Room v8 stores a private receipt JSON column plus suitability; the existing activity outbox encodes private `clientData` and the backend reconciles completion atomically. The former finish-review best-effort completion callback is removed. Normal manual completion APIs remain available.
- Current schema is `plainstride-v8.db`; only export8 is tracked. This unreleased app opens clean local activity/cache/journal/outbox data on upgrade, without copying older unsynced rows. Build/reset commands are in `android-build.md`.
- Headless `/tmp/ReceiptTransportDemo.java` executes compiled production serializers and both launch converters against the real synthetic response, then actual entity/domain mapping and private upload serialization/reload. `/tmp/plainstride-durable-android-jvm-output.txt` reports fourteen phases totaling1500seconds, exact receipt preservation, true/false performed declaration and retained optional effort/suitability. This verifies conversion/serialization; it does not execute Room transactions, recorder lifecycle, UI/relaunch or authenticated synchronization.
- Existing isolated `DebugSessionEffortHarness` additionally exercises actual `RecordingViewModel.saveFinished` with first local failure/retry and receipt reload/outbox checks, using a synthetic account, no token, no sync and no real recorder commands. Native execution remains pending while the Mac is locked. Build log: `/tmp/plainstride-durable-android-build.log`.
