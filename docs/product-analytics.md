# Product Analytics

Open this when defining product events, measuring feature adoption, changing analytics providers, or reviewing analytics privacy.

## Goal

Use analytics to answer a small set of product questions:

- Do runners discover a feature?
- Do they configure it and start an activity with it?
- Does it work through activity save?
- Do they use it again?
- Which combinations make activity starts, saves, and retention more likely?

Measure decisions and outcomes, not every tap. An event must support a product decision, funnel, reliability check, or privacy obligation.

## Current State

The app already has a provider-neutral foundation in `Core/Analytics`:

- `AnalyticsService` defines initialization, event, identity, property, and screen operations.
- `AnalyticsManager` fans operations out to one or more providers.
- `FirebaseAnalyticsProvider` and `NoOpAnalyticsProvider` are the only adapters.
- Firebase Analytics is linked through Swift Package Manager and is selected when Firebase configuration is available.
- `ProductAnalyticsEvent.swift` defines the canonical event names, property keys, scalar values, privacy allowlist, and coarse buckets.
- `AnalyticsManager` validates events, adds shared app/OS/language/authentication context, and fans the same canonical event out to every configured provider.
- Authentication identity is synchronized at the app root with the opaque Plainstride account ID and cleared when the authenticated user disappears. On both iOS and Android, Firebase collection is disabled before authentication and enabled only after that account ID is set, so anonymous app-open/session activity does not inflate registered-user dashboards. Android also drops events at the provider-neutral facade until a nonblank account ID is installed.
- Authentication recovery emits `authentication_session_recovered` with only a bounded recovery reason so rotation races and preserved transient failures can be monitored without sending credentials, account details, or raw errors.
- Legal surfaces emit `legal_document_opened` with only the document type and bounded entry source. Material Terms reacceptance emits presentation and completion events with the public integer Terms version and success/failure; it never sends document text, URLs, acceptance timestamps, account details, or errors. The backend account row, not analytics, is the acceptance record.
- The activity flow emits setup exposure, configuration, start/pause/resume/finish/save, discard-prompt, confirmed-discard, goal-threshold, live-workout-panel display changes, music, route-selection, shoe-selection, photo, and group-run events. Completed-activity photo viewing uses `photo_previewed` with only the opening surface and `photo_zoomed` with only the activity-detail surface plus the coarse `pinch` or `double_tap` control; neither event includes photo, activity, route, or location identifiers. `live_workout_panel_display_changed` contains only `expanded` or `collapsed` plus the originating `camera` or `map` surface; it excludes metrics, workout facts, route data, coaching text, and interaction duration. The discard events contain only coarse duration, distance, photo-count, and goal-completion buckets; they never include activity identifiers or exact workout facts. Interrupted-session UI recovery emits `activity_recovery_presentation` with only the direct-render result, a bounded recovery source (`recording`, `awaiting_save`, or Debug-only `run_simulation`), and a coarse render-attempt bucket; Debug local test-group recovery also emits `feature_exposed` with only `feature = test_group_recovery`; photo recovery emits `activity_photo_recovery` with only a coarse count and whether the restored set included a pre-run photo. Both exclude image content, workout details, route data, coordinates, timestamps, and session identifiers. Interrupted-workout music recovery emits only success/failure plus the bounded recovery source (`already_playing`, `existing_queue`, `rebuilt_selection`, or `unavailable`), never playlist or track metadata.
- Android activity media uses one account-scoped repository across Feed, Social detail, Group moments, and Recents. A successful disk-cache fill emits existing `feature_exposed` with only `feature=activity_photo_cached`; cache/local-file hits emit no fill event. No photo IDs, URLs, paths, image metadata, or account identifiers are included.
- Activity sync emits `activity_sync_completed` or `activity_sync_failed` with only a bounded source type, whether a route was selected, and a normalized error category. Photo transfer uses the same events and never adds image content, photo metadata, activity identifiers, or coordinates to analytics.
- Walk selection and Run/Walk start emit `motion_authorization_requested` only when iOS authorization is undetermined, followed by `motion_authorization_completed` with a bounded result. These events exclude step count, motion samples, activity identifiers, and timestamps.
- Active outdoor recordings emit `activity_location_permission_changed` only when permission availability changes, with `result = unavailable` or `restored`. Coordinates, sensor values, activity identifiers, timestamps, and authorization history are excluded. Save and background elevation enrichment retain their existing completion events; local save does not wait for network enrichment.
- Activity finish also emits one `activity_recording_quality` event with only coarse accepted-point count, filter-ratio, segment-count, and final-distance-correction buckets; bounded delivery, final signal-quality, full/reduced precision, and route-match outcomes; and booleans indicating whether motion bridged a GPS gap and whether a walking step count was available (`walking_steps_available`) and whether running cadence was available (`running_cadence_available`). It never includes coordinates, timestamps, exact counts or distances, accuracy radii, route identifiers, or route geometry.
- Apple Watch live workouts emit bounded feature exposure, connection attempt/result, origin, first-live-heart-rate, disconnect/reconnect, control, save-result, and phone-only-fallback events. Properties are limited to device/source, control, success/fallback, and normalized error categories. Session/workout UUIDs, exact timestamps, heart-rate values or samples, route geometry, HealthKit metadata, and device identifiers are excluded.
- Outdoor post-run terrain reconciliation on iOS and Android uses bounded sources `mapzen_terrain_v2` (new save), `mapzen_upgrade_v2` (v1 refresh), and the existing backfill/fallback sources. It emits `activity_elevation_correction_completed` with only success/fallback, the bounded correction source, a coarse latency bucket, and a normalized error category on fallback. It never includes coordinates, exact elevation or gain, route geometry, activity identifiers, provider URLs, or timestamps.
- The DEBUG-only interactive run simulator emits `activity_simulation_started` with only a fixture label, coarse route-distance bucket, and coarse speed bucket. Its explicit clock/speed controls emit `activity_simulation_control_used` with bounded control and selection values. Neither event includes route geometry, coordinates, exact speed, exact elapsed time, or generated coaching content; exclude these debug sessions from production activity-funnel dashboards.
- Live Activity recovery emits `live_activity_reconciled` only when ActivityKit already owns a card, with a bounded result of `restored`, `duplicates_removed`, or `stale_replaced`; it never includes session identifiers, workout details, timestamps, or activity counts.
- Home Screen widget setup emits `home_widget_onboarding_viewed`, `home_widget_setup_action_selected`, `home_widget_setup_step_viewed`, and `home_widget_setup_guide_completed`; a later launch with the widget installed emits `home_widget_already_present`. Entry source is bounded to `after_workouts`, `settings`, or `debug`; step, selection, and result are also bounded. Widget payload content, workout details, and identifiers are never sent to analytics.
- Confirmed history deletion emits `activity_deleted` with only the history source and a coarse deleted-count bucket; it never includes activity identifiers or details.
- Expanding the split table emits `activity_splits_viewed` with only the bounded detail source and a coarse split-count bucket; it never includes pace, time, elevation, route data, or activity identifiers.
- Live Guidance emits bounded semantic moment, spoken-cue, evaluated-outcome, challenge-selection, and post-run-feedback events. Semantic values include the current pace-band, break, terrain, recovery, progress, segment, finish, and challenge families documented in `docs/live-coaching-moments.md`. It never sends generated coaching text or exact pace, grade, elevation, heart rate, distance, time, or sensor samples.
- Both clients emit `live_location_stream_started` once at the first group location publication per connection, with only `source_type = group_run` and `selection_type = one_second_gps` (or Debug `one_second_simulated`). GPS coordinates, measurement timestamps, exact accuracy, participant/session IDs, and per-fix events are excluded.
- `live_cheer_follower_opened` records the entry source and whether the follower initially saw `current_pace` or `average_pace`; it never records exact live metrics or location.
- Live Guidance speech-route experiments also emit only coarse provider source (`remote` or `local`) and result (`success` or `fallback`); provider/model/voice IDs, exact transcripts, prompts, and audio are excluded.
- Android independent notification and live Group-run loaders emit `notification_detail_loaded` and `group_run_detail_loaded`; leaving the viewed session emits `group_run_leave_result`, all with only `result=success|failure`; no entity IDs, content, participants, or location.
- Push tap routing emits `push_notification_opened` with only the share-safe notification type and coarse destination; it never sends notification, actor, connection, activity, or device identifiers.
- The iOS and Android notification permission flows emit `push_notification_prompt_exposed` and `push_notification_prompt_action_selected` with bounded entry sources (`authenticated_entry`, `social`, `settings`) and selections (`enable`, `not_now`), plus `push_notification_permission_completed` with only `permission = notifications` and a `granted` or `denied` result. They never include device or notification identifiers.
- Opening the in-app Social inbox from a primary screen emits `social_inbox_opened` with only `entry_source = social`, `today`, or `me`; notification content, actors, and identifiers are excluded.
- Product events currently flow to Firebase when configured and to the no-op diagnostic provider otherwise. The no-op provider logs only event names and parameter counts, never payload values.
- Subscription surfaces emit `subscription_paywall_opened` or `subscription_customer_center_opened` with only a bounded entry source such as `settings` or `live_guidance`. Purchase, restore, and Customer Center dismissal emit `subscription_reconciled` with only a bounded source and success/failure. Product identifiers, prices, receipts, transaction IDs, RevenueCat customer data, and entitlement dates never enter product analytics.
- Sharing a personal invitation emits `referral_code_shared` with the bounded surface and policy classification `founding` or `reward_eligible`. It never includes the invitation code, URL, reward balance, referral counts, or entitlement dates.
- Copying a personal invitation code emits `referral_code_copied` with the same bounded surface and policy classification. It never includes the code or URL.
- Startup routing emits `app_startup_resolved` once per process launch with the resolved destination (`authentication`, `onboarding`, or `main`), a coarse latency bucket, and a bounded source (`auth_state`, `local_cache`, `auth_session`, `session_refresh`, `fail_open_timeout`, or `fail_open_unavailable`). It excludes account identifiers, onboarding answers, session details, and exact timing.
- Feedback submission emits `feedback_report_submitted` with success/failure plus one bounded log state: `logs_excluded`, `logs_empty`, `logs_unavailable`, or `logs_attached`. It never sends the report text, screenshot, log contents, current page, or the number or categories of captured lines to analytics.
- Public Android waitlist submissions emit the server-side `android_waitlist_submitted` event with only schema version, source (`marketing_home`), and a bounded result (`accepted`, `invalid`, `spam_rejected`, or `failed`). The email address is stored only in the dedicated waitlist record and is never written to analytics or application logs.
- AI provider reliability emits server-only `ai_attempt` and `ai_generation` operational events under `docs/ai-reliability.md`. Provider/model IDs, exact latency, and closed validation reasons (`unsafe_pain`, `medical`, `guarantee`, `vague_form`, `abrupt_pace`, and existing schema/coverage/bounds reasons) remain in operational logs; no prompts, responses, user content, or runner identifiers enter either log or product analytics.
- The rewards administrator portal emits server-side operational events only after administrator verification. Values are limited to portal load, bounded section view or search, and a bounded mutation operation—including paywall-control updates—with success/failure. These logs never contain administrator or target identities, emails, code material, code labels, grant references, reasons, expiration values, search queries, timestamps as custom fields, or raw errors. The transactional reward audit remains the authoritative mutation record.
- Opening the consolidated Me profile editor emits `feature_exposed` with the bounded feature value `me_profile_editor`; profile fields, training details, and companion memory are never included.
- Android fixed voice preparation emits `voice_audio_preparation` and voice-enabled starts emit `voice_audio_start`, with only `result = ready | incomplete`. Bundled countdown playback uses `activity_voice_enqueue` with the bounded countdown cue category, `source_type = bundled_audio`, and success/failure. No spoken text, metrics, pack URLs, checksums, identities, or exact progress counts enter analytics.
- Android Today’s adaptive location warmup emits `feature_exposed` with `feature = adaptive_start_location_warmup` and only `result = accurate`, `usable`, or `unavailable`, once after the first warmup attempt per visible/resumed visit. It excludes coordinates, exact accuracy, timestamps, and location samples.
- Showing the post-save activity postcard emits `feature_exposed` with the bounded feature value `activity_post_save_celebration`. Stretch offer, start, program-selection, completion, and dismissal events include only bounded activity type, stable routine ID, and (for dismissal) a bounded result. Route geometry, activity identifiers, exact metrics, and celebration copy are excluded.
- Opening a Me destination emits `me_destination_opened` with only a bounded destination (including `connection_profile` for a connection avatar) and `entry_source=me`; invitation and reward codes are never included.
- Importing a Strava export emits `strava_import_prompt_viewed` when the wizard opens and `strava_import_completed` when the runner confirms an import, with only `source_type = strava_export`, a bounded result (`completed`, `partial`, or `failed`), whether the selection was all or a subset, the bounded selection control, and a coarse activity-count bucket. Neither event includes activity names, identifiers, route data, dates, coordinates, file names, or export contents. See `docs/strava-import.md`.
- Showing a reliable completed-workout calorie estimate emits `feature_exposed` with the bounded feature value `completed_workout_calories`. The event never includes the calculated value, weight, workout type, distance, duration, speed, activity identifier, or the reason an estimate was hidden.
- The optional onboarding training-profile screen emits only viewed and completed events. Completion records a bounded result and whether the runner used manual entry or Apple Health; it never records which fields were supplied or any age, body measurement, or sex value.
- Showing Social's accepted-connection preview emits `feature_exposed` with the bounded feature value `social_connections_section`; opening its full list emits `connections_opened` with `entry_source = social_home_preview`, while its add action uses `social_home_add`. Me uses `me_preview` and `me_add` for the matching actions. Neither event includes connection identities, presence, names, or counts.
- Group membership controls use `group_membership_policy_changed` with bounded `source_type=open|request|invite_only` (`invite_only` applies to private Groups), `selection_type=approval_required|direct`, `change_type=member_invites_on|member_invites_off`, and `result=success|failure`; review uses `group_membership_request_reviewed` with `source_type=approve|deny` and result. `group_membership_request_submitted` distinguishes `self_join` and `member_invitation` without counting pending people as active members.
- Weekly-theme saves on Android mirror iOS `group_theme_changed` with `selection_type=curated|custom` and `source_type=now|next_week`. Personal commitments use `group_target_changed` with `selection_type=target|cleared`, a coarse `target_bucket`, and `source_type=now`. Android also records `result=success|failure` per mutation, including partial-save failures; theme keys, custom text, Group/person IDs, and exact targets are excluded.
- Weekly creation emits `activity_event_recurrence_configured` with `selection_type=weekly` and `source_type=group_activity`. Series edit/cancel uses `activity_event_series_changed` with `selection_type=this|following|series` and result. No series/Group/event/request/person IDs, invitation tokens, names, weekday/date/time values, time zones, meetup details, or user-entered content are collected. Both platforms retain existing invitation, RSVP, and activity lifecycle events.
- Group invitation previews on iOS and Android emit `feature_exposed` with only `feature = group_invitation_preview`. Accept/Decline reuse `group_invitation_accepted` / `group_invitation_declined` with `entry_source = group_invitation_preview`; acceptance adds only a coarse member-count bucket. Failed decisions emit `group_operation_failed` with `source_type = group_invitation_preview` and `error_category = api_unavailable`. Group, invitation, and person identifiers and all preview content are excluded. See `docs/run-groups.md`.
- Social operation failures presented by the home surface emit `social_operation_failed` with only the bounded source and error category. Raw HTTP status text, response bodies, request paths, and user or social identifiers are excluded.
- Account milestone reconciliation emits `recognition_sync_completed` with only a bounded source type and coarse award-count bucket, or `recognition_sync_failed` with a bounded source type and normalized error category. A newly earned local milestone emits `recognition_awarded` with only its source and a coarse count bucket. These events never include badge IDs, activity IDs, distances, earn dates, profile IDs, or raw server errors.
- Account configuration sync reuses `preference_changed` with `change_type = account_configuration_sync` and `selection_type = saved | conflict | failed`. Exclude account/configuration IDs, exact targets and routine contents. See `account-preferences.md` for the sync contract.
- Explicit unit changes emit `preference_changed` with only the bounded preference kind (`measurement_unit_system` or `temperature_unit`) and semantic choice. The event excludes locale identifiers, gear/music details, and the preference snapshot.
- Run-goal profile changes reuse `preference_changed` with bounded kinds (`primary_motivation` or `run_goal_type`) and enum selections only. One-off goal changes reuse `activity_configuration_changed` with bounded `activity_type`, coarse target buckets, and bounded source (`manual` or `planned_override`); committing an entered custom target additionally sets `selection_type = custom`. Race-plan selection may include only the bounded pacing strategy (`even`, `negative_split`, or `effort_based`). These events never include weight, exact distance, exact duration, exact calories, free-form motivation, workout IDs, learned pace, elevation, or estimated distance/duration.
- Search and text-form keyboard submissions emit `input_submitted` with only a bounded `source_type` surface: `onboarding`, `profile`, `shoes`, `rewards`, `comments`, `routes`, `groups`, `people`, `activity_entry`, `activity_edit`, `activity_event`, or `route_publish`. This observes Return-key submissions without changing multiline editing or replacing domain search/send/save events. Field identifiers, labels, values, and queries are excluded; ordinary typing, numeric-field dismissal, focus changes, and system dismissal are not tracked.
- Music-sheet explicit keyboard dismissal emits `activity_configuration_changed` with `change_type = music_keyboard` and `selection_type` limited to `search_icon` or `keyboard_search`; native system scroll dismissal is not instrumented. Search text and music metadata are excluded.
- Discovery tooltips emit privacy-safe `feature_exposed` events with bounded feature names. Music outside-tap dismissal continues to use `activity_configuration_changed` with `change_type = music_discovery_tip` and `selection_type = dismissed`; no tooltip copy or surrounding UI text is collected.
- Planning navigation emits `planning_surface_opened` with only a bounded surface (`race`, `curated_workouts`, `planned_workout_details`, `workout_change`, `plan_details`, or `plan_picker`) and entry source (`manual_mode_row`, `today_planned_card`, `today_planned_card_plan`, `today_planned_card_change`, `me_current_focus`, `plan_details_change`, or `recommendation_more_plans`). Plan Details also includes the coarse `count_bucket` for workouts displayed in the current plan week, which can detect incomplete schedule rendering without exposing workout content. Ending the active plan emits `training_plan_ended` with only `entry_source = plan_details`. Choosing a curated workout additionally emits `activity_configuration_changed` with `change_type = curated_workout` and only the selected sport as `selection_type`. These events exclude workout and plan IDs, titles, details, recommendations, and runner data.
- Ad-hoc race planning on iOS and Android emits `activity_configuration_changed` with `change_type=race_plan`, `goal_type=race`, bounded `source_type` (`training_history`, `insufficient_history`, `manual`), `pacing_strategy` (`negative_split`, `even`, `effort_based`), and coarse `target_bucket`. Race opening uses `planning_surface_opened` with `source_type=race` and `entry_source=manual_mode_row`. Exact time, pace, distance, and history are excluded.
- iOS and Android opening the End plan confirmation emits `feature_exposed` with only `feature=plan_end_confirmation`. Cancelling emits no `training_plan_ended`; that event remains tied to the confirmed clear-plan action. Actual-week count fixes retain the existing coarse Plan Details `count_bucket`, with no durations or history added to analytics. Android reports `training_plan_ended` only after successful server clearing; failure emits `feature_exposed` with only `feature=plan_end_failed` and leaves retry available.
- Android's card title, Details/Plan actions and Plan dock button emit `planning_surface_opened`: `source_type=plan_details` for active plans or unresolved syncing, and `source_type=daily_recommendation_details` for daily recommendation details. Entry sources remain `today_planned_card`, `today_planned_card_plan`, or `manual_mode_row`. Daily details omit the weekly workout `count_bucket`; no titles, workout steps, plan identities or cache payloads enter analytics. Change workout retains its existing event, and training-plan setup remains an explicit action when a daily recommendation is present.
- Canonical reminder resolution uses bounded `feature_exposed` feature `workout_reminder_resolution` and result `resolved|unavailable`; rejecting a local goal change on an audited edit uses `edited_workout_goal_guard` / `rejected`. Neither includes workout IDs, targets or reminder content.
- Today Change Apply and unsolicited proposal decisions use `today_adjustment_selected` / `today_adjustment_decided`, with `source_type=workout_change`. Android retains bounded reason results (`tired`, `sore`, `short_on_time`). iOS direct editing records failed Apply-time baseline refreshes with the same coarse failed decision (no draft content); local drafting without capabilities adds no event. iOS direct editing records only operation `edit|replace|skip`; optional private reasons and exact fields/targets are excluded. Decisions record `accepted` or `kept_original`, and iOS reports `saved` only after consuming the canonical Apply response or `failed` on save/refresh failure. Apply never emits a workout-start event. Notes, exact minute targets, catalog/request/proposal/workout IDs, readiness records and generated copy are excluded.

