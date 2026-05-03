# Recognition And Rewards

Open this when designing or building badges, milestones, post-run recognition, or social reward loops.

## Product Goal

Make progress feel noticed, not scored.

Outbound should not use rewards as a generic gamification layer. Recognition should feel like the coach and the product noticing effort, momentum, and participation in a way that helps the user come back tomorrow.

## Positioning

Use `recognition` as the main product language.

Why:
- it fits the coach relationship better than `achievement`
- it can include short sessions, comeback days, and social participation
- it avoids the cold tone of points, levels, and grind-heavy systems

Use `badge` as the internal and UI object when the product needs a compact collectible artifact.

Example mapping:
- user sees: `Recognition`, `Noticed this week`, `Coach noticed this`
- app tracks: `BadgeDefinition`, `BadgeAward`, `RecognitionFeedItem`

## Principles

- Reward showing up, not only performance.
- Short sessions count.
- Missed days should not create punishment mechanics.
- Rewards should feed the next action, not end in a trophy case.
- The coach should frame why a badge mattered.
- Social rewards should feel expressive and lightweight, not cutthroat.
- V1 should prefer a small set of meaningful badges over a large catalog.

## Competitive Takeaways

What other apps tend to do well:
- Strava: social proof, challenge participation, visible accomplishments
- Garmin Connect: dependable badge system, points, and habit loops
- Nike Run Club: coaching, milestone framing, and challenge motivation
- Peloton: frequent challenge cadence and energetic celebration

What Outbound should not copy directly:
- long streak systems as the main retention mechanic
- points and levels as the main progress language
- badge galleries that never affect the Today experience
- performance-only rewards that exclude beginners and comeback users

## Product Model

Treat rewards as a `recognition layer`, not a separate badge shelf.

Recognition should appear in four places:

1. post-run reflection
2. Today follow-up state on the next app open
3. Social share cards for selected rewards
4. a lightweight profile/history surface later

Badge visuals can also appear as compact overlays on activity thumbnails and selected avatar surfaces for important milestones.

This lets rewards influence behavior immediately instead of becoming a dead archive.

## V1 Scope

Ship:
- a curated set of 8-12 badges
- local-first unlock evaluation from saved activities and social interactions
- coach-framed unlock messaging
- post-run unlock moments
- next-day Today reinforcement
- optional sharing for a small subset of badges

Defer:
- points
- levels
- streak freeze or streak repair systems
- large badge catalogs
- seasonal challenge engine
- backend-only requirements
- badge rarity economy

## V1 Badge Families

Start with three families so the system is easy to understand.

### 1. Showed Up

Purpose:
- reward beginnings, re-entry, and small wins

Examples:
- `First Step`: save first activity
- `Short Counts`: finish a session under 15 minutes
- `Back In Motion`: save an activity after 7 or more inactive days
- `Week Closed Well`: save any activity on the final day of the current week

### 2. Momentum

Purpose:
- reinforce realistic consistency without hard streak pressure

Examples:
- `Three This Week`: complete weekly focus
- `Kept It Easy`: complete an easy-day or low-pressure suggestion
- `Finished What You Started`: complete 3 saved activities in one week
- `Steady Return`: complete 2 separate weeks with at least one saved activity

### 3. Social

Purpose:
- make Social feel participatory, supportive, and alive

Examples:
- `Good Teammate`: cheer or comment on 3 friends' activities
- `Relay Player`: join a relay, club event, or team challenge
- `Rival Edge`: finish ahead of a rival in a weekly reset
- `Photo Finish`: share a saved activity with a photo

## V1 Badge Definitions

Recommended launch set:

| Badge | Family | Unlock rule | Why it matters |
| --- | --- | --- | --- |
| `First Step` | Showed Up | first saved activity | turns first use into an identity moment |
| `Short Counts` | Showed Up | save activity under 15 minutes | teaches that small sessions count |
| `Back In Motion` | Showed Up | save activity after 7+ inactive days | supports comeback psychology |
| `Week Closed Well` | Showed Up | save an activity on the last day of week | promotes gentle weekly closure |
| `Three This Week` | Momentum | reach weekly focus target | connects goals to recognition |
| `Kept It Easy` | Momentum | complete low-energy or easy suggestion | rewards restraint and self-awareness |
| `Finished What You Started` | Momentum | save 3 activities in one calendar week | encourages rhythm without a streak |
| `Steady Return` | Momentum | active in 2 separate weeks within 21 days | rewards rebuilding consistency |
| `Good Teammate` | Social | 3 cheers/comments in a week | rewards support, not just output |
| `Relay Player` | Social | join one social challenge or relay | activates social loops |
| `Rival Edge` | Social | place ahead of one rival at weekly reset | gives Rivals a payoff |
| `Photo Finish` | Social | share activity with photo attached | rewards Outbound's camera identity |

