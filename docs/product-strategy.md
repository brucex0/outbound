# Product Strategy

Open this when prioritizing roadmap, evaluating competitors, or deciding what Outbound should match versus differentiate on.

## Snapshot

Reviewed on 2026-04-29 using:

- current Outbound docs and iOS product shape
- App Store metadata for Strava, Runna, Nike Run Club, Garmin Connect, TrainingPeaks, ASICS Runkeeper, Map My Run, adidas Running, and Peloton
- official product positioning from Strava, Runna, and TrainingPeaks web properties

Scope update on 2026-05-03:

- reviewed public market signals from Strava, Runna, AllTrails, Zwift, and Grand View Research
- confirmed the product decision to position Outbound as endurance-first, not as a broad sports super app
- keep the architecture multi-sport capable through modality adapters, but keep the user-facing promise narrow until running, walking/hiking, and cycling feel deep

## Outbound Today

Outbound already has four notable ingredients:

- camera-first recording instead of a plain tracker
- an active in-run coach with selectable persona, voice, face, style, and nudge frequency
- emotion-first motivation design for today, comeback days, and momentum weeks
- early social concepts that are more playful than a standard feed: Squad, Clubs, Rivals, and relays

Current limitations:

- no real onboarding, identity, or friend graph
- no real backend social network yet
- no training plans, workout calendar, or structured progression
- no device ecosystem or wearable sync story yet
- no safety/live tracking, route discovery, or route recommendations
- no strong post-run progress layer beyond save/history/routes

## Market Map

The major apps cluster into five jobs-to-be-done.

### 1. Social network for athletes

Leader:
- Strava

What users buy:
- social feed
- route discovery
- challenges
- device/app interoperability
- stats and AI summaries

Takeaway:
- Strava owns the social graph and habit loop. It is the benchmark for sharing, discovery, compatibility, and social proof.

### 2. Training-plan coach

Leaders:
- Runna
- Nike Run Club
- TrainingPeaks

What users buy:
- race plans
- guided runs or coach-led sessions
- adaptive progression
- strength/recovery support
- goal framing

Takeaway:
- these products win because they remove planning anxiety. Users open them to know exactly what to do today.

### 3. Device and data hub

Leader:
- Garmin Connect

What users buy:
- reliable sync
- health trends
- workout/course creation
- badges and challenges
- trust in recorded data

Takeaway:
- Garmin is less magical, more dependable. It sets the expectation that serious runners can connect everything and inspect everything.

### 4. Broad tracker with community and plans

Leaders:
- ASICS Runkeeper
- Map My Run
- adidas Running

What users buy:
- tracking
- audio cues
- beginner-friendly plans
- challenges
- route save/discovery
- shoe tracking

Takeaway:
- these apps cover a wide middle of the market. They set the table-stakes bar for any running app trying to feel complete.

### 5. Motivation and class ecosystem

Leader:
- Peloton

What users buy:
- charismatic instructors
- habit-building programming
- challenge cadence
- premium content loop

Takeaway:
- Peloton proves that motivation plus personality can drive retention when content feels alive and fresh.

## Sports Scope Strategy

### Market signals

The opportunity is large, but the winning products are specialized around a job rather than generic sport coverage.

- Grand View Research estimates the fitness app market at USD 12.12B in 2025 and projects USD 33.58B by 2033 at a 13.40% CAGR.
- Grand View Research estimated the sports app market at USD 3.66B in 2022 and projected USD 8.03B by 2030 at a 10.9% CAGR.
- Strava's public app listing says "over 180 million active people," and its subscription positioning centers on training, progress, routes, segments, and exploration.
- Strava announced the acquisition of Runna in 2025, which is a strong signal that even the leading social fitness graph wants deeper structured coaching.
- AllTrails positions around trail discovery, navigation, conditions, offline maps, live share, reviews, photos, and 500,000+ trails. It supports hike, bike, run, and walk, but its center of gravity is outdoor discovery.
- Zwift and Peloton show that motivation can be a business, but only when the experience is purpose-built around a specific environment and habit loop.

The lesson is not "support every sport." The lesson is "own a frequent, emotionally resonant job, then expand from strength."

### Decision

Outbound should be an endurance-first coaching app:

- First-class at launch expansion: run, walk, hike/trail, bike.
- Supporting modalities: strength, mobility, recovery, and generic "other" activity logging.
- Deferred as primary sports: swimming, court sports, field/team sports, golf, climbing, skiing, and deep gym lifting.

