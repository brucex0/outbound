# Account Calendar

Open when changing plan-week boundaries, account weekly statistics, timezone initialization, or cached calendar projections.

## Policy and ownership

- Plan and account-statistics weeks are Monday through Sunday in the account's persisted IANA timezone (`monday-v1`, Foundation `firstWeekday=2`). Locale and travel do not change the account's week.
- `User.calendarTimeZone` is initialized atomically from the first valid `X-Plainstride-Time-Zone` device header; statistics can also use an explicitly supplied `timeZone` query hint. Later hints never overwrite it. A missing hint permits a provisional UTC read but does not persist UTC. Background missed-workout maintenance waits for initialization.
- `PlanningState.calendar` includes `policyVersion`, `timeZone`, `firstWeekday`, inclusive `weekStart` and exclusive `weekEnd` ISO instants, actual `planStartDate` (`TrainingPlan.startedAt` in the account zone), Monday-bucket `planWeekIndex`, and `isPartialWeek`. Without a plan, the period still exists and the plan fields are null.
- Scheduled workout timestamps remain UTC-midnight encodings of logical date labels. Do not timezone-convert them as instants. iOS retains `scheduledDateKey` through cache serialization; its `logicalScheduledDate` supplies a presentation carrier without shifting the saved date during travel. Notifications keep their existing local scheduling behavior.
- Planning-state `today` selection compares schedule labels with `accountDateLabel(now, accountTimeZone)`. Future rows remain in `upcoming`; they are not substituted into the current day's slot.
- A Wednesday November 11 start has partial Week 1, November 9–15; Week 2 starts November 16. New generation allocates a full Monday-week rhythm first and omits pre-start dates, without concentrating the full weekly dose into the remaining days. Existing schedules, completed workout identities, issuance receipts and source progress are retained; metadata alignment does not force a rebuild.
- Refill preserves the current calendar week’s target: prior-version historical planned/missed slots and any current-week skipped slot remain visible unless a newer/current or completed slot already represents the same logical date and required/optional role. Prior future planned rows are not imported; completed identities and receipt links keep their existing preservation behavior.
- Calendar week numbers are distinct from earned programme/source-week progress. Existing completion, exposure, readiness and elapsed-time guards continue to control advancement. Calendar rollover alone cannot earn progression.
- Cached period/count projections belong to the shared activity/planning repository. Views present the period attached to their counts; they must not relabel old counts with a newly calculated week.

## Deployment

This is one additive nullable User column; no account reset or data backfill is required. Apply through the [guarded backend deployment workflow](backend-deploy.md) before distributing clients. The following commands are for a dedicated local development database only; they do not replace the production deployment guard:

```sh
cd backend
npm run db:generate
npx prisma db push --skip-generate
npm run build
```

Android keeps the `monday-v1` account policy in its current Room v9 shared projection. Calendar alignment itself needs no separate schema change; repository reconciliation opens clean v9 local data without migrating old caches. See `activity-repository.md`.

Operational initialization analytics contain only bounded policy/source values; no account IDs, dates, timezone values, activity metrics or user content.
