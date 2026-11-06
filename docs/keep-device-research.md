# Keep Device Research — 2026-11-05

Open this for the observed Keep feature map, plan UX evidence, and Plainstride opportunity backlog.

Follow-up: [Sport and Me deep probe](keep-sport-me-research.md), including working scrolling, custom running workouts, audio settings, metrics and privacy controls.

Workout execution follow-up: [planned warm-up transition and Plainstride comparison](keep-workout-transition-research.md).

## Scope and evidence

- Inspected the Chinese-language Keep app on Bruce’s connected iPhone through iPhone Mirroring. This is a logged-in account-specific snapshot, not a claim about every Keep version, market, or subscription tier.
- All five primary tabs were visited. Plan overview, weekly-day editor, calendar, schedule actions, leave form, initial intake, workout detail, movement list, smart-training sheet, tools, account menu, and AI plan handoff were opened.
- **This is a broad feature inventory with a deeper plan probe, not exhaustive functional verification.** Visible entry points are distinguished from opened flows below. No real workout was recorded or saved, no purchase made, no plan replaced/deleted, and no leave request applied.
- Tapped the AI coach’s built-in “generate plan” shortcut. This sent the generic request “help me generate a plan” and added a chat turn; its response linked to a questionnaire. No new personal answers were supplied to that questionnaire.
- The beginner running intake’s existing body-information confirmation was advanced once without edits, then exited at the running-status question. Server persistence of that confirmation was not inspected.
- Screenshots are retained in [the evidence folder](../artifacts/keep-research-2026-11-05/). Body-information and profile/previous-chat screenshots were excluded from the committed evidence. Other screenshots can still contain account-specific plan state or third-party community content; review before external sharing.
- Mirroring exposed no usable app accessibility tree. Clicks worked, but repeated scroll calls did not move content. Consequently, content below the visible viewport, horizontal carousels, and long program stages remain incomplete.

## Feature inventory

“Opened” means the destination was inspected, not that its end-to-end behavior was validated. “Entry” means only a label/control was observed.

| Area | Observed functionality | Coverage |
| --- | --- | --- |
| Navigation | Courses, Schedule, Sport, Discover, Me | All five opened |
| Course discovery | Search; Courses / Plans / Tools / member area; recent courses; recommended plans; topic chips and filter | Catalogs opened; search/filter results unverified |
| Courses | Difficulty level, duration, calorie range, author, rating, member restriction, official labels, movement list | Workout detail and movement list opened |
| Course actions | Frequent practice, add to calendar, cast to TV, comments, practiced/liked count, sharing, more menu, equipment, GO | Entry points; no publishing or recording |
| Smart training | Heart-rate guidance shown as currently unsupported for inspected workout; disabled option selected | Sheet opened; hardware behavior unverified |
| Plans | Active plan plus recommended running, cycling, abdominal, fat-loss, muscle-building, custom-training, and general-wellness programs | My Plans opened; active running plan deeply inspected |
| Plan discovery | Outcome-oriented recommendation hero, custom-plan CTA, themed collections, member labels, participation counts | Visible catalog inspected |
| Plan intake | Existing body information/body type; running-status choice; general custom intake also includes injury location | Initial steps opened, later steps unverified |
| Plan calendar | Week strip, dated workout rows, completion circles, rest days, add schedule, leave, plan management | Calendar opened; no completion marked |
| Daily schedule | Recently practiced workouts with direct Start; sleep, food, water, More; My Plans, My Courses, Manage Schedule, Leave | Visible lower section inspected |
| Sport launch | Free mode, goal mode, zero-foundation mode, quick fat-burn mode, sweat-related mode; outdoor run, indoor run, outdoor walk, More Sports | Launch and goal mode opened; other modes are entries |
| Goal recording | Duration target, editable time, arrows to other goal types, music, equipment, GO | Duration goal displayed; recording not started |
| Devices | Watch/device shortcuts; recommendation to train with a watch | Entry points; pairing unverified |
| AI coach | Chat composer; generate plan, food logging, data analysis, body-record shortcut; attachment/add control; voice/headset, menu and coach selector | Coach opened; generic plan shortcut exercised |
| Tools | Outdoor/indoor running, weight logging, easy audio run, food analysis, water logging; sleep-environment analysis and leg-shape assessment cards; sport/assessment/record filters | Catalog opened; individual analyses unverified |
| Discover | Following, community, medals, races, store, promotional categories; two-column feed; compose control | Community opened; other destinations are entries |
| Me | Profile, social counts, running distance summary; membership; courses, activities, food, orders/wallet | Overview opened; personal values not transcribed |
| Health dashboard | Today overview, body capability, all data; food/training/sleep gauges; AI insight with deeper analysis link | Overview visible; model accuracy unverified |
| Account menu | Exercise coins, benefits, certificates, posts, saved/liked content, friends, family, teams, help, settings | Menu opened; destinations unverified |
| Messaging | Inbox with unread badge, scan shortcut | Entry points only |
| Commercial layers | Membership offers, member-only content, event/promotion tabs, store, orders/wallet | Visible offers; prices not treated as stable or generally available |

