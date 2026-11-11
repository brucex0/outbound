# Direct workout edits

Open when changing iOS Today editing, edit persistence, or recording attribution. Manual edits are separate from readiness and adaptive proposals. Existing Android personalization endpoints remain supported.

## Contract

- `GET /v1/planning/activity-suggestion` returns `editContext`; planning state also exposes that context. The server supplies an opaque revision, operation capabilities/ranges, and reviewed effort presets.
- `POST /v1/planning/workout-edits/apply` authenticates the owner and accepts the original suggestion/planned-slot identity, logical date, base revision, UUID idempotency key, nullable optional reason, and one `change.operation=edit|replace|skip`.
- `edit` contains only changed target (`time` seconds or `distance` meters) and/or effort preset. `replace` resolves a catalog ID/version authoritatively. `skip` is explicitly confirmed in iOS. Reason is private audit context and never readiness evidence.
- Apply serializes on the planning-user lock, refreshes/rechecks the exact active slot, day, safety and normalized revision, and writes the same planned row plus a durable `WorkoutEdit` atomically. It never completes a workout or starts recording.
- The response contains a receipt and canonical planning state/suggestion assembled inside the transaction. Same-key/same-payload retries return the original receipt plus current canonical state; key reuse for another payload is rejected. iOS retains the request key after an ambiguous failure and does not queue offline edits.
- Continuous time edits preserve warmup/cooldown and change the single main phase. Goal conversion is independently restricted to a single continuous phase. Repeats, run/walk, unsupported step targets and intervals keep their original structure and explicitly disable unsupported edits; catalog replacement is available. No target or phase is silently discarded.
- Adaptive recovery and observed-baseline easy recommendations use their displayed effective phases for edit capabilities and Apply; the original planned slot remains the ownership/revision/audit identity. Apply persists the adapted stimulus, targets and phase tree into that same row, including effort-only edits. An unchanged canonical tempo/interval/pace/HR prescription retains its restrictions. Enriched editable suggestions expose exact phase durations to clients; three-phase workouts still cannot convert time to distance.
- A daily override uses the newest explicit command. Readiness, safety, activity/plan changes, completion and day rollover invalidate its fingerprint. Later legacy Android Apply commands take precedence. Invalidated newer commands cannot resurrect an older direct edit.

- Launchable planned/effective responses additionally carry a private immutable performed-workout reference. It preserves actual issued recipes across refills/edits and reconciles canonical activity completion through the existing upload outbox; see `docs/performed-workout-sync.md`. It does not change Apply confirmation/capability rules.

## UI and execution

- The sheet freezes the displayed workout and server identity/revision at opening; background refreshes never retarget an unsaved draft. A stale save is rejected with its draft/key retained.
- Missing capabilities do not block local goal, target, effort, reason or cached catalog drafting. Basic local bounds only validate input; known server restrictions remain in force. Apply/Use alone refresh a missing or expired baseline, and accept it only when the full frozen primary payload, day, plan context/version, activity watermark and decision still match. A mismatch updates canonical state for the next opening, keeps the current draft/selection, and requests retry or reopening; no revision is invented and no upload is queued.
- Goal type is static text when phase preservation prevents conversion; the numeric time/distance field and effort retain their independent edit capabilities. Available selector chevrons follow their values. This uses the existing workout-edit analytics flow and `edit` operation; no event or private reason handling changes.
- The sheet opens on the current filled goal and effort, with an always-visible optional reason. Reason selection changes no other fields. Canceling the catalog retains the unsaved fields. Catalog details ends with `Use workout`; successful Apply closes the entire flow to Today.
- A local custom/calibration session without a matching canonical edit baseline shows its actual filled values and a replacement-only explanation; direct Apply and Skip are disabled. Choosing a catalog replacement saves the server-owned replacement and clears the local override. Accessibility text sizes use a scrollable reason selection list so all choices remain reachable.
- The active save remains visible with loading, blocks duplicate actions/dismissal, and reports failures as temporary feedback. The caller consumes canonical state before closing.
- `SessionWorkoutReference` carries the original planned slot, retained issuance and edit ID/revision through intent copies and the recovery journal. The local saved activity retains that private receipt before Save succeeds; the existing activity upload outbox retries it and atomically reconciles completion with the canonical activity. Ownership/issued revision stays valid even after a newer same-day edit, without a separate best-effort completion pipeline.
- The recovery journal stores an immutable workout snapshot including the original edit/revision, goal, phase steps and cues; route geometry and group attribution remain in their existing separate journals. Recovery restores this snapshot before any current-Today fallback. Reminder launches refetch and require the same original slot/current day before presenting a canonical intent; unavailable reminders return to Today with temporary feedback.
- Edited sessions reject local setup goal changes with a localized Change workout instruction, so the immutable companion snapshot cannot disagree with a locally changed goal. Identical goals and ordinary unedited/manual sessions preserve their existing behavior.
- Effective execution content is separate from stock catalog provenance. Enriching an unedited planned run does not override calibration priority or remove ordinary easy/recovery calorie eligibility.
- Live-coach compilation resolves the immutable edit snapshot before catalog provenance/current planned content. Stock catalog guides remain canonical for unedited catalog selections. Effective step/goal triggers survive fetch/cache/relaunch.