Do not market Outbound as a sports super app. The phrase is useful only as an internal architecture ambition. User-facing positioning should stay closer to:

- `the AI coach for getting out, building momentum, and making outdoor training feel alive`
- `the running and riding app that feels like a coach, not a spreadsheet`

### Why this scope

Running, walking/hiking, and cycling share enough foundations to reuse product systems:

- GPS recording, routes, distance, duration, elevation, pace/speed, heart rate, photos, and live sharing
- coach nudges during an activity
- training plans built from endurance load, consistency, recovery, and schedule constraints
- social posts, clubs, challenges, rivals, relays, and outdoor route moments
- HealthKit and wearable integration paths

They still need sport-specific polish:

- Running needs pace, cadence, race goals, shoes, intervals, and return-to-run care.
- Walking/hiking needs route difficulty, trail conditions, time-on-feet, navigation confidence, and safety.
- Cycling needs speed, elevation, power/cadence later, bike gear, route safety, and indoor/outdoor distinctions.

That scope is ambitious enough to grow the product, but not so broad that Outbound becomes a thin tracker with an AI label.

### Architecture rule

Position narrowly, architect broadly.

The planning system should follow `docs/adaptive-planning-engine.md`: plan training stimulus first, then translate that stimulus through modality adapters. This keeps the system open to future sports without forcing the UI, coaching language, analytics, and acquisition story to support everything now.

Practical implications:

- Shared planner concepts: goal, phase, readiness, fatigue, adherence, weekly load, session count, hard/easy balance, and adaptation reason.
- Sport adapters: run, bike, walk/hike first; strength, mobility, and recovery as support adapters.
- Shared activity model: allow modality-specific fields without making every feature handle every sport on day one.
- Product QA standard: a sport becomes "supported" only when recording, summary, coaching, progress, and sharing all feel credible for that sport.

### Sequencing

Recommended sequence:

1. Make running excellent.
2. Add walk/hike as a close outdoor cousin, with safety and route language.
3. Add cycling as the second endurance pillar.
4. Add strength and mobility as plan support, not as standalone gym products.
5. Reconsider swimming or other sports only after the adaptive planner, social loops, and device integrations are stable.

The near-term wedge remains motivation plus coaching, not sport count.

## Competitive Read

### Where Outbound already feels better

- More emotionally intelligent premise than most trackers. Competitors usually motivate with plans, stats, or community; Outbound is designed to motivate with relationship.
- Stronger camera-native identity. Most running apps treat media as an afterthought. Outbound can make the run feel more vivid, expressive, and social.
- More flexible coach persona system than guided-run libraries. Outbound can become personalized rather than one-size-fits-all.
- Social concepts are fresher than a standard feed. Rivals, relays, and club loops can feel more playful and game-like than generic activity posting.

### Where Outbound is behind category expectations

- No dependable identity/social backbone yet.
- No training plan or “what should I do today?” engine.
- No strong progress layer: goals, streak alternatives, training load, PRs, benchmarks, calendar, badges.
- No route discovery or recommendation.
- No live safety or location sharing.
- No wearable/device sync story.
- No structured workout support such as intervals, target pace, or plan execution.
- No trust signals yet around consistency, depth, and reliability of recorded data.

### Where copying the market would be a mistake

- Do not become another stats-first dashboard.
- Do not overbuild coach content libraries before the personalization loop works.
- Do not chase every sport immediately; the product thesis is strongest in outdoor endurance first.
- Do not ship a generic social feed as the main differentiator. Strava already owns that pattern.

## Feature Framework

Use three buckets instead of one flat backlog.

### Table stakes to catch up

- account system and durable profile
- follow/friend graph plus privacy controls
- reliable activity sharing and comments/cheers
- route discovery, save, and import/export polish
- goals, milestones, weekly summaries, and progress views
- Apple Watch and HealthKit-first sync strategy
- live safety location sharing
- shoe tracking
- structured workout primitives: warmup, intervals, cooldown, target pace

### Core differentiators to build hard

- adaptive relationship coach that remembers mood, consistency, and context
- camera-first run storytelling during and after the activity
- emotionally smart home screen with daily spark, readiness, suggested action, and comeback mode
- socially expressive lightweight competition: relays, rivals, club moments, crew pulse
- post-run reflection that rewards showing up, not only performance

### Expansion bets

