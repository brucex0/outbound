# Coach Moment Director Design

## Goal

Make live coach announcements feel high-presence and energetic without turning every spoken nudge into a mechanical time, distance, and pace recap.

## Current Problem

`VirtualCoach` currently speaks progress recaps on fixed time or distance milestones, then also prefixes every spoken analysis nudge with the same progress recap. The rule-based fallback varies words, but its structure is still predictable: opener, pace cue, style cue. The HUD mirrors `lastNudge`, so the product has no internal distinction between a progress check, a tactical cue, a form cue, or a hype moment.

## Design

Add a lightweight moment-directing behavior inside `VirtualCoach`, not a standalone component.

The behavior should:

- classify spoken analysis into a small role such as `progress`, `form`, `hype`, `paceAdjustment`, `segment`, `finish`, or `caution`
- decide whether the spoken announcement should include a progress recap
- avoid repeating the same role too many times in a row when another useful role is available
- keep fixed progress announcements as one role in the system, not the wrapper around every coach message

## V1 Scope

Implement this in `VirtualCoach.swift` with private helpers and tiny private types. Do not create a new file unless the logic grows large enough to deserve a separate unit.

V1 should:

- remove the unconditional `progressAnnouncement + analysis.message` composition
- keep `lastNudge` as the visual HUD message
- use progress recap only for progress-like roles
- let most AI/rule coaching messages speak as natural coach lines
- track recent spoken roles alongside text fingerprints

## Non-Goals

- Do not redesign the camera or map HUD.
- Do not change coach settings UI.
- Do not replace the session analysis providers.
- Do not add a backend dependency.

## Validation

Use a build-only compile check. The project instruction says not to run the test suite unless explicitly requested.
