# Account Statistics

Account weeks and timezone initialization follow `account-calendar.md`: persisted account IANA zone, Monday first weekday, exclusive end boundary, and stable periods while travelling.

Open this when changing account totals, Progress, statistics caches, history synchronization, or import reconciliation.

## Ownership

- The backend owns complete account statistics. Neither complete activities nor complete activity summaries need to exist on a client.
- `GET /v1/statistics?timeZone=America%2FLos_Angeles&firstWeekday=1` returns an authenticated, account-scoped snapshot. Weekday numbering matches Foundation: Sunday = 1, Monday = 2.
- `algorithmVersion`, `revision`, `computedAt`, timezone, week start, and `status = complete` describe its coverage. A failed calculation returns an error rather than partial totals.
- `all` contains Progress comparisons, trend buckets, HR load, semantic insights, running best efforts, PRs, predictions, and momentum. `sports` contains the same contract per sport.
- `lifetime` and `currentWeek` count all saved, undeleted activities for account/Me totals and weekly focus. Progress retains its separate greater-than-60-second eligibility rule.
- `weeklyRunGoal` separates Me’s personal running frequency from prescribed-workout completion. `completedRuns` counts each saved, undeleted `running` activity that reaches at least 300 seconds **or** 500 meters once in the caller’s local calendar week through now. Free, regular, imported, and Group runs count with the same inclusive eligibility rule; runs below both thresholds and other sports do not. Distance and time retain all-activity totals. Plan remains the home for prescribed-workout completion.
- `weeklyRunGoal.targetRuns` is the active run-only goal’s chosen `daysPerWeekTarget`; it is `null` without that choice (including mixed-sport session targets); Me still shows the eligible saved run count. Never default to three runs or a plan-week prescription count. `scheduledRunsByToday` is present only when all chosen usual weekdays are known; it counts weekdays from the same local week start through today. Me compares the eligible logged count with the chosen weekdays through today, explicitly labeled as the usual schedule; it does not claim an adaptive workout was missed. Reaching/exceeding the weekly goal takes priority.
- Goal identity/update time participates in server-cache validation, so changing/ending a goal invalidates cached frequency without requiring an activity change. This is an additive statistics response; deploy the backend before releasing clients. No schema change, backfill, or data reset is required for this field.
- Me distinguishes a true zero from an unavailable `weeklyRunGoal` field. It keeps complete cached counts within the current week with the existing cached/pending notice, suppresses live schedule comparisons for stale/pending data, and observes the app-lifetime repository coordinator’s refreshes. A snapshot from a previous week cannot supply this week’s summary. It never falls back to the history page or adds pending local runs to server counts.
- Android Me reads active-plan status from the same account-scoped cached planning state as Today. A known snapshot with no plan means no active plan; a missing or invalid snapshot is shown as unavailable. Creating or refreshing a plan updates Me through the shared state instead of a separate sign-in-only request.
- If a current statistics snapshot omits `weeklyRunGoal` but the shared planning snapshot has an explicit run-only `daysPerWeekTarget`, Android may show that chosen target while keeping the weekly run count unavailable. It does not combine the target with local activity history or invent a completed-run count.
- Android retains real planning consistency when available, but does not manufacture a percentage from activity count. iOS local-only mode counts local running activities through the shared `ActivitySaveEligibility` rule and uses an explicitly selected run plan’s frequency.
- `gear` contains lifetime distances and last use by shoe ID. `coachingReferencePace` uses the existing recent-running median rule; clients do not derive it from their cached history.
- The assistant resolves account totals from the server. If unavailable, its numeric context is explicitly unavailable, never an invented zero or partial client total.

## Calculation And Consistency

- Versioned `Activity.statisticsFacts` stores compact per-activity inputs and route-derived best durations. Routes are examined on ingest/edit or backfill, not downloaded by clients to calculate account records.
- Activity creation, updates, facts, and `User.statisticsRevision` increments share a database transaction. Deletion increments the revision in its transaction.
- Snapshot reads use repeatable-read isolation. Each instance keeps at most 256 cached snapshots; every request checks the database revision. Cache lifetime is at most 60 seconds and ends at local midnight, including week/month boundaries.
- Preserve the existing iOS algorithms: moving time, sport-separated pace, matched elapsed periods, optional HR eligibility, goal tolerance, route-window preference, whole-activity fallback tolerances, confidence, and insight ordering.
- Foundation's existing inclusive `DateInterval.contains` endpoints and calendar-day DST arithmetic are retained for Progress. A separate change is required to revise those metric definitions.
- Standard record/prediction labels and semantic insight/momentum cases are localized by clients. Activity titles remain user-authored text.
- Analytics contains only feature/source/result enums and coarse counts. Never send snapshot values, evidence, dates, identities, or raw errors to analytics.

## Client Cache And Offline Behavior