## Plan deep dive

### Discovery and commitment

- My Plans mixes one active program with recommendations. The active row shows membership and `0/20` training days. Recommendations include named creator plans and generic custom plans.
- The discovery hero advertises outcomes from a supposedly similar cohort, including average weight change and completion rate. These are **Keep’s marketing claims**, not independently validated evidence. Do not copy the numerical claims into Plainstride.
- Named plans and course thumbnails make the offering concrete before the user commits. “Custom” and membership badges communicate a different product path, but multiple overlapping customization entry points can be hard to distinguish.

### Active running program

Observed program: `保持元气 · 自由漫跑计划` (roughly, “Stay energized · relaxed running plan”). “漫跑” is the wording shown; this is not a comic feature.

- Intermediate program: 20 training days, 60 courses, four selected weekdays (Tuesday, Thursday, Saturday, Sunday).
- Five phases, four training days per phase. Copy permits rearranging training days and recommends roughly one phase a week, no more than two weeks per phase.
- Summary shows aerobic/anaerobic proportions and estimated total calorie expenditure. These are displayed estimates, not verified physiology or measured future results.
- Phase 1 / Day 1 bundles a 5-minute warm-up, a 5 km main run, and a 7-minute stretch, with a combined 46-minute commitment.
- Day 2 previews a different main run and combined duration/distance. Later phases were not reached because scrolling did not work.
- Important detail: calorie values differed between the program overview, scheduled rows, and workout detail. The detail uses a range and offers a more precise estimate via a Keep band. Formula/context differences were not investigated; a defect cannot be concluded.

### Plan controls

- Overview menu: **Adjust training days**, **Customize again**, **Leave plan**.
- Weekly-day sheet shows all seven weekdays, highlights selected days and today, recommends 1–4 days, and has Save. The existing program used four selected days. No selection or save was applied.
- Calendar displays separate warm-up, run, and stretch rows under a date, plus a rest-day card on the next day.
- Each date has **Add schedule** and **Take leave**. Scheduled-row menu offers adjust current plan training days, leave plan, and delete this schedule. These destructive actions were not exercised.
- Leave form says schedules will be postponed from the selected date. It asks reason and duration, capped at 14 days. Reasons include injury, bad weather, too busy, too tired, travel, low mood, and menstruation. The default displayed a five-day duration. No request was confirmed, so actual rescheduling semantics remain unverified.
- The form’s reasons are a product affordance; they do not establish any condition about this account holder.

### Workout execution preparation

- Warm-up detail exposes difficulty `K1`, five minutes, estimated calorie range, membership restriction, course rating and author.
- Movement list displays 11 movements with thumbnails, durations, and an intensity legend. Visible examples include ankle circles, hip circles, alternating arm swings, and dynamic leg stretches.
- This creates a clear bridge from a high-level program to a concrete session. Video playback, audio cues, pausing, offline downloads, completion credit, and post-workout feedback were not tested.

### Intake and AI

- Beginner 5 km recommendation opened a progress-bar questionnaire, starting with existing body information and body type, followed by three running-status choices: just starting and finding it hard; running for a while but inconsistent; regular running and accustomed to the rhythm.
- The general questionnaire opened from AI additionally shows injury location in the first screen.
- The AI shortcut returned a card asking the user to fill a questionnaire with a “View details” action. This observed route is **chat-to-form handoff**, not evidence of a plan generated directly from conversation.
- Later constraints, schedule choices, generated result, paywall, and plan acceptance were not reached. Do not infer those steps from the progress bar.

## Calendar follow-up with scrolling

Follow-up on the same date, after Bruce manually scrolled the overview. Automated scrolling then moved the overview through all five phase headings and the final day. Scrolling on the Schedule shell remained inconsistent; targeting a different content region eventually moved it. This supersedes the original later-phase visibility limitation, but does not establish reliable scrolling automation.