- Choosing a reviewed plan recommendation emits `training_plan_recommendation_selected` with only success/failure and whether it starts a plan or replaces the current one. It excludes recommendation/template IDs, plan names, details, and runner data.
- The target onboarding/plan-builder redesign adds typed `onboarding_resolved`, `plan_builder_opened`, `plan_builder_exited`, and `plan_creation_completed` events. Properties are limited to skipped/completed result, bounded entry source or step, success/failure, and a coarse latency bucket. Objective and activity categories may use bounded enum values; free text, body details, event dates, constraints, workout content, and identifiers remain excluded. See `docs/new-user-onboarding.md`.
- iOS context recovery reuses `plan_intake_context_loaded` with bounded `source_type=refresh`, `result=success|failure`, and normalized `error_category` on failure. Plan creation uses bounded `error_category=planning_context_changed` for a stale review. Long-run day edits reuse `plan_intake_answer_edited` with `selection_type=long_run_days`; no chosen weekday, count, exact duration, body field, evidence contents or context token is sent to analytics.
- On iOS, `plan_builder_exited` also distinguishes `result=completed` (`Go to Today`) from `result=finish_later`, with the bounded setup entry source and step. This measures completion of the setup-to-Today handoff separately from successful plan creation; no plan or workout identifiers are included.
- Opening the optional Social event meetup-location picker emits `feature_exposed` with the bounded feature value `activity_event_location_picker`. Choosing a meetup place emits `activity_event_location_selected` with `source_type` limited to `autocomplete` (place-suggestion selection) or `map` (map-pin confirmation). Both events explicitly exclude the search query, place names, addresses, coordinates, and any other location detail. The event record may persist the resolved display label and exact meetup coordinate pair for participants, but those coordinates never enter analytics.
- Minimizing or expanding the planned-workout card emits `today_card_display_changed` with the bounded card type `planned_workout` and display state (`minimized` or `expanded`). Group visibility on Today reuses `groups_section_exposed` with `entry_source = today`; neither event includes workout, plan, Group, or member identifiers.
- The assistant launcher retains `assistant_launcher_eligible_exposure`, `assistant_launcher_opened`, and `assistant_meaningful_engagement`; the former recurring `assistant_launcher_animation_shown` loop is retired. Meaningful engagement means selecting a suggestion or sending a message. Events contain only the current bounded destination and entry source, never prompts, assistant responses, workout details, or other personal activity data.
- Fox presence emits `feature_exposed` with `feature=fox_companion_presence` and `result=idle|delivery|celebration`. Idle exposure is bounded per foreground visit rather than emitted on every gesture. `fox_companion_action_selected` uses only `selection_type=notification_preview|notification_dismissed|envelope_opened`. Existing notification action events retain their normal routing contract; no notification IDs, actor names, message text, timestamps, or activity details are added.
- Android `primary_tab_selected` records the bounded `destination` (`social`, `today`, or `me`) only when the shell selection changes, including programmatic handoffs. Repeated selection does not emit another event.
- Android assistant destination actions emit `assistant_destination_opened` with only the bounded destination route and `entry_source=assistant`; repeated outgoing taps are ignored. No message content is recorded.
- Assistant language interpretation emits `assistant_interpretation_completed` with only bounded provider (`source_type`: `apple`, `server`, `none`), outcome (`result`: `success`, `unavailable`, `invalid_input`, `invalid_output`, `cancelled`), and coarse `latency_bucket` (`under_250ms`, `250ms_1s`, `1s_3s`, `3s_8s`, `8s_plus`). Timing uses a monotonic clock around interpretation, excludes analytics delivery, and never records exact duration. It excludes prompts, model output, extracted workout fields, and selected destinations.
- Today shoe-picker actions emit `shoe_selected` with only the bounded selection type `active_shoe` or `add_new`; shoe names and identifiers are never included.

