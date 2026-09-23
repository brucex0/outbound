# Your Circle

Open this when designing or building invitation-only Circles, weekly shared motivation, Circle management, Circle celebrations, or Circle analytics.

## Product Decision

Plainstride should make being active feel good now and easier to return to because effort is noticed by a useful AI companion and shared with a few people who matter.

The core loop is:

`Personal nudge -> commitment -> activity -> effort recognized -> Circle progress -> supportive response -> return`

`Your Circle` is the first permanent relationship feature built around that loop. It is an invitation-only group for family, friends, and other accepted connections who want to live a more active, positive life together. It is optional and must not weaken the solo experience.

Circle is not a leaderboard, public community, or chat product. It is a lightweight place to share workouts, stay connected, choose a meaningful weekly theme, notice effort, Cheer, and plan an activity.

Circle uses a distinct sealed-huddle mark rather than generic two-person or three-person symbols. The outer ring should read as private and contained, while the two abstract figures leaning together should read as close and trusted. Use this mark consistently for Circle navigation, creation, active Circle cards, invitations, and transient Circle feedback; keep generic people symbols for connections and open groups.

## Product Principles

- Make progress feel shared, not scored.
- Reward participation and return, not pace or athletic rank.
- Keep creation fast; advanced choices belong in management.
- Keep the Circle relationship separate from its current goal.
- Allow rest, target changes, and paused weeks without guilt language.
- Never infer that a member owes the group a workout.
- Treat accepted Circle members as trusted people: show useful workout details inside the Circle while keeping access closed to outsiders.
- Use warm, energetic motion and copy without childish effects or constant interruption.
- Reuse existing Social, activity-event, notification, recognition, and activity-save systems.

## Product Model

### Circle

A Circle is the persistent relationship container.

- It has one creator/owner and may support additional admin roles later.
- It contains at least two accepted members, including the owner.
- Capacity is backend-configured through `CIRCLE_MEMBER_LIMIT`, snapshotted onto each Circle at creation, returned to clients, and not presented as a fixed product promise. The default is six and the operational range is 2–100.
- Pending invitations do not count as members until accepted, but the server must prevent invitations that could exceed the Circle's snapshotted capacity.
- A person may belong to multiple Circles. Do not impose a one-Circle database constraint.
- Each person may choose one primary Circle for Today. The first active Circle becomes primary until changed.
- A Circle may be active, archived, or awaiting its first accepted invitation.
- Archiving preserves history and can be reversed.

### Weekly Theme

A Weekly Theme is an optional, replaceable shared intention for one Circle week. It creates emotional direction without turning the Circle into a scorecard and is not part of the Circle's identity.

The owner chooses or changes the Circle-wide theme. Members do not receive an edit action for Circle-wide settings; they may independently set or clear only their own commitment after a theme is active. This permission rule applies consistently in Circle detail and Circle settings so a member can never enter an empty editor.

The first version supports nine curated themes:

- `build_consistency`
- `one_small_step`
- `keep_the_rhythm`
- `move_for_your_mood`
- `recover_and_recharge`
- `do_something_together`
- `explore_somewhere_new`
- `try_something_different`
- `celebrate_every_effort`

Each curated theme has a localized title, supporting sentence, and symbol. The editor shows three recommendations followed by the remaining catalog. Recommendations use safe Circle-level context only: an upcoming activity, whether the Circle has recorded activity this week, and whether a legacy numeric week completed. They must not expose or judge an individual member.

The owner may instead write a custom theme with a required title of at most 50 characters and an optional supporting note of at most 120 characters. Custom text is visible only through authorized Circle responses and must never be included in product analytics.

Themes use the `theme` focus mode. A theme itself is never completed. Activities remain visible as shared participation, while each member may optionally set an activity-count commitment. Do not add distance, duration, calories, streaks, rankings, or a shared numeric target to this first-version UI.

### Circle Week

Each Circle has an explicit reset weekday and IANA timezone.

- Defaults come from the creator's locale and current timezone.
- The owner can edit both in Circle settings.
- The current week is materialized or resolved server-side so every member sees the same interval.
- Historical weeks retain the theme, optional custom copy, and commitments from that week.
- A theme change may apply now or next week. `Now` updates the current week; `Next week` updates the next/default configuration without rewriting the current week.

