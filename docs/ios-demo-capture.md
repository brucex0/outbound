# iOS Demo Capture

Open this when recording a repeatable Plainstride product clip for the website, social media, or documentation.

## Capture

From the repository root:

```sh
./scripts/capture-ios-demo.sh
```

Optionally provide an output directory and Simulator UDID:

```sh
./scripts/capture-ios-demo.sh artifacts/ios-demo <simulator-udid>
```

The script builds and runs only `testDemoCaptureHarvestHalfMarathon`. It resets the app sandbox on the selected iPhone Simulator, fixes the status bar at 9:41 with a full battery, records the scripted flow, and writes:

- `plainstride-demo-raw.mp4`: unframed Simulator capture.
- `plainstride-demo-social.mp4`: 1080×1920 blurred-background framed export.
- `plainstride-demo-loop.mp4`: short silent loop for lightweight embeds.
- `plainstride-demo-loop.gif`: compact documentation preview.
- `xcodebuild.log`: capture diagnostics.

Generated files live under ignored `artifacts/` by default.

## Story And Data Safety

The UI test pauses long enough to show:

1. the seeded Redmond Harvest Half Marathon route on Today;
2. the transition into its simulated live run;
3. route progress and live coaching metrics after two deterministic five-minute advances;
4. pause, resume, finish, and the post-run result.

The capture uses the existing `HarvestHalfMarathonSimulation` route and `-OutboundSimulatedHarvestRun` launch argument. It runs in a fresh app sandbox, pre-grants Simulator Motion & Fitness and location access, bypasses authentication, disables Firebase, discovery tooltips, and Watch preparation, and never reads an account's health or location history. The UI test stops on the result screen without saving the generated activity.

## Editing The Clip

- Change interaction timing in `testDemoCaptureHarvestHalfMarathon` by adjusting `pacedPause` calls.
- Change the loop excerpt with the `-ss` and `-t` values in `capture-ios-demo.sh`.
- Keep the raw export as the reusable source; regenerate derived formats instead of hand-editing every copy.
