# Motivation UX

Open this when designing or building daily motivation, coach-driven engagement, nudges, comeback flows, or post-activity emotional rewards.

## Product Goal

Make Outbound feel like a coach that understands the user's day and gives them a doable next step.

The motivation system should not feel like a separate quotes or notifications feature. It should feel like part of the coach relationship that already exists in the app.

The coach should feel present across the whole product:

- before the run as the daily guide
- during the run as a calm companion
- after the run as the voice that helps the effort mean something

Core loop:

1. Daily spark
2. One clear `Now` recommendation
3. Light readiness tuning when helpful
4. Activity recording
5. Post-activity emotional reward
6. Momentum reflection

## Coach Surface Model

The product should have two distinct coach surfaces.

### 1. Coach tab or page

Purpose:
- relationship home for the selected coach
- place to check in, tune coaching style, and see what the coach wants for today
- home for future memory, plan, and reflection features

Recommended role:
- promote Coach into its own primary tab if coaching is the product thesis
- do not hide coach inside Profile long-term

What belongs here:
- selected coach hero card
- daily message
- readiness check-in
- today suggestion cards
- recent reflections and momentum notes
- coaching settings such as tone, voice, intensity, and nudge frequency
- future training plan and recovery advice

What does not belong here:
- dense historical charts
- broad account settings
- generic profile management

### 2. In-activity coach companion

Purpose:
- make the coach feel like a run mate instead of a notification engine
- keep the user feeling accompanied without cluttering the recording experience

Form:
- persistent small avatar during active sessions
- short visual reactions plus audio guidance
- tap to expand into a slightly richer coach panel when wanted

## UX Principles

- Motivation should always lead to an action, not dead-end inspiration.
- The app should reward showing up, especially for short sessions.
- Missed days should trigger softness and re-entry, not guilt.
- Copy should feel spoken by the selected coach persona, not by the system.
- History and stats support the experience, but action should come first.
- The coach must feel present, but never needy or noisy.
- The coach should act more like a good running partner than a talking dashboard.

## Home Screen Structure

The Home tab should feel like a "today" space instead of a dashboard.

## Current Product Decision

Decision:
- remove the dedicated Record tab
- keep Me as the motivation surface for recommended actions
- add a shared floating activity button on Me and Social
- let the floating button quick-start directly into the shared start page
- let the activity page remain dismissible during a live session and reopen from the floating button

Why:
- the product thesis is coach-led activation, not a neutral recording utility
- Me should still answer `what should I do today?` before asking the user to self-direct
- Social also needs a fast path into activity without pushing the user back to Me first
- a single floating button works better as a global activity anchor than as a freestyle shortcut
- quick start should feel immediate, so it should not stop on an extra chooser page first
- allowing re-entry into an active session makes the recording flow feel more resilient and premium

Non-goals for this step:
- do not turn Me into a dense dashboard
- do not force the user through a long setup flow before every activity
- do not remove the ability to start something unstructured or freestyle
- do not make the floating button visually louder than the coach recommendation on Me

Design consequence:
- Me keeps recommended starts inline, but not every start path needs to live there
- the shared start page becomes the direct quick-start surface for freestyle and suggested sessions
- the recording camera/map experience stays intact; only the pre-start and re-entry model changes

Future fallback:
- if the floating button feels too dominant, reduce its visual weight before moving start actions back into the hero

## Start Surface Design

The product now has two start surfaces with different roles.

### Me

Me remains the recommendation surface.

Recommended start actions:
- primary guided CTA in the spark card
- one compact `Now` card with the main action for today
- optional secondary action inside the same card

Principle:
- guided, not gatekeeping

This means the screen should feel like:
- the coach has a recommendation
- the user can accept that recommendation in one tap
- freestyle is still easy to reach, but no longer needs to sit inside the hero

### Floating Activity Button

The floating button appears on:
- Me
- Social

The floating button does not mean `start freestyle`.

The floating button means:
- `quick start / return to activity`

When idle:
- tapping the button opens the shared start page directly
- for MVP, this start page defaults to freestyle run confirmation

When a session is active or paused:
- tapping the button returns the user to the existing in-progress activity page
- the button becomes the persistent re-entry anchor for the live session

### Activity Page Flow