The legacy provider methods still accept vendor-facing string names after the manager boundary, but product surfaces emit typed events and values. New product instrumentation must use the typed contract rather than arbitrary event strings or `[String: Any]` dictionaries.

- Automatic iOS cadence beats emit `live_guidance_pacer_playback` with only bounded `result` (`started`, `completed`, `interrupted`, `failed`, `introduction_started`, `introduction_completed`, `introduction_interrupted`, `introduction_failed`, `introduction_unavailable`, `handoff_skipped`, `paused_for_speech`, `resumed`, `resume_skipped`). Introduction results distinguish the explanatory speech from the subsequent beat; `introduction_started` occurs at most once per run after playback starts, including when that introduction is later interrupted; `handoff_skipped` records a handoff that could not start with current eligibility. `paused_for_speech` and `resumed` record a drum yielding to an announcement and continuing its remaining audio; `resume_skipped` records cancellation when current eligibility no longer permits continuation. No new attempt or introduction is counted for a resume. The technical reason stays in device logs. Cadence readings, exact timing, workout content, transcripts, and identifiers remain excluded. See `docs/live-coaching-moments.md` for signal gates and playback scope.

- Scheduled execution instructions emit `live_guidance_execution_coaching` with only `result = scheduled`, `spoken`, or `audio_unavailable`. Instruction IDs, text, cadence, exact metrics, and timestamps are excluded.