## Unlock Logic Guidance

- Badge rules should be easy to explain in one sentence.
- One activity can unlock more than one badge.
- V1 should unlock a badge once, not as a repeatable tier system.
- If a rule depends on weekly state, use the user's local calendar week.
- Avoid hidden formulas or fuzzy scoring in V1.

Suggested inactivity rule:
- `Back In Motion` triggers when no saved activity exists in the previous 7 full days.

Suggested short-session rule:
- `Short Counts` triggers for any saved activity with duration under 15 minutes, with no minimum pace or distance requirement.

Suggested social rule:
- Count distinct support actions on distinct activities to avoid spammy farming.

## Coach Framing

Every badge should come with a short coach explanation.

Examples:

```text
Back In Motion
You came back before it felt perfect. That's real momentum.
```

```text
Short Counts
You didn't wait for a big window. You used the one you had.
```

```text
Good Teammate
You helped the week feel shared, not solo.
```

Guidelines:
- explain why the effort mattered
- prefer emotional meaning over statistic recap
- keep copy specific and short
- vary tone by selected coach persona later

## Surface Placement

### 1. Post-Run Reflection

This is the primary unlock moment.

Recommended behavior:
- show reflection first
- if a badge unlocked, append a compact recognition card below the reflection
- limit to one prominent badge card per save flow in V1
- if multiple badges unlock, show one card and summarize the rest lightly

Example:

```text
Nice work.

You showed up on a low-energy day.
That matters.

[ Back In Motion ]
You came back before it felt perfect.
```

### 2. Today Follow-Up

The next app open should reflect the badge in the spark or momentum area.

Examples:
- spark subtext: `Coach noticed: Back In Motion`
- momentum chip: `Short sessions count. You proved it yesterday.`
- suggestion framing: `Let's build on that, not top it.`

Purpose:
- make recognition influence the next action

### 3. Social

Only some badges should be shareable.

Recommended shareable set:
- `Back In Motion`
- `Three This Week`
- `Rival Edge`
- `Photo Finish`

Share behavior:
- use story-card presentation, not a generic trophy tile
- attach route/photo context when available
- let the user choose not to share

### 4. Profile / History

Defer a full badge cabinet for V1, but keep a simple `Recognition` list in mind for later.

When added, it should:
- group by family
- show coach copy and earn date
- avoid making unearned badges feel like a wall of failure

Activity cards in Profile and History can show a compact badge pill and thumbnail overlay when that saved activity earned a recognition.

Important milestones such as comeback or weekly-focus completion can also appear as a small orb on the main coach/avatar surface to make the achievement feel alive outside the badge list.

## Relationship To Goals

Badges should support weekly focus, not replace it.

Recommended role split:
- goals answer: `what am I aiming for this week?`
- recognition answers: `what effort did the app notice?`

This keeps the system from turning into pure goal compliance.

## Relationship To Social

Social rewards should reinforce the existing loops in `Squad`, `Clubs`, and `Rivals`.

Recommended mapping:
- `Squad`: support badges such as `Good Teammate`
- `Clubs`: participation badges such as `Relay Player`
- `Rivals`: outcome badges such as `Rival Edge`

Avoid:
- public shaming
- visible missed-target badges
- reward mechanics that push spam comments or low-value sharing

## Data Model Sketch

Recommended core models:
- `BadgeDefinition`: id, family, title, unlock rule, share eligibility
- `BadgeAward`: badge id, earned date, source activity ids, optional metadata
- `RecognitionFeedItem`: lightweight UI model for Today, post-run, and Social surfaces

Recommended supporting engine:
- `RecognitionEngine`

Responsibilities:
- evaluate unlocks from local activities, goal progress, check-ins, and social actions
- prevent duplicate awards
- emit coach-facing copy inputs for UI surfaces

## Implementation Order

1. Define `BadgeDefinition` and `BadgeAward` models.
2. Add a local-first unlock evaluator for saved activities and weekly focus state.
3. Surface one badge card in post-run reflection.
4. Thread recent recognition into Today spark or momentum copy.
5. Add Social share formatting for the small shareable subset.

## Copy Guidance

Prefer:
- `noticed`
- `showed up`
- `kept it going`
- `counted`
- `came back`
- `shared the week`

Avoid:
- `XP`
- `level up`
- `streak broken`
- `failed`
- `grind`
- `crushed everyone`

## Open Questions

- Should `Photo Finish` belong to Social or a future Story family once media loops deepen?
- Should `Week Closed Well` use Sunday specifically or the locale-aware last day of week?
- Does `Kept It Easy` require a guided suggestion start, or can coach intent be inferred from check-in state?
- When multiple badges unlock at once, which family gets display priority in post-run?
