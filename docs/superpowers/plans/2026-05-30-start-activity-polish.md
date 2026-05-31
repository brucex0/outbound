# Start Activity Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the start activity setup screen and prevent the custom goal button from wrapping.

**Architecture:** Keep the change in `RecordView` because the issue is local SwiftUI layout. Add small private constants/helpers only if they reduce duplicated styling inside the existing view.

**Tech Stack:** SwiftUI, iOS app target, existing `ActivityGoal` and `SessionIntent` models.

---

### Task 1: Document The Polish Pass

**Files:**
- Create: `docs/superpowers/specs/2026-05-30-start-activity-polish-design.md`
- Create: `docs/superpowers/plans/2026-05-30-start-activity-polish.md`
- Modify: `docs/INDEX.md`

- [x] Record the selected recommended polish direction.
- [x] Add a small implementation plan.
- [x] Route both docs from the documentation index.

### Task 2: Fix Goal Button Layout

**Files:**
- Modify: `ios/Outbound/Outbound/Activity/RecordView.swift`

- [x] Replace adaptive preset columns with two flexible columns.
- [x] Give preset buttons full-width stable height.
- [x] Force preset labels to stay on one line with minimum scale fallback.
- [x] Keep selected state icon and label aligned without resizing the grid.

### Task 3: Polish Start Screen Styling

**Files:**
- Modify: `ios/Outbound/Outbound/Activity/RecordView.swift`

- [x] Add more top breathing room under the close/assistant controls.
- [x] Tighten vertical spacing between setup sections.
- [x] Reduce setup card corner radius from the current oversized value.
- [x] Keep title readable with a slightly smaller responsive title style.
- [x] Make the Music card primary action row lighter and less nested.

### Task 4: Compile Check

**Files:**
- No source changes.

- [x] Run a build-only compile check.
- [x] Report the command and result.
- [x] Do not report test pass status because tests are not run.