1. User opens Me.
2. User taps a suggested action on Me, or taps the floating button on Me/Social.
3. App opens the shared start page directly.
4. If the entry came from a suggestion, the start page opens on that suggested confirmation state.
5. If the entry came from the floating button while idle, the start page opens on freestyle confirmation.
6. User starts recording.

### Freestyle Design

Freestyle remains one tap away from the floating button.

Requirements:
- visible immediately with no intermediate chooser page
- no guilt framing
- no need to choose a recommendation first
- can default to run for MVP if needed
- should not outrank the recommended action visually on Me

### Confirmation State

The existing pre-start confirmation pattern should become the shared entry point for both:
- guided starts
- freestyle starts

Guided confirmation should show:
- suggestion title
- duration / activity type
- short coach line
- `Start now`
- `Change activity`

Freestyle confirmation should show:
- simple session label such as `Freestyle run`
- optional one-line coach framing such as `No pressure. Just start where you are.`
- `Start now`
- `Change activity`

### Information Hierarchy

The Me motivation surface should keep this order:
- one emotionally strong hero
- one compact `Now` card
- one compact recent-activity card
- optional momentum below

The user should never have to scroll to find the recommended start, and the floating activity button should remain visible as the global fallback.

### 1. Coach Spark Card

Purpose:
- emotional entry point
- daily context
- primary call to action

Content:
- coach avatar or portrait
- short daily spark headline
- one-line supporting message
- primary CTA such as `Start 10 min walk`
- optional secondary action such as `Other ideas`

Example:

```text
[ Coach avatar ]   "You don't need a perfect session.
                    You need a beginning."

                    Today is a good day for something light.

                    [ Start 10 min walk ]
                    [ Other ideas ]
```

Behavior:
- refresh once per day
- tone reflects selected coach persona
- if the user already completed an activity today, swap to a congratulatory version

### 2. Readiness Check-In

Purpose:
- adapt suggestion difficulty
- adjust coach tone for the day

UI:

```text
How are you feeling today?

[ Low energy ] [ Okay ] [ Ready ] [ Stressed ]
```

Behavior:
- ask at most once per day
- do not block the rest of the screen
- collapse into a summary chip after selection, for example `Today: Low energy`
- skipping should be passive; the user can just ignore it

### 3. Suggested Actions

Purpose:
- turn motivation into a concrete next step
- remove planning friction

Use 2-3 cards only.

Card anatomy:
- duration
- activity type
- one-line coach framing

Examples:

```text
[ 5 min reset ]
"Just loosen up and move."

[ 10 min easy run ]
"Keep it relaxed. Build rhythm."

[ Fresh air walk ]
"No pressure. Just get outside."
```

Behavior:
- tapping a card launches the shared recording confirmation flow with a lightweight plan context
- suggestions should feel approachable, not like training plans

Current implementation:
- Me still owns suggested starts
- freestyle is reached from the activity page instead of the hero
- the floating activity button on Me and Social also opens the shared activity page

## Activity Page

The activity page is now the shared surface for:
- suggested-session confirmation
- freestyle confirmation
- live-session re-entry

When opened from the floating button while idle, it should skip an intermediate chooser and go straight to the freestyle start state.

Future goals work should plug into this page as context, not as a full setup interruption. The coach can reference the active weekly focus here, but initial focus setup should still begin in Me.

## Live Session Dismissal

Users should be able to leave the activity page while an activity is still active.

This should not pause, stop, or finish the session.

### Dismiss Affordance

Use a visible top `chevron.down` button instead of swipe-to-dismiss.

Reason:
- the activity page already contains gesture-heavy surfaces such as the map and camera
- swipe-down would compete with map gestures and create ambiguity
- the down-arrow communicates `hide this page, keep the session alive`

Rules:
- down arrow hides the activity page
- pause button pauses the session
- finish button ends the session
- the floating activity button reopens the page

### Floating Button Session States

The floating activity button should signal live session state:
- idle: default start treatment
- active: live visual treatment
- paused: paused visual treatment

The clue can be communicated through:
- icon change
- color change
- a small live or paused indicator

The button should not become noisy or oversized.

### 4. Momentum Strip

Purpose:
- reinforce progress without leaning too hard on stats or streak anxiety

