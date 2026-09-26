# Strava Export Import

Open this when changing Strava history import, activity-file parsing, ZIP/gzip reading, or import deduplication.

## Product Contract

Plainstride does not connect to a Strava account and holds no Strava credentials.

1. The runner requests their own archive on `strava.com` (Settings → My Account → Download or Delete Your Account → Request Your Archive).
2. Strava emails a ZIP download link.
3. The runner downloads it on the iPhone and selects it in Plainstride from Settings → Integrations → Import activity history.
4. Plainstride reads the export and shows what it found.
5. The runner chooses which activities to import.
6. Selected activities are saved locally and synchronized like any other history, attributed to Strava.

Imported activities are never presented as just-recorded sessions, never posted to Social, and never counted as shared or live activity.

## Accepted Input

- Strava export `.zip`, including the unzipped export folder.
- Individual `.gpx`, `.tcx`, and `.gz` files.
- `activities.csv` anywhere in the selection supplies activity names, sports, dates, durations, and the file links.

Only activity payloads are read. Photos, clubs, followers, and social data in the export are skipped before they are loaded into memory.

## File Support

| Format | Support |
| --- | --- |
| `.gpx` | Route, timestamps, elevation, heart rate, distance computed from geometry when the file has none |
| `.tcx` | Sport, lap duration and distance, route, heart rate, cadence |
| `.fit` / `.fit.gz` | Not parsed. The workout still imports from the export summary without a route |
| `.zip` | Stored and deflated entries, no encryption, no ZIP64 |

Distance units are not recorded in `activities.csv`. The importer infers the unit by comparing summary distances against files it parsed successfully, and only applies the result when it is unambiguous. When the unit cannot be inferred, summary-only activities import without a distance rather than with a wrong one.

## Deduplication

- `source.externalID` holds `strava:<activity id>` for summary rows and `strava-file:<path>` for files without a row.
- Review excludes any activity whose identifier is already present locally.
- Re-importing the same export produces no duplicates.

## Implementation

- `Integrations/Import/StravaImportModels.swift`: candidate, skip, and review models plus the vendor sport vocabulary. Compiled into the `OutboundSessionAnalysis` package target so it stays testable without the app target.
- `Integrations/Import/ImportArchiveReader.swift`: dependency-free ZIP and gzip reader using `Compression` for raw DEFLATE. Bounded by a 128 MB entry cap and a 512 MB selection cap.
- `Integrations/Import/ActivityFileParser.swift`: tolerant GPX and TCX parser using `XMLParser`. One delegate handles both formats by matching normalized element names.
- `Integrations/Import/StravaExportImporter.swift`: `activities.csv` reader (RFC 4180), distance-unit inference, duplicate filtering, and review assembly.
- `Integrations/Import/StravaImportFileReader.swift`: Files-picker reader for ZIPs, folders, and individual files, with security-scoped access.
- `Integrations/Import/StravaImportStore.swift`: wizard phases. Reading runs on a detached task.
- `Integrations/Import/StravaImportView.swift`: instructions, review with activity-type filters and select all, and the result summary.
- `Activity/ActivityStore.swift`: `importStravaActivities(_:)` saves confirmed activities with `ActivitySourceMetadata.Kind.strava`, rebuilds `CLLocation` samples from parsed points, and attaches heart-rate metrics when the file provided them.

## Limits And Follow-Ups

- FIT parsing is the largest coverage gap. Many Strava exports carry FIT rather than GPX or TCX, and those activities currently import without route, elevation, or heart rate.
- Imported routes without altitude samples carry a flat elevation profile, because `SavedRoutePoint` has no way to express "altitude unknown".
- Cadence from files is parsed but not yet surfaced in activity detail.
- Compressed archives are read fully into memory. Very large exports fail with a clear message instead of being streamed.
- Photos and social data from the export are intentionally out of scope.
