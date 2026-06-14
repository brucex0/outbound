# Full Social Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the optional local-first Social module while keeping no-social builds free of social feature code and strings.

**Architecture:** Social-only models, stores, recognition, seed data, and views live under `ios/Outbound/Outbound/Social` behind `OUTBOUND_ENABLE_SOCIAL`. Shared app files expose only compile-time-gated entry points or neutral no-social behavior.

**Tech Stack:** SwiftUI, Swift concurrency annotations already used by app stores, Xcode build flags through `scripts/build-install-bruce-main.sh`.

---

## File Structure

- Modify: `ios/Outbound/Outbound/App/MainTabView.swift` for the optional tab entry point only.
- Modify: `ios/Outbound/Outbound/App/OutboundApp.swift` to gate assistant social suggestions and replies.
- Modify: `ios/Outbound/Outbound/Recognition/RecognitionStore.swift` to remove social-specific state from no-social compilation.
- Create: `ios/Outbound/Outbound/Social/SocialModels.swift` for Social-only data models.
- Create: `ios/Outbound/Outbound/Social/SocialSeed.swift` for seeded posts, clubs, relays, challenges, and rivals.
- Create: `ios/Outbound/Outbound/Social/SocialStore.swift` for local Social interaction state.
- Create: `ios/Outbound/Outbound/Social/SocialRecognitionStore.swift` for Social-only awards.
- Replace: `ios/Outbound/Outbound/Social/ActivityFeedView.swift` with the expanded Social tab shell and views.
- Modify: `docs/social.md`, `docs/ios-architecture.md`, and `docs/INDEX.md` to describe the new boundary.

## Tasks

### Task 1: Isolation Cleanup

- [ ] Gate assistant suggestions/fallback replies so default builds contain no social-facing copy.
- [ ] Move social recognition state and badge definitions out of `RecognitionStore`.
- [ ] Add Social-only recognition types under `Social/`.
- [ ] Run no-social source scan and fix app-target hits outside `Social/`.
- [ ] Build no-social with `./scripts/build-install-bruce-main.sh --build-only --without-social`.
- [ ] Commit as `chore: isolate optional social code`.

### Task 2: Social Module Split

- [ ] Extract social models from `ActivityFeedView.swift` to `SocialModels.swift`.
- [ ] Extract seed content and latest-activity adapters to `SocialSeed.swift`.
- [ ] Add `SocialStore.swift` for local cheers, comments, share state, clubs, relays, privacy, reports, and blocks.
- [ ] Keep all new files wrapped in `#if OUTBOUND_ENABLE_SOCIAL`.
- [ ] Build with social using `./scripts/build-install-bruce-main.sh --build-only --with-social`.
- [ ] Commit as `refactor: split social module state`.

### Task 3: Full Local Social UX

- [ ] Rebuild `ActivityFeedView.swift` around Squad, Clubs, Relays, and Rivals sections.
- [ ] Add local comment composer, route prompt actions, report/block controls, visibility picker, relay composer, challenge join/progress controls, and rivalry claim feedback.
- [ ] Surface Social recognition feedback when cheers, club/relay actions, rivalry claims, or photo shares unlock awards.
- [ ] Keep backend copy explicit: local preview only, no network publishing.
- [ ] Build with social using `./scripts/build-install-bruce-main.sh --build-only --with-social`.
- [ ] Commit as `feat: implement local social loops`.

### Task 4: Documentation And Final Verification

- [ ] Update `docs/social.md` with implemented local loops and App Review boundary.
- [ ] Update `docs/ios-architecture.md` and `docs/INDEX.md` if file responsibilities change.
- [ ] Run both build-only checks:

```sh
./scripts/build-install-bruce-main.sh --build-only --without-social
./scripts/build-install-bruce-main.sh --build-only --with-social
```

- [ ] Run the no-social source scan:

```sh
rg -n "Social|social|Squad|squad|club|Club|rival|Rival|cheer|Cheer|relay|Relay|challenge|Challenge" ios/Outbound/Outbound --glob '!Social/**'
```

- [ ] Commit as `docs: document optional social module`.