Example messages:
- `You're building rhythm`
- `2 activities this week`
- `Back after a rest day`
- `Short sessions still count`

Design:
- compact
- swipeable or horizontally scrollable
- emotionally framed rather than number-heavy

Goal-aware progress should land here before it grows into any larger progress page.

Examples:
- `1 of 3 sessions this week`
- `15 min left on your weekly focus`
- `You completed this week's focus`

### 5. History / Feed

Existing feed or activity history should stay below the motivation layer. Action-driving content belongs above the fold; history is supporting context.

## Coach Tab Structure

If we add a dedicated Coach tab, it should become the emotional front door of the app.

Recommended top-to-bottom structure:

1. Coach hero
2. Daily spark
3. Readiness check-in
4. Suggested actions
5. Momentum strip
6. Recent reflection
7. Coach tuning controls

Example:

```text
[ Coach Maya avatar ]
"You don't need a big day. You need a real one."

[ Low energy ] [ Okay ] [ Ready ] [ Stressed ]

[ 10 min easy run ]
[ Fresh air walk ]
[ Shakeout + photo ]

You're building rhythm.

Yesterday:
"You showed up even when energy was low."

[ Tone ] [ Voice ] [ Nudge frequency ]
```

Design note:
- this should feel more intimate and alive than a settings page
- think conversation, not configuration

This same principle should guide goal setting. If we add weekly goals or focus areas, the coach should introduce them as a short conversation with reply chips, not as a static form.

## Key User Journeys

### Normal Day

1. User opens Home.
2. User sees the daily coach spark.
3. User optionally answers the readiness check-in.
4. User chooses one of the suggested actions.
5. User starts recording.
6. User receives in-activity coach nudges.
7. User finishes and sees a positive reflection.

Tone:
- supportive
- lightly energizing

### Comeback Day

Trigger:
- user has been inactive for a short window such as 2-4 days

Flow:
1. Home avoids any "catch up" framing.
2. Coach spark invites a fresh start.
3. Suggested actions skew smaller and easier.
4. Finish reflection rewards return, not performance.

Example:

```text
Fresh start today?

No catching up. Just reconnect.

[ 5 min walk ]
[ 10 min easy session ]
```

Tone:
- forgiving
- low pressure
- re-entry focused

### Momentum Week

Trigger:
- user has been active consistently in recent days

Flow:
1. Home acknowledges rhythm.
2. Suggested actions can scale slightly upward.
3. Finish reflection emphasizes pattern and confidence.

Example:

```text
You're building something steady.

Want to keep the rhythm going?

[ 15 min easy run ]
[ Repeat yesterday's vibe ]
```

Tone:
- confident
- earned
- forward-moving

## Pre-Start UX

When a user taps a suggested action, show a lightweight confirmation state before recording begins.

Example:

```text
10 min easy run

Coach Maya says:
"Keep this one light. Today is about showing up."

[ Start now ]
[ Change activity ]
```

Purpose:
- create a small commitment moment
- make the suggested action feel intentional

## In-Activity UX

During recording, the motivation layer should mostly step aside and let the existing camera/map experience lead.

Coach nudges should reference:
- readiness check-in state
- suggested action context
- recent adherence state such as comeback or momentum

Examples:
- `Nice and easy. This already counts.`
- `Good. You're back in motion.`
- `You've got a good rhythm going.`

Guideline:
- keep on-screen motivation minimal
- prefer audio nudges and short overlays over dense text

### Coach Avatar In Session

This is a strong idea and should be treated as a core interaction, not decoration.

Recommended behavior:

- show a persistent compact coach avatar on the active session screen
- place it away from key recording controls and map/camera switching
- animate subtly when the coach is about to speak or has a new check-in
- keep the default state small and quiet
- allow tap to expand into a coach card with the latest message, session intent, and quick controls

Recommended compact states:

- `Idle presence`: just the avatar, lightly breathing or glowing
- `Speaking`: brief pulse or ring animation while audio plays
- `Check-in`: small text chip such as `How's the effort?`
- `Celebration`: tiny positive reaction after milestones such as first mile or comeback completion

Recommended expanded card content:

- current coach line
- today's intent, such as `Easy effort` or `Just show up`
- one quick reply if we support interaction later, such as `Too hard` or `Doing good`
- mute / less / more coach controls

