# Account Statistics

Open this when changing account totals, Progress, statistics caches, history synchronization, or import reconciliation.

## Ownership

- The backend owns complete account statistics. Neither complete activities nor complete activity summaries need to exist on a client.
- `GET /v1/statistics?timeZone=America%2FLos_Angeles&firstWeekday=1` returns an authenticated, account-scoped snapshot. Weekday numbering matches Foundation: Sunday = 1, Monday = 2.
- `algorithmVersion`, `revision`, `computedAt`, timezone, week start, and `status = complete` describe its coverage. A failed calculation returns an error rather than partial totals.
- `all` contains Progress comparisons, trend buckets, HR load, semantic insights, running best efforts, PRs, predictions, and momentum. `sports` contains the same contract per sport.
- `lifetime` and `currentWeek` count all saved, undeleted activities for account/Me totals and weekly focus. Progress retains its separate greater-than-60-second eligibility rule.
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

- iOS and Android cache complete snapshots by account, algorithm version, timezone, and first weekday. Sign-out/account switches do not reuse another account's snapshot.
- Progress, sport selectors, Me totals, weekly-focus progress, and gear mileage consume that snapshot independently of history cache size.
- With no snapshot, show loading/unavailable with retry. A failed refresh retains the last complete snapshot and identifies it as cached.
- Pending local changes remain visible in activity history, with statistics explicitly pending until the server acknowledges and a complete snapshot refreshes. They are not added blindly to cached aggregates, so acknowledgement cannot double-count them.
- Existing local-only iOS mode remains explicitly based on local data; it is not the source for authenticated account totals.

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

No activity/database reset is required. Android reuses its current account-cache table, so its Room schema version does not change.

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
