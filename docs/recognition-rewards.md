# Recognition And Rewards

Open this when designing or building badges, milestones, post-run recognition, or social reward loops.

## Product Goal

Keep durable milestones meaningful while letting the guide encourage everyday effort without turning every positive moment into a collectible.

## Positioning

Use two deliberately different product concepts:

- `Milestone`: a durable achievement the runner should still care about months later. Milestones are account-backed and appear in Me history.
- `Encouragement`: timely guide feedback such as noticing a short session or an appropriately easy day. Encouragement belongs in post-run reflection or Today and is not stored in the milestone collection.

Social recognition remains its own lightweight system and should not determine what appears in the runner's personal Milestones history.

## Principles

- Preserve encouragement for showing up without minting a permanent badge for every positive behavior.
- A milestone must represent a clear first, meaningful distance, sustained consistency, completed focus, or genuine comeback.
- Missed days should not create punishment mechanics.
- Encouragement should feed the next action; milestones should preserve meaningful history.
- The guide should frame why a milestone mattered.
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

Milestones appear in four places:

1. post-run reflection
2. Today follow-up state on the next app open
3. Social share cards for selected rewards
4. a lightweight profile/history surface later

Badge visuals can also appear as compact overlays on activity thumbnails and selected avatar surfaces for important milestones.

This lets rewards influence behavior immediately instead of becoming a dead archive.

## V1 Scope

Ship:
- a curated set of eight durable personal milestones
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

## Personal Milestone Families

Use two personal milestone families; keep Social recognition separate.

### 1. Beginnings

Purpose:
- preserve meaningful beginnings and returns

Examples:
- `First Step`: save first activity
- `Back In Motion`: save an activity after 7 or more inactive days

### 2. Progress

Purpose:
- preserve meaningful distance, completed focus, and sustained consistency

Examples:
- `Weekly Focus Complete`: complete the runner's configured weekly focus
- `Four-Week Rhythm`: save at least one activity in each of four consecutive local calendar weeks
- `First 5K`, `First 10K`, `First Half Marathon`, and `First Marathon`: reach the distance in one run, walk, or hike

### Separate Social Recognition

Purpose:
- make Social feel participatory, supportive, and alive

Examples:
- `Good Teammate`: cheer or comment on 3 friends' activities
- `Relay Player`: join a relay, club event, or team challenge
- `Rival Edge`: finish ahead of a rival in a weekly reset
- `Photo Finish`: share a saved activity with a photo

## V1 Personal Milestone Definitions

Recommended launch set:

| Badge | Family | Unlock rule | Why it matters |
| --- | --- | --- | --- |
| `First Step` | Beginnings | first saved activity | turns first use into an identity moment |
| `Back In Motion` | Beginnings | save activity after 7+ inactive days | supports comeback psychology |
| `Weekly Focus Complete` | Progress | reach the configured weekly focus target | connects an explicit goal to recognition |
| `Four-Week Rhythm` | Progress | activity in four consecutive local weeks | represents sustained consistency without daily streak pressure |
| `First 5K` | Progress | reach 5,000 m in one run, walk, or hike | marks a recognizable distance first |
| `First 10K` | Progress | reach 10,000 m in one run, walk, or hike | marks a recognizable distance first |
| `First Half Marathon` | Progress | reach 21,097.5 m in one run, walk, or hike | preserves a major endurance achievement |
| `First Marathon` | Progress | reach 42,195 m in one run, walk, or hike | preserves a major endurance achievement |

`Short Counts`, `Kept It Easy`, and calendar-day closure copy remain eligible themes for the existing post-run reflection engine, but they never create account awards or appear in Milestones. The former `Finished What You Started` rule is removed because it duplicated weekly-focus completion, and the former two-week consistency rule is replaced by `Four-Week Rhythm`.

## Unlock Logic Guidance

- Badge rules should be easy to explain in one sentence.
- One activity can unlock more than one badge.
- V1 should unlock a badge once, not as a repeatable tier system.
- If a rule depends on weekly state, use the user's local calendar week.
- Avoid hidden formulas or fuzzy scoring in V1.

Suggested inactivity rule:
- `Back In Motion` triggers when no saved activity exists in the previous 7 full days.

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
First 5K
Five kilometers in one activity. You have a real distance marker now.
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
- spark subtext: `Milestone reached: Back In Motion`
- reflection copy may still say `Short sessions count.` without creating a milestone
- suggestion framing: `Let's build on that, not top it.`

Purpose:
- make recognition influence the next action

### 3. Social

Only some badges should be shareable.

Recommended personal shareable set:
- `Back In Motion`
- `Weekly Focus Complete`
- distance milestones

Share behavior:
- use story-card presentation, not a generic trophy tile
- attach route/photo context when available
- let the user choose not to share

### 4. Profile / History

Me includes a compact `Milestones` section beneath weekly progress. It shows up to four recent durable milestone icons and a trailing disclosure arrow; tapping the card opens the full Milestones destination grouped by family. When nothing has been earned yet, one neutral sparkles icon keeps the row lightweight without exposing locked milestones.

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

The activity save request includes milestone IDs earned from exact client context plus the user's time-zone and calendar-week convention. The backend restores `First Step`, `Back In Motion`, `Four-Week Rhythm`, and distance milestones from synchronized activity history. `Weekly Focus Complete` requires the saved client claim because historical activities alone do not contain the configured goal context.

Social mutations evaluate server-owned rules for `Good Teammate`, `Relay Player`, and `Photo Finish`, while recognition refresh also derives those awards from historical server interactions, memberships, event participation, and photo shares. `Rival Edge` stays dormant until a backend-owned rivalry result exists. Another runner's profile exposes only awards marked shareable, and only to that runner or an accepted connection; the full award collection remains private.

Award deletion does not follow activity deletion. Recognition is a durable account event after it is earned, while the source reference is explanatory provenance rather than ownership.

## Current Implementation

- `backend/src/services/recognition.ts` owns definitions, historical activity backfill, idempotent awards, and Social rule evaluation.
- `GET /v1/recognition` returns the canonical collection and performs safe historical backfill.
- `POST /v1/recognition/claims` migrates exact-context awards detected by the client.
- `RecognitionStore` and `SocialRecognitionStore` provide the account-scoped offline cache and reconcile it with the server.
- Post-run, Today, Me, History, and accepted-connection profiles render from those reconciled durable awards. Existing obsolete award rows are filtered from API responses.

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

- Should `Photo Finish` remain Social recognition or become a transient Story encouragement once media loops deepen?
- Which personal-best milestones should join the distance-first set once comparable effort calculations are canonical?
- When multiple badges unlock at once, which family gets display priority in post-run?
