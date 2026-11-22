# Performed-workout receipts and sync

Open for planned recording attribution, offline completion, effective Today variants or activity upload retries.

## Current contract

- `performed-workout-v1` is a private server-issued reference: issuance ID/hash, original workout/plan-version IDs, optional retained edit ID/result revision, and `performedAsIssued`. Clients never invent a server revision.
- Immutable `WorkoutPrescriptionRevision` rows retain the exact canonical executable snapshot actually returned by Plan Details/planning state or Today, including read-time recovery/daily variants. Registration occurs at these launchable response boundaries under the planning-user lock; unseen intermediate mutations need no synthetic historical receipts. Same snapshot/provenance reuses its row. Eligibility/provenance participates in identity; earlier receipts are never relabeled.
- An edit reference is attached only when its retained effective recipe matches the issued current recipe. A later companion/daily mutation can issue a new non-edit recipe while the older edited receipt remains valid. A legitimate older cached recipe can complete after refill, direct edit or plan replacement; ownership stays on the original row/version.
- The saved local activity must retain the reference before Save succeeds and place it in private `clientData.performedWorkoutReference` in the existing upload outbox. Numeric `sessionEffortRating` remains optional/private. Optional `plannedWorkoutCompletionQuality` carries categorical suitability separately. No second completion queue or ordinary-run inference is used.
- Existing local setup goal/target/effort changes remain allowed where the owning UI permits them. Keep valid slot attribution but set `performedAsIssued=false` when the performed recipe changes. This explicitly prevents unchanged-prescription credit without claiming a new server revision. A different activity modality cannot earn unchanged running credit.

## Atomic reconciliation and history

### Upload acknowledgement and revisions

- `POST /v1/activities` keeps the canonical activity identity at the top level
  and returns `reconciliation = { planningRevision, statisticsRevision,
  completion }`. `completion` is either `null` or the canonical completion
  summary `{ activityId, plannedWorkoutId, planVersionId, status,
  prescribedDurationSeconds }`. The canonical identity behavior is unchanged;
  clients persist the acknowledgement before removing the accepted mutation
  from their pending outbox. Planning-state responses expose the same planning
  observation watermark as `revision`.
- `planningRevision` is the account's `User.planningStateRevision` observation
  watermark. It advances under the planning-user lock when planning state is
  assembled for a response or an activity is accepted. It is not a counter for
  every planning mutation. `planVersionId` remains the identity of the plan
  version that owns the workout and is not a mutation revision. Statistics
  uses its separate `statisticsRevision`, also returned by the accepted upload.
- Completion exposes the exact issued prescription duration in
  `prescribedDurationSeconds`. That value is distinct from current scheduled-slot
  progress minutes and from actual activity duration in history. Clients must
  not derive one from another.
- Generate and apply the additive backend schema before releasing clients that
  consume these acknowledgement fields. No database reset, historical backfill,
  or recreation of completed-workout IDs is required.

- Lock order: planning-user advisory lock, then recording/import identity and activity rows. Every activity create, update, import deduplication and recording-session deduplication reconciles the receipt before committing. Activity, social activity record and completion association all succeed or roll back together.
- Companion shorten/calorie actions acquire that same planning-user lock before reading the workout, blocks or estimate inputs, then calculate and mutate inside the transaction. This prevents a response assembled from one recipe from receiving a receipt for a concurrently changed recipe. The preference writer also locks its snapshot/write, commits, then calls the separately locked rebuild; it does not nest rebuild locks. Existing action summaries, accepted-outcome/evidence records and rollback behavior are unchanged.
- Nullable unique `WorkoutCompletion.activityId` permits one immutable canonical activity association. Retries reuse that completion; another workout, issued revision, edit linkage or performed-variant declaration cannot reassign it. Missing optional metadata preserves an existing association. Unknown unlinked manual/best-effort completion records are preserved separately; a reference alone is insufficient to guess which old physical recording they described.
- Actual duration, end time, distance, energy, heart rate/pace and reported effort come from the canonical saved activity. Prescribed target calories come from the retained receipt, so a performed500cal goal stays500 after a later300cal edit. Existing explicit completion quality is not erased by a default retry.
- Completion retires replacements only in the original plan/optional-slot scope. An inactive-plan receipt does not complete, supersede or enqueue reassessment for its replacement active plan. Actual saved activity remains available to normal history/load reads.
- `programmeExposureEligible` and `sourceExposureEligible` are distinct. Unchanged generic prescribed work can advance its ladder; authored re-entry work can advance only its own run/walk ladder. Effective recovery, explicit edits and locally changed recipes earn neither. Existing issued-dose/signature, adequate-duration, distinct-ID, fresh-readiness and exposure-clock guards still apply.

