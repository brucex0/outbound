# Progress Stats And Insights

Open this when changing period comparisons, trend ranges, training-load logic, insight eligibility, or Progress analytics.

## Product Contract

- Progress answers three questions: what changed, why it may matter, and what the runner can do next.
- The primary surface stays local-first and works offline from saved activities.
- Tabs are `Now`, `Trends`, `Insights`, and `Records`.
- Shoe mileage is not part of Progress. Gear remains available in Settings and activity metadata.
- Insights describe supported patterns, not diagnoses or causal claims.

## Delivered Scope

### V1: Period Comparison

- This week versus the same elapsed portion of last week.
- This month versus the same elapsed portion of last month.
- Rolling 28 days versus the preceding 28 days.
- Distance, moving time, activity count, and elevation deltas.
- A zero previous value is shown as new activity rather than an infinite percentage.

### V2: Trends And Consistency

- Sport-specific trend history for `4W`, `3M`, `6M`, and `1Y`.
- Distance, time, activity count, elevation, and average-pace selectors.
- Pace is never combined across sports.
- Best efforts, PRs, and race predictions use running activities only.
- Insights cover active weeks, long-activity share, measurable activity-goal completion, and preferred time of day.

### V3: Training Quality

- Pace efficiency compares two 28-day running windows only when each has at least two qualifying runs, average heart rate differs by no more than 5 bpm, and pace differs by at least 2%.
- Heart-rate-weighted load sums zone minutes multiplied by zone number.
- Load-ramp insights require recorded HR zones, evidence in both seven-day windows, at least four recent HR-zone activities, and a change of at least 20%.
- Intensity balance uses the share of recorded HR time in zones 4–5 and requires at least three recent HR-zone activities.

### V4: Grounded Companion Explanations

- Each insight is a deterministic semantic result with a category, confidence, evidence payload, and priority.
- The UI localizes the explanation and displays the supporting figures and a bounded next-step suggestion.
- Confidence is based on sample depth and is labeled `Emerging`, `Solid`, or `Strong`.
- The highest-priority supported insight appears on `Now`; the complete ranked set appears under `Insights`.
- No generative response is allowed to invent an insight that the deterministic engine did not produce.

## Eligibility And Guardrails

- Ignore activities of 60 seconds or less.
- Use matched partial calendar periods so a midweek or midmonth total is not compared with a completed prior period.
- Treat slower pace as context, not failure; weather, terrain, fatigue, and workout purpose may explain it.
- Suppress small changes instead of manufacturing a narrative.
- Goal completion applies only to measurable distance, duration, or calorie goals and uses a 98% completion tolerance.
- Time-of-day patterns require at least five activities in 42 days and at least 60% in one day part.
- A long-activity share above 50% prompts recovery-oriented copy without labeling the week unsafe.

## Data Boundaries

- `ProgressStatsEngine` receives normalized activity type, totals, optional average heart rate, optional HR-zone seconds, route points, and optional measurable-goal completion.
- Calculations and rendered evidence remain on device.
- Product analytics records only surface opens, bounded control selections, insight count buckets, and the top semantic insight category.
- Never send exact distance, duration, pace, heart rate, load, goal result, time of day, activity ID, or insight copy to analytics.

## Extension Rules

- Add a typed evidence case before adding explanation copy.
- Define sample thresholds, comparison windows, suppression thresholds, and failure behavior in this document.
- Keep copy localized in English, Spanish, and Simplified Chinese.
- Prefer a new evidence-backed category over a generic generated observation.