### Program progression and ending

- Phase 1 rotates main courses: a stress-relief run, variable-speed runs, and an aerobic run, while repeating the same five-minute warm-up and seven-minute stretch.
- Observed Phase 1 totals include 42, 46 and 47 minutes. The course title “5 km” does not always equal the displayed distance: two variable-speed courses show 4.5 and 4.7 km. These may be course-family names; actual workout targets were not verified.
- Phase 2 introduces another “5 km” course, then reuses earlier courses. Phase 3 also reuses the aerobic and new course. A phase label alone does not explain its physiological purpose on this screen.
- **Displayed duration anomaly:** Phase 2 Day 1 and Phase 3 Day 2 show the new “5 km” course as **1 minute**, with a **13-minute** total including warm-up/stretch. Its displayed calorie estimate is 320. The arithmetic is internally consistent but implausible as the full duration of a 5 km run. This is a reproducible UI observation, not a confirmed root cause or verified execution defect.
- Phases 4 and 5 visibly use 8 km aerobic and fartlek courses. Main durations are 45 and 62 minutes; total commitments are 57 and 74 minutes. The warm-up/stretch remain unchanged.
- Final Phase 5 Day 4 is the 74-minute bundle; the overview ends with “No more content.” No graduation/reassessment CTA was visible at this uncompleted plan’s footer. Completion-triggered behavior remains unknown.

### Daily view and date navigation

- The Schedule shell leads with food/training/sleep scores, a coach summary, Analyze Today’s Arrangement and Chat with Coach, then a selected-day strip and plan card.
- **Visible mismatch:** on November 5, the coach summary described today as a rest day while the today-selected card listed warm-up, run and stretch. The full calendar also listed those workouts for November 5 and rest on November 6. Selecting November 6 changed the card to rest after loading, while the summary continued saying “today.” Possible causes include stale summary or date/context mismatch; no root cause was investigated.
- Date selection updates can arrive after the first screenshot; wait for loaded content before interpreting the selection.
- The lower shell repeats recently practiced courses, daily sleep/food/water logs, More, and My Plans / My Courses / Manage Schedule / Take Leave.
- Full-calendar date selection jumps the dated list to that day. Selecting November 9 showed November 9–12, and exposed Return to Today.
- November 10 includes warm-up/run/stretch **plus a body-type assessment**. Opening the assessment starts a sex-selection flow; it was exited without answers. Its presence is evidence of a scheduled assessment checkpoint, not evidence that its results automatically adapt the plan.
- Assessment-row menu differs from the main workout menu: adjust current plan training days or delete only this schedule. Neither was applied.
- Plan Management lists the active plan with 0/20 progress; Manage opens adjust training days, customize again, and leave plan. Only one plan was listed for this account; multi-plan support remains unknown.

### Adding entries and recurrence

- Add Schedule first offers Create Schedule and Log Food.
- Create Schedule expands to self-selected courses, training plan, outdoor activity, live class and body assessment.
- Outdoor Activity opens Add Training with Recently Practiced / My Courses / Outdoor Activity tabs and search. Outdoor choices are Run, Walk and Bike; selection count and Next support a multi-selection-style flow, though only Run was selected in the draft.
- Next opens training-day selection. A weekly-day sheet says the training content repeats **four weeks** and can be adjusted at any time.
- Dismissing that sheet reveals a calendar for freely selecting training dates within **30 days from today**, plus Clear Selection, a shortcut back to weekday selection, and Save.
- No dates or schedule were saved. Back triggered an unsaved-change confirmation; Exit was selected, then the Add Training screen was closed. The full calendar returned with its existing rows. No new record was observed.
- This is a general scheduling system alongside personalized plans, not evidence that a manually added activity is reconciled with plan load or replaces an existing workout.

### Additional Plainstride opportunities

- **One authoritative today state:** derive coach summary, daily card and calendar from the same dated plan version, and visibly distinguish today from a browsed future date.
- **Explain phases:** show the purpose and expected progression, not just numbered blocks and course rotation.
- **Validate time estimates:** reject implausible course durations before summing the day, distinguish a video/intro duration from planned exercise duration, and make missing estimates explicit.
- **Make added sessions plan-aware:** preview whether a manual run supplements or replaces a session, and reassess weekly load without silently stacking work.
- **Use meaningful checkpoints:** a plan review should reflect goal progress and completed sessions; verify what an assessment measures before claiming it improves running guidance.
- **Keep recurrence readable:** preview the actual dates and end date for repeated workouts; clearly distinguish a four-week recurring routine from an adaptive training plan.