## Privacy and diagnostics

### Private completed-workout headings

- Save review and private History/Details use two independently truncating lines: workout name, then localized `Plan name: D#/wk#`. `D#` is the required workout's ordinal within its programme week, never a weekday. Catalog ordinals use the full authored required sequence; generated ordinals are retained before past dates are filtered from the generated window.
- Optional `performedWorkoutReference.displayContext` retains the workout title, plan-title localization key and numbered day/week in the immutable issuance snapshot. Existing intent/recovery serialization, local activity persistence and private `clientData` preserve it after active-plan replacement. Explicit activity-title edits also update the cosmetic private display title; receipt identity, issued recipe and completion/progression authority stay unchanged.
- Event and followed-route names retain precedence. Ordinary sessions and optional/support/filler rows without a canonical numbered identity retain their existing heading. Old receipts and existing generated rows without a retained ordinal are not backfilled or guessed; new generated windows acquire it on normal generation. Existing catalog rows can resolve their authored identity at issuance. Deploy the backend before expecting new context in either client; no schema migration, reset or forced plan rebuild is required.
- Plan names and the compact day/week format render in English, Spanish and Simplified Chinese. Unknown localization keys use the localized generic plan name. This is private presentation metadata; top-level activity titles, Health exports, Social/share titles and receipt authorization are unchanged. It introduces no analytics event/property; existing finish/save events remain unchanged and never include headings or day/week values.

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
- Actual `RecordingViewModel.saveFinished` stores receipt and categorical suitability alongside optional numeric effort before returning success. Room v9 stores a private receipt JSON column plus suitability; the existing activity outbox encodes private `clientData` and the backend reconciles completion atomically. The former finish-review best-effort completion callback is removed. Normal manual completion APIs remain available.
- Current schema is `plainstride-v9.db`; only export9 is tracked. This unreleased app opens clean local activity/cache/journal/outbox data on upgrade, without copying older unsynced rows. Build/reset commands are in `android-build.md`.
- Headless `/tmp/ReceiptTransportDemo.java` executes compiled production serializers and both launch converters against the real synthetic response, then actual entity/domain mapping and private upload serialization/reload. `/tmp/plainstride-durable-android-jvm-output.txt` reports fourteen phases totaling1500seconds, exact receipt preservation, true/false performed declaration and retained optional effort/suitability. This verifies conversion/serialization; it does not execute Room transactions, recorder lifecycle, UI/relaunch or authenticated synchronization.
- Existing isolated `DebugSessionEffortHarness` additionally exercises actual `RecordingViewModel.saveFinished` with first local failure/retry and receipt reload/outbox checks, using a synthetic account, no token, no sync and no real recorder commands. Native execution remains pending while the Mac is locked. Build log: `/tmp/plainstride-durable-android-build.log`.

## Companion issuance concurrency verification

`/tmp/plainstride-companion-lock-demo.mjs` replays the real assembly/companion interleaving using a disposable localhost55472 PostgreSQL database. It observes the companion waiting on the advisory lock while assembly is paused, commits the response/receipt, then awaits the mutation. Output `/tmp/plainstride-companion-lock-output.jsonl` records matching1800-second outgoing phases/receipt, next1200-second shortened phases/receipt and an immutable original receipt. The calorie variant checks post-wait estimate inputs and retained400cal receipt; injected database failures restore the original row/blocks/steps and leave the action proposed without accepted outcome/evidence. Build log: `/tmp/plainstride-companion-issuance-lock-build.log`. No production configuration, provider, GUI or existing test suite is used.

## Repository acceptance checkpoint

- iOS and Android activity ownership, mutation generations, terminal receipt conflicts, exact pending/confirmed slot overlays and app-lifetime retry now follow `activity-repository.md`. Receipt/privacy and server progression semantics above are preserved.
- Activity upload acknowledgements capture canonical completion disposition and planning/statistics watermarks in the accepted transaction. Planning snapshot revisions order serialized observations independently of plan versions.

