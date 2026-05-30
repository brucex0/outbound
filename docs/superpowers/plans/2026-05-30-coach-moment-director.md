# Coach Moment Director Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make live coach announcements feel high-presence and varied by directing each spoken nudge as a specific coaching moment.

**Architecture:** Keep the first pass inside `VirtualCoach`. Add private moment role helpers, use them when composing spoken analysis, and keep progress announcements as a separate role instead of the prefix for every nudge.

**Tech Stack:** Swift, SwiftUI app target, Swift Package subset `OutboundSessionAnalysis`, AVFoundation speech synthesis.

---

### Task 1: Document The Design

**Files:**
- Create: `docs/superpowers/specs/2026-05-30-coach-moment-director-design.md`
- Create: `docs/superpowers/plans/2026-05-30-coach-moment-director.md`
- Modify: `docs/INDEX.md`

- [x] Add a focused design spec that records the chosen lightweight in-place approach.
- [x] Add this implementation plan.
- [x] Add both docs to `docs/INDEX.md` so future work can find them.

### Task 2: Add Moment-Aware Speech Composition

**Files:**
- Modify: `ios/Outbound/Outbound/Coach/VirtualCoach.swift`

- [x] Add private moment role types near the other `VirtualCoach` private state.
- [x] Track recent spoken roles in `VirtualCoach`.
- [x] Reset the role history during `activate`.
- [x] Replace unconditional `coachingAnnouncement(for:message:)` stat-prefixing with moment-aware composition.
- [x] Keep progress announcements as their own spoken role.

### Task 3: Capture Expected Behavior In Focused Tests

**Files:**
- Modify: `Tests/OutboundSessionAnalysisTests/VirtualCoachTests.swift`

- [x] Add tests that describe natural coaching messages no longer requiring a progress prefix.
- [x] Add tests that describe progress-role messages still including progress context.
- [x] Do not run the test suite unless the user explicitly asks.

### Task 4: Compile Check

**Files:**
- No source changes.

- [x] Run a build-only compile check.
- [x] Report the command and result.
- [x] Do not claim test pass status because tests were not run.