## What Plainstride can do better

These are product hypotheses informed by observed screens and repository contracts, not claims that Keep lacks capabilities elsewhere.

| Priority | Proposed experience | Why it improves the observed journey | Plainstride starting point |
| --- | --- | --- | --- |
| P0 | One plan explanation: goal → current phase → this week → today | Combines Keep’s tangible program structure with an immediate next action | Existing plan details already show rationale, tradeoff, statistics and week preview; improve continuity before adding new screens |
| P0 | Show **total time**, then warm-up / main / cooldown as one session | Keep’s bundle is useful, but three calendar rows can turn one commitment into three chores | Existing stretch routines and post-save celebration can support the finish; inspect launch/planning contracts before linking all stages |
| P0 | “I have 20 minutes”, “Move this”, “I need a break” beside today’s plan | Makes ordinary life changes accessible without browsing management menus | Existing constraints, daily adaptation, skip and rebuild contracts; UI/API gaps need a focused audit |
| P0 | Before/after adjustment preview with one reason | Makes adaptation legible and preserves agency, rather than merely claiming personalization | Activity-aware planning already documents confirmation for multi-workout changes; surface and polish this instead of rebuilding it |
| P0 | Break → return flow based on reason and elapsed time | A simple date shift may be inadequate after illness/injury or a long gap | Keep’s leave screen promises postponement; actual implementation unknown. Plainstride should reassess rather than cram missed work |
| P1 | Goal-aware progress: completed key sessions, sustainable volume, readiness to progress | Avoids presenting calorie totals or checklist fullness as the primary proof a plan works | Existing Progress and planning evidence can be connected; do not invent race certainty |
| P1 | Accept observed baseline in one tap, edit anything | Avoids re-entering facts or repeatedly confirming body information | New-user onboarding contract already specifies recent-evidence inference and editable provenance |
| P1 | Let AI complete structured intake within the same conversation | Removes the observed chat → questionnaire handoff | Already specified in reusable plan setup; verify implementation/runtime continuity before calling it a new feature |
| P1 | Honest offline plan and launch readiness | Ensures today’s plan remains usable with clear cache freshness | Existing cached-plan direction; runtime/offline behavior not checked in this research |
| P2 | Curated plans with distinct promises and readable tradeoffs | Borrow Keep’s concreteness without requiring its content volume | Authored plan recommendations exist; improve titles, preview and fit explanations |

### Recommended first product slice

- Focus on **plan confidence and recovery from disruption**, rather than expanding into Keep’s shopping, assessments, and broad content marketplace.
- Today: show the main session, total commitment including optional preparation/recovery, and one sentence linking it to the goal.
- Plan detail: show phase intent and this week, distinguish committed near-term sessions from adaptable future direction.
- Adjustment: offer shorter / different day / break; explain the changed session and any weekly impact before committing a material plan change.
- Return: acknowledge the break, reassess current capacity, and offer a gentle return without backlog or shame.
- Preserve one meaningful primary activity; warm-up/stretch completion should not inflate training-session adherence or create duplicate activity credit.
- Treat pain/illness as conservative constraint handling, not diagnosis. Keep private reason codes out of social output and analytics payloads.

### Evaluate the hypothesis

- Plan detail → first planned session start and completion.
- Disrupted-week users who accept an adjustment and return within seven days; segment by prior engagement to avoid attributing all differences to the UI.
- Time to modify a session, adjustment abandonment, undo/reversal rate, repeated request for the same adjustment.
- User understanding: can they explain why today’s session supports their goal and what changed after a break?
- Guardrails: no stacked intensity after a miss, no duplicate credit for bundled stages, no stale-plan claim, no private health reasons in analytics/social.
- Proposed measurements are future work; this documentation change adds no product behavior or analytics events.

## Remaining probe checklist

- Scroll-dependent catalog and horizontal mode/sport carousels. All five phase headings and the final plan day were reached in the calendar follow-up; individual course execution remains unverified.
- Full plan intake and generated result, ideally with an explicitly disposable account.
- One real planned workout lifecycle: start, pause/resume, audio/video controls, finish/discard, completion linkage, reflection.
- Missed-day behavior, leave application and return, date editing, plan replacement, multiple-plan rules, custom workout substitution.
- Offline/cache behavior, device/watch integration, permissions, notification reminders, accessibility and localization.
- Search/filter results, food/sleep/water/weight entry, analysis explanations, achievements/races/teams/family, commerce, settings/export/privacy.
- App version and subscription entitlement were not verified. Never describe unvisited items as absent.