### Commitments

- Under an active theme, each member controls only their own optional activity-count commitment.
- Present a few sensible presets and a custom value rather than a fixed 0–7 rule.
- The server should accept a bounded positive custom count; use a generous validation ceiling to prevent malformed input without presenting it as a product limit.
- Turning the commitment off removes it. Do not describe the member as behind, skipped, or owing the Circle activity.
- Commitments may be changed during the current week without punishment or public audit copy.
- Do not aggregate personal commitments into a Circle-wide target or completion state.

### Contributions

A qualifying contribution is one canonical saved activity. Current supported types are running, walking, hiking, cycling, and swimming; newly supported canonical activity types count automatically.

- Recorded, imported, and manually entered activities count.
- There is no minimum pace, distance, or duration.
- Use the activity's actual start time to select the Circle week, not its import or sync time.
- An activity that crosses a reset boundary belongs to the week in which it started.
- One canonical activity contributes at most once to a given Circle week.
- If a person belongs to multiple active Circles, the same activity may contribute once to each. Contributions are encouragement, not scarce currency.
- Late imports update the historical week in which the activity occurred. They do not inflate the current week.
- Activity deletion removes its linked Circle contributions and recomputes affected totals. Do not retract already delivered human Cheers or celebration notifications.
- Account deletion follows the existing cascade and privacy contract.

## Creation And Invitation

Circle creation should take less than a minute:

1. Select at least one accepted connection, up to the capacity returned by the backend.
2. Accept the generated name or edit it.
3. Create the Circle and send invitations.

Do not require a Weekly Theme during creation. After creation, offer `Choose a weekly theme` as a clear next step that can be skipped.

### Creation Experience

Use each state for one communication job:

- **Before creation — make the idea desirable.** The empty Social card leads with `Active. Positive. Together.` and shows walking, running, and cycling symbols. One concise sentence connects goals, progress, the people closest to the member, and mutual encouragement. The whole card opens creation.
- **During creation — turn inspiration into one easy decision.** Keep one scrollable screen rather than a wizard: repeat the concise promise, then show `Who helps you keep moving?`, the accepted-connection picker, an optional name, and one persistent `Create your Circle` action. Show the number selected but do not advertise a fixed maximum; disable additional choices only when the backend-delivered capacity is reached.
- **After creation — teach the loop and offer the next useful action.** Do not drop directly into a mostly empty detail screen. Show a warm success state with the invited people, explain that all supported activities count, show that workouts are visible to the Circle and can receive Cheers, then make `Choose a weekly theme` primary and `Open Circle` secondary. Explain that personal commitments are optional.
- **After activation — let real people and workouts carry the meaning.** Circle detail leads with its relationship statement, weekly progress, and member rows containing recent workout context. Cheers sit beside people, and `Plan an activity` remains the primary shared action.

Avoid a carousel, educational modal, or mandatory goal setup. The screen itself should demonstrate the product loop with real connections and real workout context.

The generated name may use first names for a small selection and a concise localized fallback for a larger group. Store the resolved name so every member sees the same value.

Invitation rules:

- Only accepted connections may be invited in the MVP.
- Membership always requires explicit acceptance.
- The owner becomes a member atomically when the Circle is created.
- Before another member accepts, show the Circle as awaiting members in Social and do not show it on Today.
- Invitation acceptance must recheck capacity, connection status, blocks, and membership.
- Decline, cancel, expiration, and duplicate requests must be idempotent.
- Existing blocks override every Circle read and mutation.

## Surfaces

### Today

Keep the existing Today hierarchy and the planned-workout card's established display rules. Circle is an independent row rather than a replacement for another eligible card.

