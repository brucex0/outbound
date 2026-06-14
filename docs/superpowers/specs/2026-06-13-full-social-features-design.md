# Full Social Features Design

## Goal

Implement the optional Social experience as a feature-complete local-first module while preserving the default beta/App Review build as a no-social app. A build without `OUTBOUND_ENABLE_SOCIAL` must not reference Social screens, social assistant copy, social recognition state, or social feature types.

## Scope

- Keep the Social tab behind `OUTBOUND_ENABLE_SOCIAL`.
- Split Social code out of shared app files where it is not needed by the no-social app.
- Expand the local Social module to cover Squad feed, latest-run sharing, cheers, comments, clubs, relays, challenges, rivals, local report/block/privacy controls, and recognition feedback.
- Keep backend calls out of this pass. The current social doc says the surface is local/seeded until moderation, reporting, blocking, contact, and backend ownership are ready.
- Update docs for the build boundary and the local feature set.

## Architecture

The default app remains centered on Me, activity recording, assistant, goals, progress, and recognition from non-social activity. Social-specific state and UI live under `ios/Outbound/Outbound/Social` and are compiled only when `OUTBOUND_ENABLE_SOCIAL` is defined. Shared app code may expose neutral extension points, but no-social builds should not include social naming, strings, storage keys, or feature logic.

Social becomes a small local module:

- `SocialModels.swift`: social people, posts, comments, clubs, relays, challenges, rivals, visibility, and moderation action models.
- `SocialSeed.swift`: deterministic prototype data and adapters from the latest `SavedActivity`.
- `SocialStore.swift`: local state for cheers, comments, sharing, clubs, relay invites, rival claims, blocked people, reported content, and privacy defaults.
- `SocialRecognitionStore.swift`: Social-only recognition awards for support, relay/club participation, rivalry, and photo sharing.
- `ActivityFeedView.swift`: the Social tab shell and child views.

The main tab switcher continues to use compile-time gates. Assistant suggestions and fallback replies have social variants only under `OUTBOUND_ENABLE_SOCIAL`; default builds use motivation/exploration wording. RecognitionStore keeps only activity/momentum badges in default builds, while SocialRecognitionStore owns social-only rewards.

## User Experience

The Social tab should feel useful before a backend exists:

- Squad: latest-run share card, live/seeded feed, cheer and comment interactions, route prompts, visibility controls, and report/block menus.
- Clubs: joined clubs, next-run details, joining/leaving, recurring run cards, and club challenge progress.
- Relays: create a local relay invite from route/window/audience choices and surface it in Squad.
- Rivals: weekly leaderboard, lightweight “claim edge” action, and segment/weekly notes.
- Privacy/moderation: local controls that make the eventual App Review requirements visible without pretending server enforcement exists.

## Verification

Use build-only checks, not tests:

```sh
./scripts/build-install-bruce-main.sh --build-only --without-social
./scripts/build-install-bruce-main.sh --build-only --with-social
```

Also scan the no-social app source outside `Social/` for social feature strings and compile gates:

```sh
rg -n "Social|social|Squad|squad|club|Club|rival|Rival|cheer|Cheer|relay|Relay|challenge|Challenge" ios/Outbound/Outbound --glob '!Social/**'
```

Expected no-social hits should be limited to compile-time-gated code paths or neutral docs/tests outside the app target.