- iOS durably stores complete snapshots in the account-scoped activity manifest under the canonical `monday-v1` policy, independent of the travelling device timezone. The app coordinator owns refresh/invalidation. Android durably stores complete snapshots and revision/invalidation cursors in its account-scoped Room projection. Sign-out/account switches do not reuse another account's snapshot.
- Progress, sport selectors, Me totals, weekly-focus progress, and gear mileage consume that snapshot independently of history cache size.
- With no snapshot, show loading/unavailable with retry. A failed refresh retains the last complete snapshot and identifies it as cached.
- Android Me refreshes the shared Today planning snapshot on entry and its refresh action. Its current-focus card distinguishes an active plan from a confirmed no-plan state; when there is no active plan, it may show a non-stale same-day Today recommendation with explicit wording. The bounded `feature_exposed` event uses `feature=me_daily_recommendation_focus` and includes no recommendation content. Weekly run targets remain unset unless the saved run-only goal supplies a target.
- Pending local changes remain visible in activity history, with statistics explicitly pending until the server acknowledges and a complete snapshot refreshes. They are not added blindly to cached aggregates, so acknowledgement cannot double-count them.
- Existing local-only iOS mode remains explicitly based on local data; it is not the source for authenticated account totals.

## Recording Save Identity

- Plainstride recording uploads with different client activity IDs are reconciled by exact recording session UUID, scoped to the authenticated account. A transaction lock serializes concurrent saves; the response returns the canonical client ID so installed iOS clients adopt it and retain photos.
- A shorter/stale copy cannot overwrite the fuller saved recording. A newer copy can extend the canonical record when both duration and distance are at least as complete, without replacing manual edits or changing its client ID. Same-client-ID edits retain their existing behavior. No time-overlap or Group-event-ID guessing is used.
- `activity_recording_identity` logs only `reused`/`extended` results; recording IDs, user data, and metrics are excluded.

## History And Media

- Background synchronization uploads pending writes, checks changes/tombstones for already-cached IDs in batches of at most 200, and fetches one recent history page.
- Cached-change requests contain each known server ID and server update timestamp. Responses omit route geometry. They do not enumerate the account's complete history.
- History pages use the server cursor and request `includeRoute=false`. More pages are fetched on demand. Owning detail views fetch the current record and route by ID; iOS route-card previews can also request geometry for visible cards.
- Existing local recordings, pending data, original route sidecars, and photos are retained. This change does not destructively evict local originals or replace the iOS manifest store.
- Photo metadata is restored without downloading JPEGs. The existing authenticated photo cache loads bytes when rendered and preserves cached files, image orientation, mirroring, and original bytes. Canonical import adoption copies retained photo bytes without re-encoding.
- The iOS manifest's storage/write cost can still grow with retained local records; moving that persistence layer to an index is independent of statistics correctness and is not required to calculate account totals.

## Import Identity

- Source/external IDs, Health workout references, and Plainstride recording-session IDs have server lookup indexes.
- `POST /v1/statistics/import-identities` checks at most 200 exact candidates per request. Health-owned sessions can restore only their matching activity metadata for reconciliation.
- Imported source identities are serialized in the ingest transaction. Reimporting from another/offline device returns the existing canonical activity without overwriting its edits or creating another activity/post.
- Clients adopt the canonical client ID after upload acknowledgement, retaining pending photos. Outbox acknowledgement follows durable local reconciliation.
- Normal external/Strava imports can remain pending offline. An owned Health workout with an uncached Plainstride session is deferred until its exact session identity can be reconciled.

## Schema And Rollout

No backend/iOS activity reset is required. Android repository reconciliation uses the current Room v9 account projection tables and opens clean local data under the unreleased-client policy; see `activity-repository.md`.

1. Build backend and apply the additive Prisma schema through the guarded deployment helper before releasing either client.
2. Backfill historical facts/indexed import identities, preferably before client rollout:

   ```sh
   cd backend
   npm run db:generate
   npm run build
   npm run statistics:backfill
   ```

   Run with the intended database environment. Production uses a dedicated `outbound-statistics-backfill` Cloud Run Job, the deployed immutable image, the runtime service account/VPC, and a Secret Manager reference. Never reuse the read-only diagnostic job for this migration.
3. The backfill processes 100 rows at a time, checks source update timestamps before writing derived fields, and preserves canonical timestamps. It is restartable. Snapshot construction can also derive missing facts on demand; errors retain the client's prior complete snapshot.
4. Release clients using the same current statistics contract; no historical Android payload readers or data migrations are added.

## Verification

- Build backend, iOS, and Android without running the test suite unless requested.
- Compare the server calculation with the retained Swift reference across empty, short, mixed-sport, HR/goal, timezone/DST, calendar boundary, and 10,000-activity inputs.
- Verify account results are identical with zero, one page, and complete local history available; statistics requests must contain no client activity dataset.
- Verify revisions after save/edit/delete, cached reads, unavailable/offline behavior, account switches, exact import reconciliation, and media preservation. Report any device scenarios not exercised.

## Activity-driven reconciliation

- iOS observes the account-scoped activity repository and resumes outstanding planning/statistics reads from its durable acceptance cursor. It retains complete backend totals while offline; it never adds client aggregate deltas.
- Planning commands also invalidate the statistics read model. Persisted invalidation/read tickets prevent a pre-command response with an unchanged activity revision from clearing a newer invalidation. See `activity-repository.md`.