- Show one compact card for the member's primary active Circle below any currently visible workout or activity-event card.
- Keep Circle to one tappable row: truncating name, member count in parentheses, breathing room, then trailing weekly progress.
- A future Circle activity adds a compact calendar indicator and becomes the Circle row's status without displacing today's workout.
- Keep Circle above the measured selected-route/goal preview and manual goal pills with a narrow gap instead of allowing the surfaces to overlap.
- Do not show Circle creation on Today.
- An imminent joined activity event keeps its existing priority within the non-Circle opportunity slot.
- A joined Circle activity scheduled for today replaces the separate planned-workout card and pairs with that workout's structure. The center Start action and the activity detail Start action launch the same event-linked workout.
- If the primary Circle has no Weekly Theme, the card may show a recent Cheer or a restrained `Plan an activity` action instead of numeric progress.
- If there are several Circles and no valid primary selection, choose the most recently active Circle and persist it as primary.

The card should answer only:

- What is the Circle's current state?
- What did I contribute?
- What is the next useful action?

### Social

Keep the current Social screen and place `Your Circle` directly below Connections and above Upcoming.

- No Circles: show one restrained creation card after Connections has loaded successfully.
- Pending Circle: show invitation/setup status and management access.
- One Circle: show its compact status and open the detail screen.
- Multiple Circles: the tabbed Social Circle tab lists every Circle inline in the store's primary-first order; there is no separate overflow list or list screen.
- Keep creation in the section header as a plus action instead of adding a second creation row below the preview.
- Circle detail owns member progress, recent workout context, Cheers, activity planning, history, and settings.

Do not rename the production Social tab or redesign the wider feed for this feature.

### Circle Detail

The detail screen includes:

1. Circle name and member avatars.
2. `Up next` activity cards with date, location, attendance count, and a direct path to activity detail.
3. Current Weekly Theme, shared activity count, and the viewer's optional commitment when applicable.
4. Member rows with first name, avatar, completed/target state, and Cheer.
5. `Plan an activity`.
6. Recent Circle moments limited to Cheers, completed activities, and weekly completion—not a duplicate activity feed.
7. Management entry.

Member progress may show `2 of 3`, `3 of 3 · 2 extra`, `Contributed 2`, `Skipping this week`, or no numeric state. Once a member exceeds a commitment, cap the completed portion at the target and show additional activities separately instead of presenting progress such as `5 of 3`. Under each member, show their most recent activity from the current Circle week with title/type, date and time, duration, distance, and available workout metrics such as average heart rate and energy. Do not expose companion inferences or why someone changed or skipped a target.

## Actions

### Cheer

- A Cheer is a preset reaction to a member's current Circle-week progress or recent workout.
- It does not require a public activity post; the Circle member row supplies the workout context.
- Start with a small localized set such as encouragement, celebration, and support; do not accept free text in the MVP.
- Make repeated requests idempotent or explicitly toggleable so tapping cannot create notification spam.
- Do not award points or rank people by Cheers.

### Plan An Activity

- Reuse the existing activity-event creation and invitation flow.
- Enter from Circle detail with current Circle members preselected but editable.
- The organizer must still review the invitees, time, attendance mode, and optional meetup before creation.
- Store the resulting event through the existing activity-event model; do not create a second Circle-specific activity object.
- The event may retain a Circle source reference for navigation, but activity-event privacy and attendance rules remain authoritative.
- Scheduled and active events live in Circle `Up next`; they enter Recent moments only after reconciliation or completion.
- Opening any planned-activity card routes to the existing activity-event detail screen.
- On the scheduled day, pair the event with the runner's current planned-workout intent. Keep its workout steps and workout reference while using the event title and event link.
- If no personal plan exists, launch the event as a freestyle activity.
- One saved recording completes the paired planned workout and reconciles the activity-event participant; never create duplicate personal activities.

## Post-Activity And Recognition

After a qualifying activity is saved and synchronized, add one compact Circle contribution message to the existing post-activity reflection:

```text
You moved your Circle forward.
4 activities together this week.
```

Behavior:

- The personal reflection remains primary.
- Circle contribution appears once and does not block saving.
- If recognition also unlocks, compose the reflection, Circle progress, and at most one prominent recognition into one hierarchy rather than stacking celebration screens.
- If several Circles receive the contribution, show the primary Circle and summarize the rest compactly.
- If the server is temporarily unavailable, save the activity normally and show Circle progress after reconciliation instead of claiming success prematurely.

Weekly themes never enter a completed state and do not produce Circle-wide completion notifications. A future personal-commitment reflection may recognize the individual privately, but it must not reinterpret the shared theme as a scored challenge.

