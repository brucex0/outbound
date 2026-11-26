# iOS route suggestion cache

Open when changing private generated-route reuse, storage, or planner request ownership. Provider/generation behavior remains in `route-planning.md`.

## Reuse contract

- Keep at most 30 individual successful generated routes per authenticated account, expiring seven days after generation. Empty responses and provider failures do not replace good entries. Community lookup results are not persisted here.
- Automatic GPS, address, and map confirmations can reuse routes whose **actual first point, snapped start, and closing point** are all within 50 meters of the new start. Proximity to the previous requested point alone never qualifies a route.
- Activity, climbing preference, and explicit required-place coordinate must match. Required places are never approximated. Canonical route distance must satisfy the new target's ±10% interval; deviation is recomputed for that target.
- Preserve canonical geometry, distance, elevation, source, and attribution. Never add straight connectors or alter a workout target. Existing route details show the routed start offset.
- A matching fresh cache result is displayed immediately, then saved/community lookup participates in the same comparison. Automatic generation fills fewer than three diverse choices; a full reusable comparison avoids provider generation. **More routes** bypasses automatic provider reuse and makes a real provider attempt; valid matching cached routes remain available after failure, with a localized temporary fallback notice.

## Ownership and privacy

- `LoopPlanningCache` is the feature port; `DiskLoopPlanningCache` is its actor-based disk adapter. `LoopPlanningSession` owns input revision, cancellation, and published results. Late lookups and writes cannot mark newer inputs current or revive a dismissed presentation.
- Files live under Application Support `LoopSuggestions-v1`, use a SHA-256 account filename and account owner envelope, are excluded from backup, and use atomic protected writes. Disk IO runs on the adapter actor. Only schema 1 is read; corrupt, mismatched, expired, or invalid entries are discarded. No migration or server publication occurs.
- Account-context epochs reject late reads/writes after logout or switching accounts. Logout/account deletion schedules removal of the departing account's file. A delayed purge does not erase the same account's newly signed-in copy. Other accounts' files are isolated.
- Cache diagnostics include only operation and bounded category. Existing `feature_exposed` analytics uses `feature=loop_planner_cache` and `result=hit|miss|expired|bypass|error`; never coordinates, queries, filenames, account/route IDs, provider payloads, or exact targets.

## Focused verification

- `OutboundTests/LoopPlanningCacheTests`: actual-start boundary/barrier, activity/target/via/preferences, TTL, 30-route bound, empty-write retention, disk reopen, logout, and stale-account isolation.
- `OutboundTests/LoopPlanningSessionTests`: reuse without API calls, adjusted target deviation, explicit refresh and failed-refresh retention, late cache/input/cancel ownership, and existing planner input contracts.
- Run only these targeted checks when authorized; a compile does not establish runtime or map rendering. Runtime UI evidence and phone installation are reported separately.