## Measurement Model

### Post-Workout Stretch Contract

Both clients emit `post_workout_stretch_offered`, `post_workout_stretch_started`, `post_workout_stretch_completed`, and `post_workout_stretch_dismissed` with only canonical activity type, bounded routine ID, and bounded dismissal result.

The run templates add bounded routine IDs `pre_run_v1`, `post_run_1_v1`, `post_run_2_v1`, and `post_run_3_v1` under the existing sport/standalone prefixes. Existing offer, selection, start, step, completion and dismissal events cover them. `held` and `fully_held` mean completed timed intervals; dynamic intervals do not assert a static hold or detected exercise. No artwork, instruction text or inferred movement performance is emitted.

### Core Activity Funnel

Track:

1. activity setup viewed;
2. configuration changed;
3. activity started;
4. paused, resumed, or finished;
5. saved, or shown the discard warning and then explicitly discarded.

`activity_started` should carry bounded configuration rather than separate events for every selected setup control:

- `entry_source`: quick start, Today workout, Me suggestion, route, group invitation;
- `activity_type`: running, walking, cycling, hiking, or swimming;
- `goal_type`: freestyle, distance, time, calories, workout;
- `target_bucket`: coarse distance, duration, or calorie range; never the exact target;
- `music_enabled`;
- `route_selected`;
- `shoe_selected`;
- `pre_run_photo_added`;
- `group_run_enabled`;
- `live_share_enabled`;
- `indoor`;
- `voice_guide_enabled`;
- `ai_coach_enabled` (iOS and Android; false for non-running Android activities).
- `auto_pause_enabled`.
- `auto_stop_at_goal`: whether a manual distance, time, or calorie goal is set to pause recording when reached.

iOS and Android AI Coach changes reuse `activity_configuration_changed` with `change_type=ai_coach` and `selection_type=enabled|disabled`; live changes include `source_type=live_workout` and canonical activity type. Voice keeps the existing `voice_guide` analytics identity. No speech or coaching content is collected. Onscreen-only Android delivery advances local cue history without emitting speech events or increasing the spoken-cue count.

Auto Pause setup changes use `activity_configuration_changed` with `change_type=auto_pause`, the enabled/disabled selection, and canonical activity type. The preference value is also captured on `activity_started`.
Goal pause changes use `activity_configuration_changed` with `change_type=auto_stop_at_goal`, the enabled/disabled selection, and canonical activity type. The effective session value is also captured on `activity_started`. Do not include exact goal values in these events.
Live dashboard changes reuse these events with `source_type=live_workout`, `change_type=voice_guide|ai_coach|auto_pause|auto_stop_at_goal`, enabled/disabled selection, and activity type. Voice, auto-pause, and goal-pause changes apply only to the current session; AI Coach also updates its device-local launch preference. Recipient changes reuse `live_cheer_invitation_configured` with coarse participant counts.

`activity_saved` may add coarse duration, distance, goal-completion, and photo-count buckets. Keep exact activity facts in the activity record, not general product analytics.

Activity cancellation records `activity_event_cancellation_result` with bounded `entry_source`, `group_run_enabled`, and `result` (`success` or `failure`). Never include event IDs, titles, dates, invitee identities, or cancellation text.

### Feature Funnels