## Management

Use one clear Circle settings screen.

Settings fields, Weekly Theme controls, and personal commitments keep a local draft while editing, then sync changed values when their screen closes. Unchanged drafts do not call the API, and sync results use transient success or failure feedback; these screens do not use explicit Save buttons.

Owner controls:

- rename Circle;
- invite or remove members;
- choose a curated theme or write a custom theme;
- change reset weekday or timezone;
- apply theme changes now or next week;
- transfer ownership;
- archive or reactivate the Circle.

Member controls:

- set, edit, or clear their personal commitment when a theme is active;
- choose the primary Circle shown on Today;
- mute Circle notifications;
- leave the Circle.

Rules:

- The owner cannot leave until ownership is transferred or the Circle is archived.
- Removing or leaving takes effect immediately and revokes future access.
- Historical screens retain only the display and workout snapshots required for Circle history; removed members lose future Circle access immediately.
- API results use transient toast feedback unless the result requires a persistent action.

## Notifications

Use the existing in-app notification system for:

- Circle invitation;
- invitation accepted;
- Cheer received;
- Circle weekly goal completed;
- ownership transferred;
- relevant planned-activity event notifications.

Do not notify members whenever another member contributes. Avoid reminders that identify someone as behind. A muted member still receives security- or membership-critical state in-app when they open the Circle, but no optional Circle nudges.

Push delivery remains governed by the existing notification rollout. Circle MVP must work with the in-app inbox alone.

## Trust, Access, And Safety

Accepted Circle members may see:

- stored Circle name;
- member name and avatar;
- role;
- current target, skipped state, and completed count;
- recent Circle-week workout title/type, date and time, duration, distance, elevation, average pace, average heart rate, and energy when available;
- Circle-level combined progress;
- preset Cheers;
- explicitly shared activity events.

Do not expose to outsiders through Circle responses, and do not put workout facts into product analytics. Circle UI may show the member-authorized workout fields above, but it still excludes:

- route geometry or coordinates until Circle activity detail provides an intentionally designed map experience;
- readiness, injury, cycle, medical context, or private planning information;
- reflections, companion prompts/responses/inferences, or reasons for changing/skipping a target;
- source activity IDs in client-visible Circle progress unless required for an owner-only deletion reconciliation flow.

All Circle reads and mutations require authentication and active membership or a valid pending invitation. Enforce connection and block rules server-side. Never rely on UI hiding for authorization.

## Data And API Direction

The Prisma schema already has minimal `Circle` and `CircleMember` placeholders. Replace or extend those cleanly; do not maintain parallel legacy and production Circle models. Pre-release data does not require backward compatibility.

Recommended server-owned concepts:

- `Circle`: name, owner, lifecycle, reset weekday, timezone, and default/upcoming theme configuration.
- `CircleMember`: user, role, joined state, primary selection, notification preference, and timestamps.
- `CircleInvitation`: sender, recipient, status, expiry, and idempotency fields.
- `CircleWeek`: immutable interval plus the theme key, optional custom title/note, legacy focus-mode snapshot, and state.
- `CircleCommitment`: one member's optional personal activity-count target for one Circle week.
- `CircleContribution`: unique Circle-week/activity relation used for idempotent counting and deletion reconciliation.
- `CircleCheer`: sender, recipient, Circle week, preset type, and timestamps.

Keep primary-Circle selection account-owned and enforce at most one primary membership per user in service logic or with an appropriate database constraint.

Recommended authenticated route groups:

- list/create/detail/update/archive Circles;
- invite/list/cancel/accept/decline Circle invitations;
- add/remove/leave/transfer Circle membership;
- read/update current and upcoming Weekly Theme;
- read/update personal commitment;
- send/remove Cheer;
- select primary Circle.

The Social-home response may embed compact Circle summaries to avoid an extra initial request. Circle detail and management should use focused endpoints. Mutations return canonical updated state so the client does not reconstruct server rules.

Activity save/sync should invoke one idempotent Circle contribution reconciler after the canonical activity exists. Activity deletion invokes the same reconciler for removal. Do not make Circle availability a precondition for saving an activity.