What the avatar should do well:

- provide companionship
- make the coach feel embodied
- reinforce the selected persona
- offer reassurance at moments of doubt

What the avatar should not do:

- cover the camera scene
- bounce constantly
- interrupt every metric change
- become a cartoon mascot that cheapens the tone

### Check-In Model During A Run

The best version is not constant talking. It is timed companionship.

Use three types of interventions:

1. affirmation
2. check-in
3. guidance

Examples:

```text
Affirmation:
"Good. Settle in. This is enough."

Check-in:
"How's that pace feeling?"

Guidance:
"Back off slightly. Keep this easy."
```

Cadence guidelines:

- first supportive nudge after the run settles in
- check-ins at meaningful intervals, not on a timer alone
- milestone reactions at distance, duration, or comeback moments
- fewer nudges when the user chose low energy or low coach intensity
- more guidance only when the user is in a structured workout or clear goal session

### Future Interaction Layer

Long-term, the avatar can become lightly interactive.

Promising future behaviors:

- user taps `Too hard` and the coach shifts the rest of the run tone
- user taps `Need a photo moment` and the coach suggests a capture prompt
- user taps `Quiet for a bit` and the coach pauses nudges temporarily
- user finishes a segment and gets a brief face-to-face reflection

Avoid full chatbot behavior during the run. Fast, low-friction interactions are better than open-ended conversation while moving.

## Finish UX

The finish moment is a key emotional payoff and should not be just a stats handoff.

### Immediate Reflection Card

Show a short reflection before or above the save/discard controls.

Example:

```text
Nice work.

You showed up on a low-energy day.
That matters.

12 min completed
```

Purpose:
- reward follow-through
- recognize context, not only output

### Save Flow

Keep the existing save/discard flow, but anchor it with the reflection so the session feels meaningfully closed out.

### Return to Home

After save, the hero card can shift into a post-activity mode.

Example:

```text
Session logged

That's two activities this week.
You're building consistency.
```

## Notification UX

Notifications should be sparse, behavior-aware, and coach-voiced.

Useful categories:
- morning spark
- comeback nudge
- optional late-day gentle reminder

Examples:
- `Ten minutes still counts.`
- `Fresh start today?`
- `Want an easy reset with Coach Maya?`

Rules:
- avoid guilt language
- default to no more than one motivational push per day
- skip motivation pushes after the user has already completed an activity
- reduce frequency if pushes are repeatedly ignored

## Tone System

Define coach copy using a few simple tone axes:

- gentle vs intense
- warm vs direct
- playful vs focused

Examples:
- warm / gentle: `A small session is still a real session.`
- direct / focused: `No drama. Shoes on. Ten minutes.`

This keeps the UX structure stable while making each coach persona feel distinct.

## MVP Recommendation

Ship the smallest complete loop first:

1. Coach spark card on Home
2. One-tap daily readiness check-in
3. 2-3 suggested action cards
4. Local motivation state logic from recent activity history
5. Post-finish reflection card

This provides a full motivation arc without requiring backend work, notification tuning, or new AI dependencies.

## Architecture Mapping

This concept fits the current app shape with minimal disruption.

Relevant existing pieces:
- `CoachCatalogStore` already owns persona-related customization
- `VirtualCoach` already handles coach nudges during active sessions
- `RecordView` already owns the activity start flow
- `ActivityFeedView` is the logical Home insertion point
- `LocalActivityStore` can support local behavior-derived motivation states

Suggested additions:
- `DailyMotivationEngine` to determine home state, daily spark, suggested actions, and finish reflections
- `DailyCheckInStore` to persist one daily mood value in `UserDefaults`
- Home-specific SwiftUI views for spark, check-in, suggested actions, and momentum
- lightweight session-intent context passed into the Record flow and VirtualCoach

## Visual Direction

Lean toward an editorial coach-companion feel instead of a metrics dashboard.

Guidelines:
- one strong featured card at the top
- generous spacing
- large copy
- fewer metrics above the fold
- color/background tone reflecting coach personality
- subtle motion on card appearance instead of gamified clutter

The emotional goal is simple: the app should feel like it understands the user's day and offers a manageable next step.