| Feature | Recommended sequence |
| --- | --- |
| Music | setup exposed -> authorization requested/result -> quick pick selected -> playback started -> control used or playback failed -> activity saved with music |
| Routes | owner Save Route exposed -> publish started -> publish completed/failed -> optional publication removal; library exposed -> searched/imported -> bookmark saved/removed -> route selected -> route displayed -> Route Guidance started -> 25/50/75/100% progress -> wrong-way or deviation/rejoin when applicable -> arrival/recovery when applicable -> activity saved with route outcome |
| Distance/time goals | goal control exposed -> type/preset/custom selected -> activity started -> progress bucket reached -> activity saved |
| Shoes | gear entry exposed -> shoe added/defaulted -> shoe selected -> activity saved with shoe -> retirement reminder acted on |
| Photos | capture entry exposed -> capture attempted/succeeded (including whether a coordinate was attached, never the coordinate itself) -> retained or deleted -> activity saved with photo -> explicitly shared |
| Photo album export | default-on preference changed -> automatic export completed with success, permission denial, or failure; record only a coarse photo-count bucket |
| Group runs | group control exposed -> create/join attempted -> invitation shared/opened -> joined -> activity started -> activity saved |
| Groups | Groups exposure -> template selection -> creation -> invitation/request -> acceptance -> active Group -> capability use -> activity participation -> following-week contribution |
| Live Guidance | coaching level selected -> semantic moment detected -> cue spoken -> cue outcome evaluated -> optional challenge completed -> post-run feedback submitted |
| Assistant launcher | eligible exposure -> animation shown -> launcher opened -> suggestion selected or message sent |
| Apple Watch live workout | setup exposed -> connection attempted/result -> origin resolved -> first live heart rate -> controls or disconnect/reconnect -> Watch save result or phone-only fallback |
| Progress | surface opened -> bounded tab/range/metric/sport control changed -> insight set exposed |

Groups use the typed `group_*` events defined in `ProductAnalyticsEvent.swift` for exposure; template exposure/selection; creation; invitation and request outcomes; activation; capability and setting changes; progress; member-list opening; discovery searches; Cheers; activity planning and RSVP; notices; membership, mute, member, ownership, archive, report, and block outcomes; and normalized failures. The allowlist accepts only entry/source/result categories, template/policy selections, and coarse participant/target/count buckets. IDs, names, activity facts, locations, free text, notification text, member identities, search queries, and exact counts are rejected from this event family.

Exposure matters: a missing action means something only when the runner actually saw the relevant control. Use explicit exposure events for optional features and compare exposed users with adopters.

Progress uses `progress_surface_opened`, `progress_control_changed`, and `progress_insights_exposed`. Allowed values are limited to entry source, coarse activity/insight count buckets, bounded control selections, and the top semantic insight category. Exact activity totals, pace, heart rate, load, goal completion, time-of-day evidence, activity identifiers, and rendered explanation copy are excluded.

Avoid continuous progress telemetry. Emit at most one event for each meaningful activity goal threshold, such as 25, 50, 75, and 100 percent.

Route Guidance follows the same bounded rule. Its events may contain source (`community` or `imported`), intended direction, coarse progress percent, coarse distance bucket, and a semantic outcome. They must never contain raw route ID, route name, geometry, coordinates, or exact remaining distance. Recovery suppresses already-fired progress, deviation, wrong-way, and arrival events.

`live_guidance_moment_suppressed` reports only a bounded `result`: `unreliable_pace`, `measurement_gap`, `no_actionable_target`, or `repeat_correction`. Each reason is emitted at most once per session on each client; no GPS timestamps, measurements, or text are included.

Live Guidance uses semantic values such as moment type (including periodic `progress`), coaching contract, outcome, and a coarse cue-count bucket. `live_guidance_voice_selected` records only the product voice style and whether the change came from settings or preview; it excludes the provider voice ID. `live_guidance_provider_result` permits only typed product values: `source_type` (`dynamic_generation`, `planned_cache`, `fixed_pack`, `cached_fallback`), bounded result category, effective `audio_mode`, bounded `access_reason`, and a coarse latency bucket. `live_guidance_audio_first_byte` records only source type plus `under_1s`, `1s_2s`, `2s_4s`, or `4s_plus`, measured from the device request start to the first PCM frame. `live_guidance_audio_playback_route` records only `cloud_stream` or `recorded_audio`; the app no longer uses system-synthesized speech. `live_guidance_fixed_audio_unavailable` records only a bounded cue group (`start_countdown` or `segment_countdown`) and `audio_unavailable` or `late_start`, making an intentionally silent fixed cue observable without recording its text or voice identity. For the founding-access policy, `promotion` means a durable founding grant, `open_beta` means one of a later account's three trial runs, and `entitlement_required` means the trial is exhausted; do not add account ordinal or exact remaining-run count. None of these events includes provider/model/voice IDs, request/session IDs, guidance-plan status, generated speech, prompts, audio, snapshot history, exact pace, distance, elapsed time, location, weather, survey, or profile data. Evaluated outcomes update only local aggregate evidence used to reduce repeatedly unhelpful Responsive cues.

### Questions And Dashboards

- Weekly active runners and saved activities.
- Start-to-save conversion, discard-prompt stage, and confirmed discard stage.
- First-activity completion and 7-day/30-day retention.
- Feature discovery, adoption, successful use, and repeat use.
- Permission denial and operational failure rate by feature.
- Goal completion by goal type and coarse target bucket.
- Feature combinations used at activity start and their relationship to save and repeat-run rates.
- Group-run create/join conversion and participant-count buckets.
- Group invitation acceptance, activation, weekly contribution, focus completion, support actions, continuity, and their relationship to D7/D28 saved-activity retention. Follow the privacy contract in `docs/run-groups.md` and do not treat observational correlation as causation.

Do not treat correlation between a feature and retention as proof that the feature caused retention.

## Event Contract

### Canonical Types

Product code should emit a typed, provider-independent value:

```swift
struct ProductAnalyticsEvent: Sendable {
    let name: ProductEventName
    let schemaVersion: Int
    let properties: [ProductPropertyKey: AnalyticsValue]
}

enum AnalyticsValue: Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
}
```

The exact Swift shape may differ during implementation, but preserve these rules:

- Event names, keys, and enumerated values are centrally defined.
- Values are scalar and explicitly supported; no `Any`, nested objects, dates, URLs, or model serialization.
- Each event has an owner, purpose, trigger, required properties, optional properties, and schema version in one event catalog.
- Feature code emits domain meaning such as `music_playback_started`; it never imports or names Firebase, PostHog, Amplitude, or Mixpanel.
- Provider adapters perform the final naming, length, and capability mapping.

### Shared Context

The manager may add a small, centrally controlled context to every event:

- app version and build;
- operating-system major version;
- locale language;
- measurement system;
- authenticated or anonymous state;
- analytics schema version.

Do not let each feature assemble these properties. Avoid device fingerprinting, exact timestamps as custom properties, and user properties that merely duplicate event facts.

### Identity

- Use a stable opaque Plainstride account identifier after authentication, never email, display name, provider subject, or contact data.
- Reset provider identity on logout.
- Do not collect pre-login activity for registered-user reporting. If anonymous measurement or anonymous-to-known merging is later needed, define its semantics in the manager and test every adapter.
- Treat user properties as a small governed allowlist, not an alternate user database.

## Privacy And Governance

Never send:

- GPS coordinates, route geometry, precise start/end locations, or route names from product analytics; event meetup coordinates are operational event data and must not be sent as analytics properties;
- photo contents, filenames, captions, or metadata;
- playlist, album, artist, track, or shoe names and notes;
- contact, group, participant, or invitation identifiers;
- free text, assistant prompts, reflection text, or error messages that may contain user data;
- raw health, reproductive-health, cycle, symptom, readiness, or private adjustment data.

Use coarse buckets for distance, duration, participant count, photo count, goal progress, and error category. Maintain an allowlist sanitizer and reject unknown keys in development. Production should drop invalid properties and record only a local diagnostic.

Before release, decide and document:

- whether collection is opt-in or opt-out and where the control lives;
- what is collected before authentication;
- retention period and regional storage;
- deletion behavior after account deletion;
- App Store privacy disclosures;
- who can access raw events and dashboards.