## iOS Direction

- Keep production work under `Domains/Social`; do not connect the legacy feature-flagged Social prototype.
- Extend the existing Social contracts and store or add a focused `CircleStore` when independent mutation/loading state makes that clearer.
- Cache only member-authorized Circle summaries and workout detail, scoped by authenticated account.
- Clear in-memory and persisted Circle state when authentication changes.
- Reuse the existing connection picker and activity-event creation flow.
- Integrate the Today card through `SimplifiedAppShell` without adding a new root destination.
- Integrate the contribution message through the existing activity save and `PostRunSummaryView` flow.
- Use the shared design system, dynamic type, 44-point controls, VoiceOver labels, and Reduce Motion behavior.
- Localize every visible string in English, Simplified Chinese, and Spanish with natural product-context translations.

## Analytics

Measure the complete relationship loop:

`eligible exposure -> creation -> invitation -> acceptance -> active Circle -> theme configured -> activity contributed -> Cheer or activity planned -> following-week contribution`

Add typed provider-neutral events for:

- Circle section exposed;
- creation started/completed/failed;
- invitation sent/accepted/declined/cancelled;
- Circle activated;
- curated/custom theme selected or changed;
- personal commitment set or cleared using only a coarse target bucket;
- progress opened;
- Cheer sent/removed;
- Plan-an-activity started/completed;
- activity contribution reconciled;
- primary Circle changed;
- notifications muted/unmuted;
- member left/removed;
- Circle archived/reactivated;
- Circle operation failed with a normalized category.

Allowed properties are bounded values such as entry source, curated/custom selection type, coarse Circle-size bucket, coarse target bucket, current/next-week application, and success/failure category. Never send a custom theme title or note.

Never send Circle IDs, user IDs beyond the existing analytics identity contract, member identities, names, activity IDs, exact counts, exact activity facts, locations, health data, free text, notification text, or companion content.

Evaluate:

- invitation acceptance;
- Circle activation;
- share of members contributing each week;
- theme adoption and repeat use;
- Cheer and Plan-an-activity use;
- second- and fourth-week Circle continuity;
- D7 and D28 saved-activity retention;
- active workout weeks during the four weeks after Circle activation;
- solo start-to-save conversion as a guardrail;
- mute, leave, block, report, and qualitative pressure or trust feedback as guardrails.

This is a permanent MVP, not an A/B-gated prototype. Measure usage and retention before choosing the next investment. Do not claim that observational correlation proves causation.

## Cross-Age Validation

Use one shared product experience and test clarity, warmth, pressure, trusted-sharing expectations, and celebration tone with adults aged 18–24, 25–44, and 45–65.

Do not introduce visibly age-specific modes. Research involving ages 15–17 requires explicit account-eligibility, consent, safety, and moderation decisions; children accounts remain outside this MVP.

## Follow-On Roadmap

1. Ship and measure the complete Circle loop.
2. Tune the existing assistant launcher toward restrained, context-aware discovery; avoid persistent motion that becomes background noise.
3. Deepen effort recognition for first activities, consistency, personal records, comeback runs, difficult days, and Circle participation.
4. Add attractive route postcards, milestone cards, Circle-week keepsakes, and monthly recaps that require explicit save/share actions.
5. Expand the proven goal model into personal, friend, and community challenges centered on participation and improvement.
6. Add rare seasonal visuals, celebration variants, and AI observations only after the core loop is useful.
7. Personalize recommendations and recognition around fitness, exploration, competition, stress relief, and social connection without selectable `vibes`.

## Deferred

- Circle chat and direct messaging;
- voice notes;
- public Circle discovery;
- free-text Cheers or AI-generated comments;
- leaderboards, contribution rankings, points, levels, and streak punishment;
- automatic activity posting;
- live-run celebration animation;
- distance, duration, calories, or multi-sport Circle goals;
- children accounts;
- a broader Social redesign;
- frequent seasonal effects;
- selectable motivation `vibes`;
- a separate accessibility initiative beyond correct system behavior.

## MVP Acceptance Criteria