## Migration and verification

The schema is additive and recorded in `backend/prisma/migrations/20261110020000_workout_edits/migration.sql`. Production deployment uses the exact-image, non-destructive `outbound-db-push` job before traffic promotion, as described in [backend-deploy.md](backend-deploy.md); do not substitute an uncoordinated manual migration command. The 2026-11-10 rollout record there captures schema execution and serving revision. Deploy the backend before distributing the matching iOS client.

Local compile preparation remains `cd backend && npm run db:generate && npm run build`.

An isolated disposable development database can instead use the documented `npm run db:rebuild`; it destroys only the explicitly configured database. Never point fixture commands at personal/production configuration.

Build verification uses `npm run build`, Prisma schema/migration validation, an iOS simulator build, and `python3 scripts/check-design-system.py --base <base>`. Runtime QA must exercise the real Today presentation and normal Apply network path, editing/reason independence, picker cancel/Use, failed save/retry/loading, skip confirmation, keyboard, narrow+largest type, translations/themes, refetch and completion/guide linkage. See `ux-qa.md`; compilation alone is insufficient. Do not run the full test suite.

## Isolated local QA

The explicit fixture runs the real planning routes against its own loopback PostgreSQL database and synthetic identities. It injects identity only in the fixture Hono instance; production startup never imports it. It never loads personal environment files. Ports 28479–28481 must be unused; a second instance must not run over an existing fixture.

```sh
cd backend
npm ci
npm run db:generate
npm run build
node scripts/fixtures/direct-workout-edits.mjs
# In another shell, while that fixture is running:
node scripts/fixtures/check-direct-workout-edits.mjs
# Run only the adaptive recovery/observed-baseline regressions when checks are authorized:
OUTBOUND_DIRECT_EDIT_CHECK=adaptive node scripts/fixtures/check-direct-workout-edits.mjs
```

Evidence and the disposable database live under `/tmp/plainstride-workout-edit-fixture` (override with `OUTBOUND_DIRECT_EDIT_OUTPUT` in both shells). Normal dependency installation runs the embedded PostgreSQL platform package's library-symlink setup; do not use another checkout's native binaries as a permanent workaround.

The iOS `DirectWorkoutEditUITests` cases are separately selected, targeted UI checks against `http://127.0.0.1:28481`. They cover the actual Today presentation and normal network DTOs, not a sheet-root harness. Run only the needed named case with `-only-testing:OutboundUITests/DirectWorkoutEditUITests/<case>` and `-collect-test-diagnostics never` on an isolated simulator, following `build-test-device.md`. Never run the broad suite implicitly. Fixture-only reset/fail/delay/response-loss controls affect synthetic accounts only. PNGs default to `/tmp/outbound-direct-edit-ui`; the `.xcresult` also retains attachments.

The recovery UI case uses the explicit `-OutboundWorkoutEditRecoveryUITest` flag together with seeded test data in a DEBUG simulator build. It backdates only that synthetic recorder's canonical start by six minutes; the real recording, journal, finish/save path and production save threshold remain active. It removes its reset flag on relaunch and verifies the saved completion references the revision performed before a newer edit. This branch is absent from Release and physical-device builds.

The focused reminder case injects a deliberately stale cached reminder only with `-OutboundWorkoutReminderUITest <planned-id>`, seeded data, and a DEBUG simulator build. It exercises the real MainTab resolver and records its canonical intent (slot, edit revision, goal and steps); a past-day reminder must return to Today. It does not claim operating-system notification delivery. Software-keyboard checks use only the selected simulator's keyboard setting; spoken VoiceOver and physical-device behavior remain separate checks.

Local-draft gating follow-up (2026-11-10): simulator/device builds, the design guardrail and the focused local-draft/picker-failure/ambiguous-retry/changed-baseline case passed. Bruce reported personally verifying the signed iPhone update and requested stopping further verification. The new Spanish retry message at narrow width plus largest accessibility text size was not visually verified; its focused automation was stopped at that direction. No full suite ran.

Release follow-up (2026-11-10): Bruce explicitly requested merge, production deployment and iPhone installation after the independent UX review reported `Incomplete`; that request is the documented waiver for missing runtime evidence. The narrow-layout and largest-text Spanish retry rendering, broader presentation/interactions, translations, themes, and supported accessibility settings remain unverified by this rollout. The backend was deployed as `outbound-api-00193-hwp`; candidate and production `/health` returned `ok`. A signed Debug iOS build from this revision was installed on Bruce main (`plainstride.outbound`) using UDID `00008150-000A1194026A401C`; the helper's configured CoreDevice ID was stale. The app was not launched. The full test suite was not run. The UX QA status remains `Incomplete` under the accepted waiver.
