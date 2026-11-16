# Plan adjustments

Open when changing the iOS Adjust plan flow, temporary availability, pause/return, canonical preview receipts, or generator exclusions. Direct changes to today's workout remain in [workout-edits.md](workout-edits.md).

## Product contract

- iOS Plan Details → **Adjust** offers Move or swap workouts, Change available days, and Pause. A saved pause exposes Edit pause and Resume/cancel pause. More options is collapsed by default and contains Rebuild remaining plan and the existing event-goal editor.
- Plan Details groups the icon-free **Adjust**, **Change**, and **End** buttons as matching, content-sized native bordered peers with evenly distributed flexible gaps across the row, with a vertical fallback for narrow layouts or large text. Adjust edits the current plan; Change opens plan selection; End retains its destructive confirmation.
- Configuration is a draft. Back preserves it; Cancel does not change the plan. The server generates the before/after review, and only explicit Apply mutates the plan. Apply is online only, blocks duplicate submissions/dismissal while saving, and consumes canonical planning state before closing. Transient results use toasts.
- A move swaps all still-planned required/optional support rows on the two dates. The server limits moves to the issued horizon, preserves closed days, quality/long-work recovery spacing, event dates and the actual distance-specific taper boundary. It preserves recipes, row IDs, issued receipts and completion history. Vacated slots remain reserved across refills, including after completing/skipping the moved workout.
- Temporary availability uses an inclusive date range (at most 90 days) and selected weekdays (Sunday=1 … Saturday=7). No selected days means no planned workouts during that range. Generation retains the normal rhythm outside the range; inside it, affected prescriptions may use free selected days in the same account week. Overflow is omitted, never caught up in a later week. Recovery spacing, event/taper boundaries, required/optional distinctions and current-day boundaries remain binding.
- A pause starts on a chosen account-local date, today or future. Earlier dates keep their current schedule. The estimated return is a reference shown in Adjust plan; it sends no notification and never automatically resumes. The plan stays active and discoverable. Edit pause can change the future start or estimated return; an already-started pause retains its original start.
- Resume requires an explicit readiness self-check; that check is not a readiness report or medical clearance. The production planner uses current training/readiness, then the existing conservative break/readiness/pain adaptation policy. It does not mark a workout missed, clear illness/pain, prescribe a demo workout, or catch up skipped work. Cancelling a scheduled pause also previews the refreshed schedule.
- Rebuild refreshes the remaining supported window using the real planning engine. It cannot shift an event date or extend a rolling plan to an invented fixed finish date. The existing event editor remains the explicit path for changing race goals and preserves temporary availability/pause metadata.
- Edit/end temporary availability uses a new preview. Undo is available only on the same logical day while the full resulting plan/training revision is unchanged; it restores only future prescriptions and prior adjustment metadata. A completion, edit, replan, readiness/activity change or day rollover disables stale Undo. Completed/history rows and immutable issued recipes are never deleted.
- Optional reason is private command audit context only; it does not change the selected operation or readiness.

## Backend ownership and API

- `GET /v1/planning/plan-changes/context`: authenticated current plan ID, account date/timezone, future canonical rows, active availability and safe Undo command ID. iOS refuses a different plan ID from the one whose sheet opened.
- `POST /v1/planning/plan-changes/preview`: plan ID, UUID idempotency key, nullable reason, and one operation: `move`, `availability`, `pause`, `resume`, `rebuild`, or `undo`. Returns a durable preview ID, 15-minute expiry, canonical before/after rows and resulting availability.
- `POST /v1/planning/plan-changes/apply`: preview ID plus the original idempotency key. Under the shared user planning lock, checks active plan, version, logical date, full schedule/goal revision, latest readiness and activity watermark. It applies exactly the reviewed delta atomically and returns its receipt plus current canonical planning state and Today suggestion.
- Same-key/same-payload preview retries reuse their receipt; key reuse for another payload is rejected. Applied-key retries return the original receipt with current canonical state before expiry/staleness checks, even after a later plan replacement. iOS retains the preview/key after an ambiguous Apply failure and never queues offline changes.
- `PlanChangeCommand` stores private request hash, before/after snapshots, revisions, expiry and applied/undone timestamps. `TrainingGoal.constraints.planAvailability` stores the current pause/range/weekday selection; the goal and plan remain active. Reasons do not enter goal constraints or analytics.
- Engine-based previews run only transaction-local planner writes inside a SQL savepoint, capture coherent version/workout/block/step IDs, roll back those speculative writes, then save the immutable receipt. Apply materializes those exact IDs and recipes. Preview does not process outside-transaction events or issue workouts; speculative refresh analytics are suppressed.
- The shared persistence boundary enforces availability for generated, catalog and event replans. Generated/catalog refresh and event processing respect active pause; Today explicitly returns localized pause/unavailability advice. iOS also enforces saved availability with the account calendar after offline date rollover, so expired Today data cannot reactivate a calibration/planned launch. All dates are UTC-midnight containers of account-local calendar labels, never device/travel timezone dates.

## Deployment and verification

The additive schema is in `backend/prisma/migrations/20261116010000_plan_change_commands/migration.sql`. Deploy the backend schema and matching API before installing/distributing the iOS client. Use the exact-image non-destructive DB job and revision workflow in [backend-deploy.md](backend-deploy.md); no reset or destructive migration is required.

```sh
npm ci --prefix backend
npm run db:generate --prefix backend
npm run build --prefix backend
xcodebuild -quiet -jobs 2 -project ios/Outbound/Outbound.xcodeproj -scheme Outbound -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
python3 scripts/check-design-system.py --base 601e57b8d767e839c653a393dfe0b3b14fb20b53
```

Bruce explicitly waived UX verification for this change. No test suite, fixture, simulator/emulator UI check or independent UX review was run; source/build checks do not establish runtime or visual correctness. Physical-phone installation is a separate delivery step owned by the coordinator. Follow `docs/ux-qa.md` if runtime UX verification is later requested.