- A person can create a Circle from accepted connections without configuring a goal.
- Invitees can accept or decline, and blocked or disconnected users cannot join.
- A Circle becomes Today-eligible after at least two members are active.
- Owners can choose one of nine localized themes or create a custom title and optional note.
- The editor recommends three themes using safe Circle-level context and retains the theme in Circle history.
- Members never see a Circle-wide theme edit action or an empty editor.
- Members can set, edit, or clear only their own optional personal commitment.
- Multiple Circle membership works, and one primary Circle controls Today presentation.
- Qualifying canonical activities reconcile exactly once into every applicable Circle week.
- Social and Circle detail show the current theme, shared activity count, personal commitment state, and latest workout context for each member.
- Cheer and Plan-an-activity work from the shared Circle context.
- The post-activity flow presents confirmed contribution without blocking activity save.
- Weekly themes never produce score-like completion language or a Circle-wide completion notification.
- Leave, remove, mute, transfer, archive, reactivate, and primary-selection flows work.
- Offline cache never crosses accounts and stale content remains clearly non-authoritative during failed mutations.
- All new strings are localized in English, Simplified Chinese, and Spanish.
- Analytics use the typed data-minimization allowlist and cover the full funnel.
- Backend and iOS build-only verification succeed.

## Consolidated Implementation Handoff

Use the following prompt to hand the MVP to an implementation agent:

```text
Build the permanent Your Circle MVP described in docs/your-circle.md.

Read AGENTS.md and docs/INDEX.md first, then read docs/your-circle.md completely
and only the focused architecture, Social, activity-event, notification,
recognition, analytics, localization, and build docs it routes to. Inspect the
existing implementation before editing. Treat docs/your-circle.md as the
authoritative product and acceptance contract.

Deliver the complete backend and iOS vertical slice:

- Evolve the existing placeholder Circle and CircleMember Prisma models into the
  production model. Add server-owned invitations, Circle weeks, member
  commitments, idempotent activity contributions, preset Cheers, lifecycle,
  primary selection, notification preferences, and ownership transfer. This is
  pre-release data, so prefer a clean schema over compatibility scaffolding.
- Implement authenticated, membership-authorized Circle APIs with strict block,
  accepted-connection, capacity, access-control, and idempotency enforcement. Return
  canonical state after mutations.
- Reconcile recorded, imported, and manual canonical activities into the
  correct Circle week by activity start time. Reconcile deletion too. Circle
  failure must never block activity save or deletion.
- Add the fast creation/invitation flow, owner-controlled Weekly Theme configuration,
  Circle detail, and management controls. Support the curated catalog, custom title
  and optional note, safe recommendations, and optional member-owned activity-count
  commitments. Keep the Circle relationship and Weekly Theme separate.
- Support multiple Circle membership and one account-owned primary Circle.
- Add Your Circle below Connections on Social. Show one compact primary-Circle
  card in Today's existing social-opportunity slot only when eligible; imminent
  joined activity events retain priority. Do not redesign Social or navigation.
- Reuse the existing connection picker and activity-event creation flow for Plan
  an activity, with Circle members preselected but editable.
- Add preset Cheers and the required in-app notifications. Do not build
  chat, free text, public discovery, rankings, points, or automatic posting.
- Add confirmed Circle contribution and one-time weekly completion presentation
  to the existing post-run/recognition hierarchy without stacked celebrations.
- Add account-scoped offline caching, authentication-change clearing, transient
  toast feedback, accessibility, Dynamic Type, 44-point targets, and Reduce
  Motion behavior.
- Localize every new iOS string naturally in English, Simplified Chinese, and
  Spanish.
- Add typed, provider-neutral, data-minimized analytics for the full Circle
  funnel and management outcomes. Never emit identities, Circle/activity IDs,
  exact activity facts, routes, locations, health context, free text, or
  companion content.
- Update all affected focused docs so schema, behavior, API, rollout, and rebuild
  instructions remain accurate. Avoid duplicating the canonical product rules.

Follow every acceptance criterion and deferred-scope boundary in
docs/your-circle.md. Preserve unrelated user changes and keep generated or local
artifacts out of the commit. Do not run the test suite. Run appropriate backend
and iOS build-only verification, fix all relevant compile failures, review the
final diff, and commit the verified implementation before handing it back.
```
