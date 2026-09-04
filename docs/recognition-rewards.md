# Recognition And Rewards

Open this when designing or building badges, milestones, post-run recognition, or social reward loops.

## Product Goal

Make progress feel noticed, not scored.

Outbound should not use rewards as a generic gamification layer. Recognition should feel like the guide and the product noticing effort, momentum, and participation in a way that helps the user come back tomorrow.

## Positioning

Use `recognition` as the main product language.

Why:
- it fits the guide relationship better than `achievement`
- it can include short sessions, comeback days, and social participation
- it avoids the cold tone of points, levels, and grind-heavy systems

Use `badge` as the internal and UI object when the product needs a compact collectible artifact.

Example mapping:
- user sees: `Recognition`, `Noticed this week`, `Guide noticed this`
- app tracks: `BadgeDefinition`, `BadgeAward`, `RecognitionFeedItem`

## Principles

- Reward showing up, not only performance.
- Short sessions count.
- Missed days should not create punishment mechanics.
- Rewards should feed the next action, not end in a trophy case.
- The guide should frame why a badge mattered.
- Social rewards should feel expressive and lightweight, not cutthroat.
- V1 should prefer a small set of meaningful badges over a large catalog.

## Competitive Takeaways

What other apps tend to do well:
- Strava: social proof, challenge participation, visible accomplishments
- Garmin Connect: dependable badge system, points, and habit loops
- Nike Run Club: guidance, milestone framing, and challenge motivation
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
- immediate on-device unlock evaluation for the save experience
- account-backed awards that restore after reinstall or sign-in on another device
- guide-framed unlock messaging
- post-run unlock moments
- next-day Today reinforcement
- optional sharing for a small subset of badges

Defer:
- points
- levels
- streak freeze or streak repair systems
- large badge catalogs
- seasonal challenge engine
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

## Guide Framing

Every badge should come with a short guide explanation.

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
- vary tone by selected guide persona later

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
- spark subtext: `Guide noticed: Back In Motion`
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

Me now includes a compact `Milestones` section beneath weekly progress. It shows up to four recent earned badge icons and a trailing disclosure arrow; tapping the card opens the full Recognition destination grouped by family. When nothing has been earned yet, one neutral sparkles icon keeps the row lightweight without exposing locked badges.

The profile/history surface:
- group by family
- show guide copy and earn date
- avoid making unearned badges feel like a wall of failure

Activity cards in Profile and History can show a compact badge pill and thumbnail overlay when that saved activity earned a recognition.

Important milestones such as comeback or weekly-focus completion can also appear as a small orb on the main guide/avatar surface to make the achievement feel alive outside the badge list.

## Relationship To Goals

Badges should support weekly focus, not replace it.

Recommended role split:
- goals answer: `what am I aiming for this week?`
- recognition answers: `what effort did the app notice?`

This keeps the system from turning into pure goal compliance.

## Relationship To Social

Social rewards should reinforce private Circles and the existing loops in `Squad`, `Clubs`, and `Rivals`.

Recommended mapping:
- `Your Circle`: contribution and weekly-completion moments from `docs/your-circle.md`; do not create a repeatable badge for every completed week
- `Squad`: support badges such as `Good Teammate`
- `Clubs`: participation badges such as `Relay Player`
- `Rivals`: outcome badges such as `Rival Edge`

Avoid:
- public shaming
- visible missed-target badges
- reward mechanics that push spam comments or low-value sharing

## Persistence And Sync

`RecognitionAward` is the account-owned source of truth. The backend stores one row per user and badge, including the earn date, family, optional source activity/reference, rule version, and whether the award can be shared. The unique `(userId, badgeId)` constraint makes evaluation and retries idempotent.

The iOS stores keep an account-scoped `UserDefaults` cache so earned moments render immediately and remain useful offline. On sign-in and foreground refresh they:

1. claim any legacy or newly earned cached awards so existing users keep valid local progress;
2. fetch the canonical server collection; and
3. replace the account cache with that response.

The activity save request includes the badge IDs earned from exact client context plus the user's time-zone and calendar-week convention. Authenticated API requests also carry that calendar context so weekly Social rules use the same local-week boundary. The backend backfills rules derivable from synchronized activity history, which restores awards such as `First Step`, `Short Counts`, `Back In Motion`, `Week Closed Well`, `Finished What You Started`, and `Steady Return` even after reinstall. Context-dependent awards such as `Three This Week` and `Kept It Easy` require the saved client claim because historical activities alone do not contain the goal/check-in intent needed to reproduce them accurately.

Social mutations evaluate server-owned rules for `Good Teammate`, `Relay Player`, and `Photo Finish`, while recognition refresh also derives those awards from historical server interactions, memberships, event participation, and photo shares. `Rival Edge` stays dormant until a backend-owned rivalry result exists. Another runner's profile exposes only awards marked shareable, and only to that runner or an accepted connection; the full award collection remains private.

Award deletion does not follow activity deletion. Recognition is a durable account event after it is earned, while the source reference is explanatory provenance rather than ownership.

## Current Implementation

- `backend/src/services/recognition.ts` owns definitions, historical activity backfill, idempotent awards, and Social rule evaluation.
- `GET /v1/recognition` returns the canonical collection and performs safe historical backfill.
- `POST /v1/recognition/claims` migrates exact-context awards detected by the client.
- `RecognitionStore` and `SocialRecognitionStore` provide the account-scoped offline cache and reconcile it with the server.
- Post-run, Today, Me, History, and accepted-connection profiles render from those reconciled awards.

Apply the schema before deploying the API:

```sh
cd backend
npm run db:generate
npm run db:push
```

Production rollout should use the schema job documented in `docs/backend-deploy.md`.

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
- Does `Kept It Easy` require a guided suggestion start, or can guide intent be inferred from check-in state?
- When multiple badges unlock at once, which family gets display priority in post-run?