## Explicit completion and correction

- `POST /planning/workouts/:id/complete` accepts optional `manualAction=link|complete|undo`. Existing receipt upload behavior is unchanged. Link requires an owned, undeleted same-sport recording from the last 30 days with no issued receipt or other workout association. Future slots cannot be completed.
- Explicit operations run under the planning-user lock. Manual entries retain `performedAsIssued=false`, no receipt/edit linkage, and no fabricated actual metrics. A linked entry uses only canonical activity measurements. They never earn exact-prescription dose credit. Undo/correction cannot alter receipt-linked history.
- Completion also retires planned replacements in the same plan/date/required-or-optional scope, matching receipt completion. An inactive plan cannot retire another plan's workouts. Undo restores only the explicitly selected manual row and never resurrects superseded replacements.
- Corrections replace only the selected slot's manual associations. Both previously and newly linked activities receive a fresh `updatedAt`, so cached activity metadata refreshes observe unlink/link. Activity list and cached-change reads return a private canonical `completion` summary independently of optional issued metadata. This also restores associations created without a receipt.
- This change requires backend deployment before native explicit-completion controls work. No schema change, migration, reset, or historical backfill is needed. Backend compile verification: `npm run build`; no test suite or production data writes are required.

### Native explicit-completion controls

- Existing planned-workout details on both platforms offer **Link recorded activity** and **Mark completed without recording** for today/past planned or missed slots. An online picker pages owned activities through the last 30 days, filters linked/issued/different-sport rows, and shows the recorded date, distance and duration. Completion/correction requires a connection; there is no second outbox.
- Backend `completionMode` distinguishes `recorded`, `manual_recorded`, and `manual_unrecorded`. Manual completions show **Undo completion** and can replace their recording. Receipt-linked completions keep their immutable history. Unrecorded completion creates no synthetic activity or metrics. Normal planning reassessment still runs; exact issued-dose credit remains excluded.
- After saving an unreferenced Group recording, the existing saved-activity summary/celebration/stretch header can ask **Count this toward today's workout?** only for one same-day same-sport unfinished required workout with at least half its prescribed duration recorded. The recording remains independently saved. Tapping Count synchronizes the existing activity, waits for its canonical identity, then explicitly links it. A pending upload provides retry feedback; no receipt is invented and no link occurs without the tap.
- Activity reads advertise `completionPolicyVersion=manual-completion-v1`; an explicit null summary removes an old manual association. iOS atomically commits canonical association and activity baseline in its existing account-owned manifest. Android does the same in its existing Room transaction/completion table, exposing a presentation-only linked-workout ID. Old activity baselines are rejected by server update timestamp. No Android schema or local data reset is needed.
- Build-only/static verification is permitted; no automated suite or simulator/emulator runtime was requested for this change. UI behavior, large text, VoiceOver/TalkBack, offline retry and cross-device refresh still require native verification. Physical iOS installation remains a separate required checkpoint from a successful compile.

### Deployment and verification checkpoint (2026-11-22)

- Backend revision `outbound-api-manual-completion-4defa4ac` received 100% traffic after a successful compile/deploy, including replacement-slot retirement. `/health` was healthy and an unauthenticated explicit-completion request returned 401. Existing service environment configuration remained unchanged. No schema sync, reset or production data mutation was part of deployment verification.
- iOS final frozen source compiled successfully with the build-only helper. A signed compile also succeeded; installation on Bruce main failed with CoreDevice 4016 because requested device-service/connectivity/power states were not assertable. Phone installation/launch and interactive native behavior remain outstanding.
- Android's optional Group question uses localized prescribed duration to identify the unique same-day workout; detail screens retain the existing authored workout-title localization. The saved celebration scrolls so its question, Share and Done remain reachable; runtime large-text/theme evidence is still pending.
- Backend compilation, the final signed iOS build, Android `:app:assembleDebug`, the design-system checker and diff checks passed. Independent Sol/Medium source review resolved its findings; its final status remains **Incomplete** because native interaction, visual/accessibility evidence and phone installation are outstanding. No test suite or simulator/emulator runtime checks ran.
