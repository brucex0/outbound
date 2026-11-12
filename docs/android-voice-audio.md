# Android Offline Voice Audio

Open when changing fixed voice preparation, countdowns, download persistence, or voice readiness UI. Shared coaching semantics and dynamic audio remain in `live-coach-operations.md`.

## Delivery

- On authenticated app startup, prepare only the active app language (`en`, `es`, or `zh-Hans`) and saved voice/persona/style. Changing that selection cancels obsolete work and prepares the new selection. Reconnection and the settings Retry action resume missing recordings.
- Fetch the signed catalog, verify ES256 with the trusted key, validate its declared version, and verify each recording's SHA-256, byte count, and mono 24 kHz PCM WAV format. A previously verified catalog remains usable offline.
- Prioritize speed warnings and pause/resume. Download each missing recording once at a time per checksum; reuse existing files. Attempts are bounded to 60 seconds overall and individual asset requests to 12 seconds. Cancellation interrupts active asset requests.
- Store the signed manifest and verified recordings atomically under private `filesDir/Plainstride/LiveCoachAudio`. Existing backup/device-transfer exclusions cover this directory. Retain current-catalog recordings for previously selected languages/voices; prune obsolete hashes only after a complete preparation.
- The old cache directory is not migrated. An existing development install must prepare the new durable store online once; no database reset is needed. Rebuild with `cd android && ./gradlew :app:assembleDebug`.
- Settings shows preparation progress, offline readiness, or an incomplete state with Retry. Activity start never awaits preparation. With Voice enabled and audio incomplete, show a temporary toast, start normally, and continue preparation. Available clips and dynamic audio can still play; unavailable fixed cues are skipped.

## Bundled Countdown And Tick

- Bundle the six reviewed countdown recordings (five through one plus Go) for both voices and all three locales. These are unchanged source WAVs, about 1.70 MB before APK compression. Countdown playback uses the selected coach voice with no network or device-TTS dependency.
- Resolve countdown language from the active Compose configuration and explicitly refresh it on app-language changes; the singleton application context is not the locale authority. Verify and preload the selected six recordings locally on startup/selection change. If they are not ready at start, show a toast and use the visual countdown immediately; do not wait for speech initialization or download late countdown beats.
- Play complete WAV clips through a static AudioTrack loaded before playback, so short English words do not stall waiting for a streaming buffer to fill. The full-pack warning describes coaching cues separately from bundled countdown readiness.
- Await each voiced countdown clip’s AudioTrack completion before advancing the visible beat. Anchor the existing one-second minimum (420 ms for Go) to the first rendered audio frame, so first-beat audio-focus/output startup cannot consume the beat. Cancellation stops active and queued countdown audio; unavailable audio retains the visual beat and one transient notice. Walk/Hike still skip the start countdown.
- The stretch tick remains bundled at `feature/recording/src/main/res/raw/stretch_tick.wav`. Requested stats retain their device-speech path; live numeric progress remains cloud-streamed. Neither is added to the fixed-pack preparation.

Refresh or check the reviewed countdown subset:

```sh
python3 scripts/sync-android-countdown-audio.py
python3 scripts/sync-android-countdown-audio.py --check
```

The generator checks all locale/voice/cue identities, original checksums, sizes, and PCM format. It does not synthesize, transcode, or approve new recordings.

## Verification

- Build-only: `JAVA_HOME=/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home ANDROID_HOME="$HOME/Library/Android/sdk" ./android/gradlew -p android :app:assembleDebug --max-workers=2 --no-parallel`.
- Inspect fresh install, interrupted/retried preparation, offline restart, corrupt/missing files, and language/voice changes. Confirm only the selected full pack downloads, valid files survive restart, and recordings with mismatched transcripts are not substituted.
- Start with Voice on during incomplete preparation and offline: expect a temporary toast, immediate visual countdown/recording, and no delayed countdown audio. Also check Voice off, Walk/Hike, cancel/restart, and a normal prepared start.
- Listen to three-two-one-Go in EN/ES/ZH with both voices on speaker/headphones; confirm full words, no overlap, correct voice, cancellation, and no interference with music/coaching. A build and checksum check alone do not establish audibility or device timing.