Do not enable session replay, autocaptured UI text, or automatic interaction tracking by default. A fitness app has too many sensitive surfaces for indiscriminate capture.

## Framework Evaluation

Evaluated against official vendor documentation on 2026-08-21. Pricing and plan limits change frequently and must be rechecked before procurement.

Identity completion during onboarding emits `onboarding_identity_prompt_viewed` and `onboarding_identity_completed`. Both include only boolean `missing_display_name` and `missing_email` properties; names, usernames, and email addresses are never included.

`activity_feed_loaded` includes `timestamp_source` (`activity_start`, `post_created_fallback`, `mixed`, or `empty`) so rollout of exact activity-time display can be monitored without sending activity dates or other personal data.

`activity_feed_returned` records an iOS return from activity detail with only `source_type = activity_detail`, the coarse loaded-post count bucket, and page-depth bucket. It measures return usage at different feed depths; it does not claim that restoration succeeded or include post IDs, titles, offsets, or activity data.

`paginated_list_page_loaded` records additional-page loads for `activity_history`, `activity_feed`, and `connections`. It includes only the list source, a coarse count bucket for newly revealed rows, and a coarse page-depth bucket; activity history also includes success/failure in `result`, so failed retries are observable; activity facts, connection identities, cursors, and exact totals are excluded. Profile history uses `source_type=friend_profile` for first and subsequent successful page loads; detail opens use `activity_detail_opened` with the same source. Neither event includes a person ID.

`route_detail_opened` records independent Android route-detail loading with only `source_type` (`community` or `imported`) and `result` (`success` or `failure`). Route IDs, names, geometry, and location are excluded.

`social_profile_opened` records only the source surface for profile navigation through the shared social-profile link. It excludes the runner's name, username, profile ID, and connection ID.

`connections_search_completed` measures successful and failed people searches with only the trigger (`autocomplete` or `submitted`), coarse input script (`han`, `latin`, `mixed`, or `other`), query-length bucket, result-count bucket, match mode (`none`, `literal`, `fuzzy`, `mixed`, `unknown`, or `unavailable`), and result. Match mode makes fuzzy-search usefulness measurable without identifying a search or result. The event never includes the query, matched names or usernames, profile IDs, or connection IDs.

| Provider | Strengths for Plainstride | Tradeoffs | Fit now |
| --- | --- | --- | --- |
| Firebase Analytics | Already linked; minimal implementation work; familiar iOS SDK; automatic baseline events; custom events; direct BigQuery export for SQL and long-term ownership | Console analysis is less product-focused than dedicated tools; custom parameters need console registration for standard reports; GA naming and reporting constraints can leak into a poorly designed taxonomy | Best initial provider |
| PostHog | Strong funnels, retention, paths, stickiness, lifecycle, SQL, flags, experiments, and optional replay in one product; iOS SDK queues offline events; cloud and self-hosting paths | Adding the SDK and a new data processor increases operational/privacy work; powerful autocapture and replay require strict disabling or masking; self-hosting is real infrastructure ownership | Best next provider to trial |
| Amplitude | Mature product analytics, cohorts, funnels, experimentation, and broad Swift support; current Swift SDK has a plugin architecture | More platform surface and governance overhead than needed for the first beta; experimentation/replay integrations increase coupling if called directly | Strong alternative for deeper product analysis |
| Mixpanel | Mature event analytics and funnels; maintained Swift SDK; explicit controls for opt-out, regional endpoint, IP geolocation, and automatic events | Another SDK and processor; provider-specific identity, profiles, timing, and flags should remain outside feature code | Strong alternative, especially for straightforward event analytics |

Relevant official documentation:

- [Firebase iOS event logging and event-type limits](https://firebase.google.com/docs/analytics/ios/events)
- [Firebase Analytics export to BigQuery](https://firebase.google.com/docs/projects/bigquery-export)
- [PostHog iOS SDK, identity, and offline queue](https://posthog.com/docs/libraries/ios)
- [PostHog product analytics capabilities](https://posthog.com/docs/product-analytics)
- [Amplitude SDK capabilities and Swift support](https://amplitude.com/docs/sdks)
- [Mixpanel Swift SDK configuration and privacy controls](https://docs.mixpanel.com/docs/tracking-methods/sdks/swift)

### Recommendation

Use Firebase Analytics for the first instrumentation pass because it is already present. Design dashboards around the canonical event catalog and enable BigQuery export when raw analysis becomes useful.

Trial PostHog only after the core events have real volume and Firebase demonstrably blocks a needed analysis, such as fast exploratory paths, behavioral cohorts, or integrated flags. Run both providers through `AnalyticsManager` for a time-boxed comparison using identical canonical events. Do not rewrite feature instrumentation for the trial.

## Provider-Neutral Architecture

Use four boundaries:

1. **Domain event catalog**: typed names, values, descriptions, and privacy classification.
2. **Analytics client/manager**: consent, identity, common context, validation, and fan-out.
3. **Provider adapter**: vendor SDK initialization and canonical-to-vendor mapping.
4. **Destination configuration**: selects zero, one, or multiple adapters without changing product features.

Keep vendor-only capabilities behind separate optional protocols, for example `AnalyticsFlushing`, rather than expanding the core contract until every feature depends on the richest provider. Feature flags, experiments, crash reporting, and session replay are separate products and should not be placed on `AnalyticsService` merely because one vendor bundles them.

Provider adapters should own:

- SDK imports and credentials;
- event/key sanitization and vendor limits;
- consent enable/disable calls;
- identity/reset semantics;
- offline/flush behavior;
- regional endpoints and IP/geolocation settings;
- translation of screen events if screens remain part of the canonical catalog.

The central manager should own:

- schema validation and privacy allowlists;
- shared context;
- sampling policy, if ever needed;
- dispatch to all configured providers;
- debug inspection with no production payload logging.

### Switching Or Comparing Providers

1. Add a new adapter that passes the same contract checks.
2. Dual-write a controlled percentage or internal cohort to old and new providers.
3. Compare event counts, identities, funnel conversion, latency, deletion, and consent behavior.
4. Resolve semantic differences in the adapter, not in feature code.
5. Stop registering the old adapter after the comparison window.
6. Remove its SDK and credentials only after its local queue is flushed or intentionally abandoned.

Historical dashboards do not migrate automatically just because the client adapter changes. BigQuery export or a first-party event pipeline is the stronger long-term portability layer if historical continuity becomes important.

## Delivery Sequence

1. Approve product questions, privacy policy, naming convention, and event catalog.
2. Replace free-form calls at the product boundary with typed canonical events and values.
3. Instrument the core setup-to-save funnel.
4. Add music, route, goal, shoe, photo, and group-run funnels.
5. Add development validation and a provider contract check without sending private payloads to logs.
6. Validate Firebase DebugView and initial dashboards with internal activity sessions.
7. Review data after two to four weeks; delete unused events before expanding.
8. Re-evaluate PostHog or another provider only against concrete unanswered questions.

`group_moment_opened` records iOS and Android recent-moment detail opens with only `entry_source=group_detail` and bounded `selection_type` (`cheer`, `completed_activity`, `weekly_completion`, or `other`). IDs, names, dates, and content are excluded.

`group_moment_results_loaded` records success/failure and, on success, a coarse participant count bucket. It excludes event/person IDs, names, outcomes, stats, and photos.

`group_activity_presence_viewed` records the first successful participant-panel load per mounted panel (setup or live recording), with only a coarse `participant_count_bucket`. It excludes event/person IDs, names, attendance modes, outcomes, and location.

iOS live runner/follower map presentation emits `feature_exposed` with only `feature=live_map_motion_smoothing` when mounted. It contains no coordinates, timestamps, speed, or participant identity.

Android `live_location_publish_result` records the first realtime publish acknowledgment/failure and subsequent success/failure transitions per channel connection. Only `source_type=live_share|group_run` and `result=success|failure` are sent; payloads, location, and identifiers are excluded. Enqueueing a message or starting a stream alone does not establish delivery.

`activity_event_rsvp_result` records join/leave success or failure with only bounded `entry_source`, `selection_type`, and `result`. On iOS and Android, `group_participant_location_unavailable` records a participant selection without an available location, and `group_participant_focused` records a successful map focus with only `source_type=participant_pill|group_card`; participant IDs, names, and coordinates are excluded.

Android planned-activity cancellation retains `activity_event_cancellation_result` with only bounded `entry_source`, `group_run_enabled`, and `result=success|failure`. Recurring cancellations also emit the existing `activity_event_series_changed` with `selection_type=this|following|series` and result. The result describes the server mutation independently of a subsequent Group refresh; IDs, titles, dates, and cancellation content are excluded.

`feature_exposed` with `feature=group_activity_recovery` records restoration of durable event context. It contains no event ID, participant names, or location. Live-map reconnection emits safe recovery diagnostics and existing participant presence analytics.

- iOS and Android running cadence use `feature_exposed` with only `feature=running_cadence_live` or `running_cadence_summary` when those surfaces appear. Recording quality reports availability only; cadence values, step counts, samples, timestamps, and activity IDs are excluded.

- Android recording emits `activity_recording_quality` with only `running_cadence_available` for motion coverage. Optional motion permission uses the canonical requested/completed events and a bounded result, without step timestamps or counts.

## Apple Watch running parity

The Watch app toggle, automatic Plainstride Watch imports, and allowlisted lap/goal/alert controls reuse the existing typed events. `health_workout_write_back` records phone write success/failure or a skip backed by a confirmed same-session Watch save, with only source, result, and normalized failure category. See `docs/apple-watch-running-parity.md` for exact values and offline limits. No exact health metrics, route points, session IDs, or target values enter these events.

- Gemini assistant generation emits server diagnostics with success/failure and coarse latency; failures include only operation, numeric HTTP status when available, and a bounded category. Prompts, replies, runner context, and provider error bodies are excluded. Existing client assistant outcome events remain unchanged.

### Activity duration semantics

- New phone-recorded outdoor activities use moving time for the `activity_finished` / `activity_saved` `duration_bucket`. Both events also carry `elapsed_duration_bucket`, using the same coarse duration buckets over start-to-finish wall-clock time.
- No coordinates, speed samples, exact durations, or stop locations enter analytics. Other event timing and workout-goal progress retain their existing clocks.

- Live-coach planning fallback diagnostics use only operation, numeric HTTP status, and bounded failure category, including timeouts. Existing moment/provider-result events remain unchanged; diagnostics never include runner context or generated phrases.

- iOS and Android `live_guidance_preparation_result` permits only `source_type` (`selection`, `generation`, `start`, `attachment`) and bounded result (`pending`, `generating`, `ready`, `fallback`, `failure`). Backend `live_coach_preparation` diagnostics record cache reuse, readiness, attachment, and coarse generation latency. Neither includes preparation/session IDs, request fingerprints, prompts, context, phrases, or exact runner metrics.

- iOS coaching reference diagnostics report only a bounded source (`profile`, `local_history`, `unavailable`) when it changes. Pace values, activity IDs, dates, and runner data are excluded; `live_guidance_eligibility_resolved` includes this optional `source_type`; existing moment and provider-outcome events stay unchanged.

- Android `live_guidance_reference_resolved` reports `source_type=server_statistics|unavailable` when starting a catalog workout that requests an athlete reference; it excludes pace, activity identifiers, and dates.
- Guide-profile recovery emits `guide_profile_resolution` diagnostics with bounded source/outcome. Activity completion emits `activity_completion_task` with operation/outcome and safe failure metadata only; no user IDs, prompts, activity bodies, or provider error bodies are logged.

- Weekly reviews use shared `ai_attempt` / `ai_generation` diagnostics with operation `weekly_review`. These retain the existing metadata-only privacy contract; no new client event or runner identifier is added.

- iOS and Android `live_guidance_speed_change` record `source_type=increase|decrease` and `result=detected|spoken|audio_unavailable` (plus Android `stale` for dropped queued alerts) for independent local speed-change guidance. It excludes raw speed, pace, profile, locations, timestamps, and activity identifiers. The cue-wording and bundled-recording update retains these event names and bounded properties; preparation diagnostics log only ready/expected counts, never scripts or measurements.

- Phone finish/save events include `moving_time_method=gps_observations_v2` to distinguish timestamped stop accounting from the earlier timer-polled implementation. This is an implementation enum, never a location or raw observation.

- iOS and Android `activity_share_previewed` include `count_bucket` for the coarse number of geotagged photos eligible for route annotations; it excludes photo content, identifiers, and coordinates. Off-map or unavailable thumbnails may be omitted from the rendered card.
- iOS and Android post-save sharing reuse `activity_share_previewed` and `activity_share_action` with `source_type=post_save`; preparation failure uses `result=prepare_failed`; Android share-sheet launch failure uses `result=share_failed`. No activity identifiers, exact metrics, or content are included.

## Account Statistics

- iOS and Android Me weekly summaries emit `feature_exposed` with only `feature=me_weekly_run_goal`. Goal frequency, activity counts, schedule differences, dates, source IDs, and health measurements are excluded. Existing server-statistics refresh and Progress-entry events remain unchanged.

- Successful server snapshot refresh emits existing `feature_exposed` with `feature = server_statistics`. Existing Progress controls and insight exposure events retain their coarse/semantic properties. Snapshot metrics, evidence, account/activity/source IDs, routes, timestamps, and raw errors never enter analytics.

## iOS App Review

- `app_review_requested` records only invocation of StoreKit’s native review action after the persisted three-save milestone and explicit post-save exit. It carries no event-specific properties; standard shared context and authentication collection rules still apply.
- Never interpret this event as prompt presentation, rating, submission, or sentiment. Do not send activity IDs, workout facts, exact save counts, or review content.

- Debug review requests emit only `feature_exposed` with `feature=debug_app_review_request`; they never emit production `app_review_requested` or alter milestone persistence.

## Stretch customization

- `stretch_routine_edited` records `result=opened|add|remove|replace|reorder|duration|undo|saved|reset`, with stable built-in `routine_id`, optional `activity_type`, `source_type=post_save|today|standalone`, and `stretch_customized` indicating whether the selected routine is customized. Draft actions describe editor interactions, not persisted changes; only saved/reset changes persistence.
- Existing stretch funnel events also include bounded source and customized status. Existing hold-time count buckets remain unchanged. No free text, custom IDs, posture sequences, selected body areas or health conditions are sent.

- Stretch starts and successful editor saves/resets include posture-count buckets (`one_to_three`, `four_to_six`, `seven_plus`) and estimated duration buckets (`under_3_min`, `3_to_6_min`, `6_plus_min`). Per-step/completion count buckets continue to mean held time.

- Entry-point defaults do not add an analytics event or property. Existing stretch offer/start events continue to report the stable routine ID actually shown or started; Today defaults to `pre_run_v1`, while post-save defaults to `standing_standard_v1`, regardless of indoor/outdoor context or saved customization requirements.

- iOS and Android `stretch_interface_used` records bounded `result=instructions_opened|options_opened|routines_opened|voice_enabled|voice_disabled|feedback_enabled|feedback_disabled`, stable `routine_id`, `source_type`, `stretch_customized`, and optional `activity_type`. Android also records `result=audio_ready|audio_unavailable` after preparing the selected voice’s routine clips, without voice IDs, transcripts, or audio. It contains no instruction text or user content. Today uses the existing offered/started/dismissed funnel with `source_type=today`.

- iOS and Android activity editors emit `feature_exposed` with `feature=activity_editor` on opening and `feature=activity_editor_saved` after successful metadata save. Android also emits `feature_exposed(feature=activity_editor_expanded_inputs)` once when its wrapping title and full-width distance inputs appear; typing and field contents are never tracked. No titles, metric values, or photo data are included.

- The iOS shared photo management strip retains finish-review photo events and emits existing `photo_capture_attempted`, `photo_captured`, `photo_previewed`, `photo_removed`, and `photo_reordered` events for edit drafts with `source_type=activity_edit`. Capture events include only `location_attached` as a boolean; no images, coordinates, filenames, or user content are sent. Remove/reorder describe draft actions, with persistence confirmed by `activity_editor_saved`.


Android shared inbox/roster refresh emits `social_state_refresh_result` with only `source_type=foreground|push` and `result=success|failure`. It excludes notification content, relationship/account IDs, names, and exact counts.

- iOS and Android `workout_feedback_opened` record `source_type=finish_review` when the save-review Feedback entry opens the reusable editor. It includes no selections, workout identifiers, coaching text, or sensor values. Existing submission events are unchanged.

### Single recording entry

- `activity_recording_entry`: `entry_source` is `app` or `group_activity`; `result` is `prepared` or `reused_existing`. Opening an existing recording/review does not emit a new `activity_started` event. No recording IDs, event IDs, or user content are included.

- iOS photo import location fixes retain existing `photo_captured.location_attached` instrumentation, including pre-activity imports; the boolean reflects the imported metadata. No capture times or coordinates enter analytics.

- iOS automatic `photo_album_export_completed.count_bucket` counts only camera photos eligible for export; library imports are excluded before permission requests and produce no export event when no camera photos remain. Existing `photo_captured.location_attached` reflects resolved asset/EXIF GPS after placement. Metadata diagnostics contain availability booleans and bounded placement reasons only, never asset IDs, file paths, dates, or coordinates.

- Android `photo_import_location_access` records only `source_type=activity_edit|finish_photo_library` and `result=requested|granted|denied` for optional photo-metadata access. Existing `photo_captured.location_attached` reflects actual plausible GPS for imports, without camera-route fallback. Automatic album event counts exclude imports, and imported-only saves emit no album event. Import diagnostics contain operation/error type or bounded placement reason only; no URIs, filenames, photo IDs, dates, or coordinates are logged.

### Group recording selection and location consent

- `group_activity_recording_selection_changed`: `selection_type=joined|solo`, `entry_source=today|group_activity`. Records explicit next-recording selection or attaching an existing unlinked recording.
- `group_activity_location_sharing_changed`: `selection_type=on|off`, `result=requested|success|failure`. Records the current user's location consent operation independently from recording linkage. Existing `group_run_join_attempted` / `group_run_joined` events retain their transport semantics.
- Neither event includes account, event, recording, participant identifiers, titles, or coordinates.

- Android post-run guidance feedback mirrors iOS `live_guidance_feedback_submitted`: bounded `selection_type=helpful|too_much|too_generic|bad_timing` and `cue_count_bucket`. Counts persist locally; analytics excludes coaching text and workout/activity identifiers.

- Bundled countdown playback continues to report `activity_voice_enqueue` with `source_type=bundled_audio` and success/failed results; playback failure shows one transient unavailable notice per countdown, independently of full coaching-pack readiness.

- Arrival check-in (iOS): `activity_event_arrival_changed` records bounded `selection_type=arrive|undo` and `result=success|failure`, separately from RSVP, recording, and live-map sharing. No location, arrival timestamp, or participant/event identifiers are collected.

### Race goal and planning window

- Both clients emit `planning_surface_opened` with bounded `source_type=race_goal_edit`, `entry_source=plan_details` when opening the saved race editor.
- `race_goal_updated` records only `result=success|failure` and `selection_type=short|standard`. Dates, distances, finish times, frequencies, goal/plan IDs, free text, and body measurements are excluded.
- Initial short-session and optional-mobility edits reuse `plan_intake_answer_edited` with bounded `selection_type=short_sessions|optional_mobility`, `source_type=conversation`.
- Backend operational `generated_window_refreshed` records bounded reason (`goal_updated|policy_updated|refill`), phase, and required-session count only. It is a privacy-safe service diagnostic, not a client analytics event.
- Expanding or collapsing a workout's phases in Plan Details uses `feature_exposed` with fixed `feature=plan_workout_phases` and `result=expanded|collapsed`; workout IDs, phase text, dates, duration and effort targets are excluded.

- Backend `catalog_programme_decision` operational analytics records only bounded `outcome=initial|same_week|advanced|repeated|completed`, existing planning-event trigger or `refill`, and `result=version_created`. It excludes programme/runner/workout IDs, dates, readiness/effort values, activity facts and text. `catalog_programme_failed` diagnostics contain only operation and bounded failure category.

- Structured running generation retains existing operational refresh analytics and adds only `structuredRunning` as a boolean. Workout kind, quality seconds, per-phase effort and durations remain prescription data, not analytics properties.

- Backend `goal_feasibility_decision` records only `result=eligible|blocked`. Goal distance/date, experience, history, runner identifiers and user text are excluded. Expected infeasibility is validation flow, not an error log.

- Reported session-effort planning adds only `reportedEffortLoadAvailable` (boolean) to persisted engine decisions and the existing bounded refresh diagnostic. Ratings, duration×effort values, coverage counts/ratios, activity/completion IDs and private metadata never enter analytics.

- iOS/Android optional session effort uses `feature_exposed` only with bounded `feature=session_effort_optional|session_effort_selected|session_effort_cleared|session_effort_saved`. Selection values, rating, duration×effort, activity IDs and feedback content are excluded; saved exposure follows durable local save. Categorical feedback events stay separate.

- Running benchmarks emit only bounded status/source/presence and operation/category through `running_benchmark_updated`, `running_benchmark_validation`, `running_benchmark_fallback` and version decision metadata. Distance, time, date, pace, performance estimate, goal/activity identifiers and user text are excluded. Expected invalid input is validation flow, not an error log.

- The optional benchmark editor uses `planning_surface_opened` with `source_type=running_benchmark`, `entry_source=plan_details`; `feature_exposed` uses bounded `feature=running_benchmark_saved|running_benchmark_removed|running_benchmark_save` and success/failure only. Report fields, dates, pace estimates, rating, identifiers and entered content are excluded.

- Durable iOS/Android performed-workout save uses `feature_exposed` with only `feature=performed_workout_saved` after local persistence. Receipt/plan/workout identifiers, revisions, hashes, exact effort and suitability are excluded. Backend reconciliation retains its bounded recorded/replayed categories.

- Opening running programme progress that needs review emits only `feature_exposed` with `feature=running_programme_review`. Source-week indices, calendar estimates, constraint details, prescriptions and identifiers are excluded. Expected schedule/programme validation logs only bounded operation/category.

- Existing-plan `running_plan_review` operational diagnostics use only `result=entered|cleared` and the bounded validation category. They exclude plan/version/workout/issuance identifiers, exact volume/caps/dates, ratings and private engine content. Repeated unchanged review does not emit a new entry. Generic running review reuses `feature=running_programme_review`; no new personal-data property is added.