- AI-generated route ideas tied to mood, time available, and neighborhood
- creator or club-led coach personas
- async social prompts tied to photos, routes, and live moments
- recovery and strength plans tightly paired to endurance intent
- bike and walk/hike support once run quality is credible
- premium coaching tier with adaptive plans plus richer voice/video coach output

## Recommended Feature List

### V1 complete runner foundation

- signup, profile, privacy, and onboarding
- activity sharing from saved runs
- real comments, cheers, and follow graph
- route detail polish plus easy share/export
- weekly progress view with activity count, time, distance, and consistency
- goals and milestones
- live location safety sharing
- Apple Watch companion or workout sync path

### V2 coaching system

- daily coach spark on Home
- readiness check-in
- suggested action cards
- comeback-day and momentum-day logic
- structured workout support
- coach memory across sessions
- goal-aware nudges that reference training intent
- post-run reflection and weekly recap

### V3 social engine

- real clubs with membership and recurring runs
- rivals leaderboard with weekly reset
- relay invitations and live presence
- route prompts and photo prompts
- challenge creation and participation
- notifications tuned to social momentum, not spam

### V4 premium depth

- adaptive training plans
- strength and recovery prescriptions
- route recommendations
- AI session recap and next-best-action guidance
- deeper analytics for serious runners
- coach marketplace or premium personas

## Roadmap

### Phase 1: Make Outbound credible

Goal:
- users can record, save, share, and return with confidence

Ship:
- auth and profile basics
- backend-backed activities and social posts
- cheers/comments/follows
- route detail and sharing polish
- weekly progress summary
- live safety sharing

Why first:
- without trust, identity, and shareability, the rest of the product cannot compound

### Phase 2: Make Outbound habit-forming

Goal:
- users open the app before the run, not only during the run

Ship:
- motivation home redesign from `docs/motivation-ux.md`
- daily spark
- readiness check-in
- suggested actions
- comeback and momentum logic
- post-run reflection

Why second:
- this is the cleanest path to differentiation and daily retention

### Phase 3: Make Outbound useful for progression

Goal:
- users trust Outbound to help them improve, not only to capture memories

Ship:
- goals and milestone system
- structured workouts
- coach memory and adaptive nudges
- weekly/monthly recaps
- simple training plans for beginner and return-to-run use cases

Why third:
- it closes the biggest gap versus Runna, NRC, Runkeeper, and Map My Run

### Phase 4: Make Outbound socially magnetic

Goal:
- users come back because their people and status live here

Ship:
- real clubs
- rivals weekly league
- relays
- social notifications
- challenge loops
- route and photo-based sharing prompts

Why fourth:
- social loops get much stronger once identity, recording, and motivation systems are already stable

### Phase 5: Make Outbound premium-worthy

Goal:
- give serious runners a reason to pay without losing the emotional product soul

Ship:
- adaptive training plans
- richer AI analysis
- route recommendations
- premium personas
- strength and recovery programming
- deeper device integrations

## Strategy Calls

### Positioning

Best near-term positioning:

- `the running app that feels like a coach, not a spreadsheet`
- `the AI coach for outdoor endurance and active-life momentum`

Avoid positioning as:

- a Strava clone
- a pure training-plan app
- a generic AI fitness assistant
- a sports super app

### Ideal early user

Best wedge:

- beginner to intermediate runners who want encouragement, identity, and social energy more than elite analytics

Strong secondary wedge:

- comeback runners who have fallen out of routine and need emotional re-entry support

### Product thesis

Most running apps answer:

- `What did I do?`
- `How did I perform?`
- `What is everyone else doing?`

Outbound should own:

- `Can you help me want to go out today?`
- `Can you make the run feel alive while I’m in it?`
- `Can you help me feel proud enough to come back tomorrow?`

## Hard Priorities

If only five things can happen next, choose these:

1. real account plus backend-backed social identity
2. shareable activity posts with route and photo support
3. motivation-first Home with daily spark, readiness, and suggested actions
4. goals, weekly recap, and comeback/momentum logic
5. simple structured workouts plus beginner return-to-run plans

## Anti-Backlog

Do not prioritize yet:

- broad multi-sport expansion beyond run, walk/hike, bike, strength, mobility, and recovery support
- deep coach marketplace
- advanced pro analytics comparable to TrainingPeaks
- desktop/web companion products
- elaborate creator economy features

Those can matter later, but none of them strengthen the main wedge as much as motivation, trust, and social retention.
