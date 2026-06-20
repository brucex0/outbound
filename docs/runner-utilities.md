# Runner Utilities And Gear

Open this when adding practical runner features such as shoes, PR history, race predictions, activity editing, source attribution, treadmill mode, or richer activity analytics.

## Product Gap

Runkeeper, MapMyRun, Strava, Garmin, and similar apps all carry small practical utilities that make a runner trust the product as a real logbook. Outbound already has recording, progress, best efforts, route export, and some HealthKit scaffolding, but it is missing several table-stakes runner tools:

- shoe tracking
- PR history
- race predictions
- heart-rate zone summaries
- cadence
- treadmill mode
- manual activity editing
- broader import/export
- device/source attribution polish

These should support the coaching/motivation thesis, not turn Outbound into a spreadsheet.

## Product Principles

- Start local-first where possible; sync later.
- Treat gear and stats as trust infrastructure.
- Keep the Me surface calm; put detail in Progress and Activity Detail.
- Make every metric explainable, especially race predictions and heart-rate zones.
- Preserve source attribution so imported, manually edited, and Outbound-recorded activities are distinguishable.

## Feature Sequencing

### Phase 1: Logbook Credibility

Ship first:

- shoe inventory with mileage totals
- assign a shoe to a saved run
- PR history for common distances
- manual title, distance, duration, date, sport, and shoe edits
- activity source badge: Outbound, Apple Health, Garmin via Health, manual, imported file

Why:

- gives runners confidence that Outbound is their real training log
- unlocks sticky reminders without needing device integrations first
- builds on existing local saved activities and progress calculations

### Phase 2: Serious Summary Metrics

Ship next:

- heart-rate zone summary from saved or imported HR samples
- cadence display when HealthKit or device imports provide it
- treadmill/manual indoor run mode with no GPS route requirement
- richer PR views: all-time, this year, rolling 90 days

Why:

- fills category expectations for runners who inspect workouts
- makes imported HealthKit/watch data visibly useful

### Phase 3: Planning And Prediction

Ship after enough clean history exists:

- race predictions for 5K, 10K, half, and marathon
- prediction confidence based on recent activity depth
- shoe retirement reminders
- source-aware training load and consistency summaries

Why:

- predictions are only useful when based on credible, recent data
- coach copy can explain the "why" without overpromising precision

### Phase 4: Import/Export Breadth

Add when sync foundations are stable:

- FIT/TCX import
- FIT/TCX export if needed by target users
- Strava import/export
- duplicate detection across HealthKit, Strava, and local recordings

## Data Model Direction

### Local Activity Additions

Extend saved activities over time with:

- `source`: kind, display name, external ID, device name, import date
- `gear`: shoe ID, optional bike ID later
- `manualEdits`: edited fields, edited at, original values where needed
- `indoor`: true for treadmill/indoor sessions
- `cadence`: average and max steps per minute or revolutions per minute
- `heartRateZones`: zone boundaries and seconds per zone

Keep older manifests loadable with defaults.

### Gear

Local-first model:

- `GearItem`
  - `id`
  - `kind`: shoes first, bike later
  - `name`
  - `brand`
  - `model`
  - `startedAt`
  - `retiredAt`
  - `distanceLimitM`
  - `notes`

Computed fields:

- total distance
- last used date
- remaining distance before suggested retirement

### Backend

Add server models after activity sync and authenticated identity are stable:

- `GearItem`
- `ActivityGear`
- optional `ActivityEdit` audit records

For activity source attribution, expand `Activity.syncSource` into a structured source payload or add fields:

- `sourceKind`
- `sourceName`
- `sourceDevice`
- `externalSourceId`
- `importedAt`
- `isManual`

## UX Surfaces

### Settings

- Gear list
- Add shoe
- Retire shoe
- default shoe for runs

### Activity Save/Edit

- shoe picker on Save Activity
- edit activity sheet from Activity Detail
- manual indoor/treadmill entry

### Activity Detail

- source badge near route controls
- shoe row for runs
- PR badges when applicable
- HR zone summary when data exists
- cadence metric when data exists
- edited/manual badge when applicable

### Progress

- tabs for Now, Trends, Records, and Gear to keep the stats surface discoverable
- PR history
- shoe mileage
- race prediction card with confidence
- source filters later if imports create duplicates or confusing totals

## Metric Rules

### PR History

Use route-window best efforts where GPS route exists. For treadmill/manual sessions, count only explicit race/result entries or full-activity distances to avoid inventing segment PRs from edited totals.

Recommended distances:

- 400m
- 1 km
- 1 mile
- 5K
- 10K
- 10 mile
- half marathon
- marathon

### Race Predictions

Do not present predictions until there is enough recent data.

Minimum viable rule:

- use recent best effort or race result
- apply a conservative Riegel-style exponent
- lower confidence when data is old, manually entered, or sparse
- show ranges rather than false-precision single times

### Heart-Rate Zones

V1 zones:

- let the user set max HR manually or estimate it as a fallback
- store zone boundaries with the summary so past activities remain interpretable if settings change
- clearly label estimated zones

### Cadence

Cadence is source-dependent.

- live cadence requires watch/sensor support and should wait
- imported cadence can appear on activity detail when HealthKit or file imports provide it
- never fake cadence from GPS speed

## Rollout Recommendation

The first high-value slice is:

1. local shoe model and Settings UI
2. shoe picker on Save Activity
3. shoe mileage in Progress
4. activity source badge model
5. edit title/distance/duration/date for manual corrections

This gives Outbound practical logbook credibility without blocking on HealthKit entitlements, Strava OAuth, or watch work.

## Current Local Slice

Implemented locally:

- `Gear/GearStore.swift` stores shoes in `UserDefaults`, supports default shoes and retirement, and computes mileage from saved activities.
- `SavedActivity` now carries source, gear, manual-edit, indoor, cadence, and heart-rate-zone metadata with decoding defaults for older manifests.
- `RecordView` can mark treadmill/indoor sessions and attaches the default shoe on save.
- `ActivityDetailView` shows source, shoe, indoor, cadence, and HR-zone metadata and has a focused edit sheet for title, date, distance, duration, and shoe.
- `ProgressStatsEngine` computes PR history and race predictions; `ProgressView` renders PRs, predictions, and shoe mileage.

Still future work:

- real backend/import source sync for Strava, FIT, TCX, Garmin, and Apple Health writes
- true HR-zone distributions from samples rather than saved summaries/estimates
- imported cadence ingestion and live cadence sensor support
- fuller manual activity creation outside of post-save editing
