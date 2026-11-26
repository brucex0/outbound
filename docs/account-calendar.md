# Account Calendar

Open when changing plan-week boundaries, account weekly statistics, timezone initialization, or cached calendar projections.

## Policy and ownership

- Plan and account-statistics weeks are Monday through Sunday in the account's persisted IANA timezone (`monday-v1`, Foundation `firstWeekday=2`). Locale and travel do not change the account's week.
- `User.calendarTimeZone` is initialized atomically from the first valid `X-Plainstride-Time-Zone` device header; statistics can also use an explicitly supplied `timeZone` query hint. Later hints never overwrite it. A missing hint permits a provisional UTC read but does not persist UTC. Background missed-workout maintenance waits for initialization.
- `PlanningState.calendar` includes `policyVersion`, `timeZone`, `firstWeekday`, inclusive `weekStart` and exclusive `weekEnd` ISO instants, actual `planStartDate` (`TrainingPlan.startedAt` in the account zone), Monday-bucket `planWeekIndex`, and `isPartialWeek`. Without a plan, the period still exists and the plan fields are null.
- Scheduled workout timestamps remain UTC-midnight encodings of logical date labels. Do not timezone-convert them as instants. iOS retains `scheduledDateKey` through cache serialization; its `logicalScheduledDate` supplies a presentation carrier without shifting the saved date during travel. Notifications keep their existing local scheduling behavior.
- iOS Plan Details shows only current/upcoming roadmap phases because the rolling schedule may not retain historical sessions. Displayed phase ranges use the roadmap's ISO start/end labels as logical dates in the account calendar, formatted with the active locale. They show broad phase boundaries independently of the issued workout window; they do not claim scheduled workout coverage.
- Planning-state `today` selection compares schedule labels with `accountDateLabel(now, accountTimeZone)`. Future rows remain in `upcoming`; they are not substituted into the current day's slot.
- A Wednesday November 11 start has partial Week 1, November 9–15; Week 2 starts November 16. New generation allocates a full Monday-week rhythm first and omits pre-start dates, without concentrating the full weekly dose into the remaining days. Existing schedules, completed workout identities, issuance receipts and source progress are retained; metadata alignment does not force a rebuild.
- Refill preserves the current calendar week’s target: prior-version historical planned/missed slots and any current-week skipped slot remain visible unless a newer/current or completed slot already represents the same logical date and required/optional role. Prior future planned rows are not imported; completed identities and receipt links keep their existing preservation behavior.
- Android active Plan Details groups the complete issued `PlanningState.workouts` window by logical-date Monday, numbering from `calendar.planStartDate` (or account-zone plan creation date). It does not reuse the current-week-only progress snapshot as the schedule. Compact phase date ranges use only issued non-optional rows within each broad phase.
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

## Issued past weeks

- Planning state includes retained past rows from every version of the active plan, including original blocks, date labels and statuses. Completed identities survive; uncompleted duplicate date/required-or-optional slots use the latest retained prescription. Superseded future prescriptions are excluded. History is never regenerated from current templates, and rows that were never retained cannot be recovered by the clients.
- iOS and Android Plan Details place prior Monday weeks under a compact **Past weeks** disclosure above the current week. The current week starts expanded; past weeks and their individual rows remain observational, with no Start or catch-up action. Expanding history leaves current-week progress calculations unchanged.
- Historical planned rows do not issue new launch receipts or schedule notifications. Completed details open the exact locally available activity via private completion/issuance association. If that activity has not synced to the device, the UI says it is unavailable rather than guessing from the date.
- Today and Plan Details prioritize **Planned workout complete** after today's required slot completes, without an extra generic recovery walk. An unfinished required slot still takes precedence; explicitly scheduled optional mobility remains in its plan details. Completion from an older version of the same active plan is recognized. No schema migration or data reset is required; deploy the backend before expecting the expanded history response.

- A completed Today workout keeps the existing planned-workout card, original title, prescribed duration/phases and Plan navigation. Completion replaces the Change action with the linked activity action; it does not replace the card with a toast. Selecting Planned remains available after completion, while the recording launch guard prevents restarting that completed slot. The embedded iOS setup retains Planned after saving a planned workout and when its completed prescription no longer has a launchable intent.

- Week headings use primary text and readable semantic type on both clients; actual completion totals use regular readable body/subheadline type. Only the current account-calendar week carries the localized “This week” label and a small theme accent marker. Past/future week headings remain neutral, with the outer Past weeks disclosure identifying history. Opening a past week still requires its existing week-header disclosure; workout rows then open their preserved prescription details.