## Evidence map

Screenshots use the numbering captured during the probe; omitted numbers are intentional.

- [01-schedule-bottom](../artifacts/keep-research-2026-11-05/01-schedule-bottom.png)
- [02-my-plans](../artifacts/keep-research-2026-11-05/02-my-plans.png)
- [03-active-plan](../artifacts/keep-research-2026-11-05/03-active-plan.png)
- [04-plan-actions](../artifacts/keep-research-2026-11-05/04-plan-actions.png)
- [05-training-days](../artifacts/keep-research-2026-11-05/05-training-days.png)
- [07-plan-intake-running-status](../artifacts/keep-research-2026-11-05/07-plan-intake-running-status.png)
- [08-plan-discovery](../artifacts/keep-research-2026-11-05/08-plan-discovery.png)
- [09-course-catalog](../artifacts/keep-research-2026-11-05/09-course-catalog.png)
- [10-sport-launch](../artifacts/keep-research-2026-11-05/10-sport-launch.png)
- [11-recording-goal](../artifacts/keep-research-2026-11-05/11-recording-goal.png)
- [12-discover](../artifacts/keep-research-2026-11-05/12-discover.png)
- [13-account-menu](../artifacts/keep-research-2026-11-05/13-account-menu.png)
- [14-calendar](../artifacts/keep-research-2026-11-05/14-calendar.png)
- [15-calendar-actions](../artifacts/keep-research-2026-11-05/15-calendar-actions.png)
- [16-plan-leave](../artifacts/keep-research-2026-11-05/16-plan-leave.png)
- [17-workout-detail](../artifacts/keep-research-2026-11-05/17-workout-detail.png)
- [18-movement-list](../artifacts/keep-research-2026-11-05/18-movement-list.png)
- [19-smart-training](../artifacts/keep-research-2026-11-05/19-smart-training.png)
- [20-ai-plan-handoff](../artifacts/keep-research-2026-11-05/20-ai-plan-handoff.png)
- [21-tools](../artifacts/keep-research-2026-11-05/21-tools.png)

- [42-plan-days-2-4](../artifacts/keep-research-2026-11-05/42-plan-days-2-4.jpg)
- [43-phase-two-duration-anomaly](../artifacts/keep-research-2026-11-05/43-phase-two-duration-anomaly.jpg)
- [44-phase-three](../artifacts/keep-research-2026-11-05/44-phase-three.jpg)
- [45-phase-four-8km](../artifacts/keep-research-2026-11-05/45-phase-four-8km.jpg)
- [46-phase-five](../artifacts/keep-research-2026-11-05/46-phase-five.jpg)
- [47-plan-end](../artifacts/keep-research-2026-11-05/47-plan-end.jpg)
- [48-calendar-plan-management](../artifacts/keep-research-2026-11-05/48-calendar-plan-management.jpg)
- [49-add-schedule-choices](../artifacts/keep-research-2026-11-05/49-add-schedule-choices.jpg)
- [50-calendar-entry-types](../artifacts/keep-research-2026-11-05/50-calendar-entry-types.jpg)
- [51-calendar-add-outdoor](../artifacts/keep-research-2026-11-05/51-calendar-add-outdoor.jpg)
- [52-repeat-four-weeks](../artifacts/keep-research-2026-11-05/52-repeat-four-weeks.jpg)
- [53-select-dates-30-days](../artifacts/keep-research-2026-11-05/53-select-dates-30-days.jpg)
- [54-future-date-assessment](../artifacts/keep-research-2026-11-05/54-future-date-assessment.jpg)

## Plainstride references

- [Reusable onboarding and plan setup](new-user-onboarding.md) — current product contract; includes evidence-aware intake and conversational continuity.
- [Activity-aware planning v2](activity-aware-planning-v2.md) — current near-term adaptation, evidence boundaries and confirmation semantics.
- [Guidance plans](guidance-plans.md) — broader planning architecture; contains historical phase/status notes, so prefer the newer focused contracts when they disagree.
- `ios/Outbound/Outbound/Features/Planning/TrainingPlanViews.swift` — source inspected for existing recommendation/detail UI; no device runtime equivalence was verified.
- [Stretch routines](stretch-routines.md) and [post-save celebration](activity-post-save-celebration.md) — route here before proposing a bundled session implementation.
