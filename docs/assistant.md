# Assistant

Open this when changing the in-app AI assistant, its chat UX, or the app-context it uses for discovery, navigation, support, brainstorming, and planning.

## Product Intent

- Position the assistant as Plainstride's persistent running companion, not as a separate named guide or generic chatbot.
- Keep the first version local-first so the feature still works without backend dependencies.
- Reuse existing app context such as companion communication style, saved activities, and current goal progress to make responses feel grounded.
- Make the assistant always reachable across the app, but quiet by default.

## UX Principles

- Always reachable: the assistant should be visible everywhere in some form.
- Context-aware: the expanded assistant should use the current screen or flow when suggesting next steps.
- Low-noise: default to a passive icon, not constant interruption.
- Guide-adjacent: useful and motivating, but distinct from the live `VirtualGuide`.
- Typed outcomes over generic chat: prefer navigation, explanation, planning, and suggestions over long free-form responses.

## Shell Model

- Primary shell is a standalone sparkles icon floating above the leading side of the main tab bar.
- The launcher remains visually separate from `Social · Today · Me`, so it reads as a persistent app capability rather than a fourth destination.
- The icon is the minimized state and expands into a richer assistant surface on demand.
- During live recording, the assistant switches to a compact entry mode so it does not compete with the camera/map workout UI.

### Presence Levels

- Minimized: visible as the standalone sparkles icon.
- Expanded: conversation or guided workflow with screen-aware quick starts.

## Screen Map

### Main surfaces

- Me:
  - primary jobs: planning, discovery, goal setup, progress explanation
- Social:
  - primary jobs: navigation, feature explanation, brainstorming, social suggestions
- Settings / integrations:
  - primary jobs: support, permission explanation, setup troubleshooting

### Activity-adjacent surfaces

- Today:
  - uses the same global launcher as every other main surface
  - prioritizes the visible workout in its context label and quick starts while retaining general questions and app navigation
  - applies supported distance, duration, and effort changes directly to the visible workout through the shared conversation
- Record start / pre-activity:
  - primary jobs: suggested-session help, simple planning, and conversational activity customization
  - concrete duration and effort requests update the card and its launch intent immediately
- Live recording:
  - compact-only mode
  - primary jobs: lightweight help only
  - do not introduce a large, distracting chat surface by default
- Post-run / reflection:
  - primary jobs: summary, progress framing, recovery or next-step suggestions

## V1 Action Model

- `answer`: explain or summarize a feature, screen, or state
- `navigate`: point users to the right place in the app
- `support`: explain setup, integrations, or likely fixes
- `brainstorm`: generate personal ideas for workout enjoyment, motivation, routines, and goals. The quick-start prompt asks for ideas tailored to the user’s goals and recent activity, with a clarifying question when needed; the offline reply keeps the same personal focus. Suggestion taps retain the existing `assistant_meaningful_engagement` event (`entry_source: suggestion`) without logging prompt text.
- `plan`: turn vague intent into a simple next step or weekly structure
- `suggest_session`: propose a likely next workout or direction
- `summarize_progress`: reflect recent activity or goal momentum

## Destination And Highlight Framework

- `AssistantDestinationRegistry` is the source of truth for assistant-reachable pages and general app information. Each entry has a stable ID, title, description, and optional default highlight anchor.
- `AssistantNavigationTarget` is a typed request containing a destination and optional anchor. The model never receives permission to name or manipulate arbitrary SwiftUI views.
- `AppNavigationStore` coordinates tab selection, detail navigation, and the pending highlight across app surfaces.
- Add `.assistantHighlightAnchor("stable.anchor.id")` to an important control or content region to make it spotlightable. Anchors are opt-in because SwiftUI does not expose a reliable semantic runtime inventory of every view.
- Product-help requests include the destination catalog as bounded source-of-truth context, so navigation and app explanations use the same metadata.
- Adding a destination requires one registry entry and a renderer at the app composition root. Top-level destinations select their tab; detail destinations are pushed in the Me navigation stack.
- Appearance requests such as “change app theme” route directly to the shared appearance chooser instead of returning setup instructions or stopping at Settings.

## Current Implementation Shape

- `SimplifiedAppShell` owns the persistent assistant launcher for the main app tabs and presents the shared assistant at medium or large sheet heights. The launcher and compact navigation capsule share one dock with a fixed 16-point gap across phone sizes and rotations. The launcher's recurring animation state is isolated inside `AssistantLauncherButton`, so each pulse does not invalidate the surrounding tab, toolbar, or presented native menus.
- While the app scene is active, the launcher plays a noticeable bounce, sparkle shimmer, and expanding glow ring about every four seconds after a short initial settle delay.
- The loop stops when the app leaves the foreground and resumes when it becomes active again. Assistant presentation, tab changes, and activity presentation do not consume or permanently suppress the loop.
- `RecordView` owns the compact live-session assistant entry.
- `AssistantView` remains the expanded assistant surface with:
  - a short hero summary
  - contextual quick-start prompt cards (Today shows workout-focused prompts; other screens show Log a workout, Plan, Support, and Brainstorm)
  - a lightweight conversation timeline
  - a text-only bottom composer; the microphone shortcut is hidden while assistant voice input is unsupported
- The Today workout card no longer carries a separate sparkle button or `Ask companion` menu action. Its assistant work uses the global `AssistantStore` transcript and Today-focused context.
- Android parity source: `android/feature/assistant/IOS_PARITY.md` lists the Compose screens, repository, activity command handoff, translated copy, analytics, and scenario checklist. Android shares the companion API and deterministic local responses, with a text-only assistant composer.
- The Reset button clears the stored conversation and restores the seeded intro message.
- Text sends and suggestions retain the existing `assistant_meaningful_engagement` analytics contract; hiding the unsupported microphone adds no new input events.

## Shared Shortcut Contract

- Both platforms use these IDs, ordering, and conditions:

| Context | Shortcut IDs, in order | Labels |
| --- | --- | --- |
| Today with an available workout | `today-easier`, `today-why`, `today-history` | Make this workout easier; Why this workout?; Open activity history |
| All other contexts, including Today without a workout | `log-workout`, `plan`, `support`, `brainstorm` | Log a workout; Plan my week; Help me set up; Brainstorm ideas |

- Android reads workout availability from the same shell-scoped Today state as the visible Today screen. Loading or failed states without a usable suggestion show general shortcuts; a usable cached suggestion still counts as available.
- Shortcut labels and prompts use the `assistant.assistant.*` entries in `Localizable.xcstrings`, also used to generate Android resources. Preserve identical translations and prompt meaning across platforms.
- History taps open the existing typed activity-history destination directly, without language interpretation or a model call. Log a workout retains each platform’s existing manual-entry flow.
- Every shortcut tap retains `assistant_meaningful_engagement` with bounded destination and `entry_source: suggestion`; no shortcut text, workout details, or runner data enters analytics.
- Manual verification: compare ordered shortcuts on Today with a workout, Today without one, Me, Social, and recording; repeat with cached/offline suggestions and all three languages. History must open activity history, and general shortcuts must still perform their existing actions.

## Shared Product Knowledge

- `shared/assistant/product-knowledge.txt` supplies bounded feature facts and action limits to backend replies/interpretation and both client reply paths. It is model context, not display copy.
- After editing it, run `python3 scripts/generate-assistant-knowledge.py` and commit all three generated runtime files with their respective platform changes. Verify synchronization with `python3 scripts/generate-assistant-knowledge.py --check`.
- Keep the catalog grounded in existing screens. Missing catalog entries or assistant actions are not evidence that a feature is unavailable. Corrections must be checked against feature facts rather than earlier assistant claims.
- Navigation remains limited to each client’s typed catalog; use a containing screen and explain remaining manual steps when a nested feature lacks a direct link. Existing bounded destination analytics remain unchanged; no prompts or feature content enter analytics.
- Manual verification: ask about shoes, appearance, records, integrations, routes, sharing, and stretches; repeat with a correction after a wrong reply. Check questions and negated requests do not execute actions, unknown features do not receive invented availability claims, and opening a parent screen never claims a nested change completed. Model/device verification is required; compilation alone does not establish language understanding.

## Response Strategy

### Unified companion path

Authenticated builds now send assistant turns to `POST /v1/companion/turns`. The endpoint compiles bounded context from the shared runner model, current plan and activities, conversation state, and fresh situational signals. It returns a message, optional typed action and confirmation request, runner-model version, and context receipt. `AssistantStore` renders the confirmation and submits decisions through `POST /v1/companion/actions/:id/decision`.

The legacy `POST /v1/assistant/chat` route remains a compatibility adapter. When authenticated database context is available, it delegates to the same companion orchestrator before falling back to the older assistant path.

Conversation transcripts are not durable runner memory. The backend stores a bounded conversation checkpoint, while validated facts and hypotheses live in the versioned runner model. The iOS local and Foundation Models fallbacks remain available when companion or provider calls fail.

- `AssistantStore` owns draft state, stored messages, quick suggestions, and response generation.
- Messages persist in `UserDefaults` under `assistant_store_messages_v1`.
- `AssistantContext` currently includes:
  - selected companion communication profile
  - saved activity count
  - current week distance
  - current goal summary line, when present
  - current screen and recording state
  - current device time zone, so backend date questions such as "yesterday" use the user's local day
- Free-form activity-start requests use structured local intelligence. Requests such as `start a 10K run` or `bike for 45 minutes` prepare the shared activity start page with the extracted goal and require a final Start tap. Assistant microphone input remains unavailable; the dormant speech bridge retains fixed recognition vocabulary only.
- `Log a workout` is an explicit button action that starts a manual draft. Free-form logging requests and follow-ups use structured Apple Intelligence interpretation, with authenticated server interpretation as fallback. Missing fields prompt for clarification; `Enter workout details` appears only while a manual draft has missing required fields. Completed drafts use `Review and Save`; general conversations do not show a manual-entry button. Direct entry retains the `assistant_meaningful_engagement` event with `entry_source: manual_entry`. A completed draft still requires review and Save.
- Today workout customization uses the global transcript and the authenticated companion action path. The assistant only reports success after the planned-workout mutation executes, then refetches `TrainingPlanStore` so the Today card immediately reflects the canonical workout and its updated steps. The action response includes a concise description of the changed fields; failures retain the original card and produce an explicit error response. Local activity-goal customization remains available for preparing a new unsaved activity, but it must not claim to have edited a persisted Today workout.
- Users can explicitly ask the assistant to recalibrate, reassess, review, or update their training plan. This runs the bounded server-side AI planning evaluation against recent training, recovery state, adherence, feedback, and upcoming workouts. If the current plan remains appropriate, the assistant says so without creating a mutation. If the evaluator finds a useful change, the assistant presents it through the existing confirmation card and only applies or rejects the underlying personalization adjustment after the user's decision. Manual assistant reviews share the planning cooldown, and no separate plan-card entry point is exposed.
- Product-help prose prefers Apple Intelligence with the current destination catalog and bounded conversation. Training, live coaching, and persisted plan changes retain the server companion/action flow. Server failures can still use bounded on-device reply generation and localized offline copy.
- Generic provider failure text such as `Sorry, something went wrong. Please try again.` is treated as unusable and falls through to deterministic local copy; backend transport errors are logged under the `Assistant` OSLog category for device debugging.
- Backend chat keeps provider keys on the server rather than in the iOS app.
- The assistant backend uses the Google GenAI SDK with `gemini-3.8-flash` (override with `APP_AI_MODEL`), low thinking, schema-constrained JSON, and a 20-second deadline. Authentication uses `GEMINI_API_KEY` locally or Vertex runtime identity via `GEMINI_VERTEX_PROJECT_ID`/`GOOGLE_CLOUD_PROJECT`; `APP_AI_KEY` and `APP_AI_BASE_URL` are no longer used for assistant calls. Existing bounded context, action permissions, and local fallbacks remain unchanged.
- When Firebase auth and `DATABASE_URL` are available, the backend assistant route enriches each chat request with read-only, typed activity tools:
  - resolves the authenticated app user on the server
  - reads recent synced activity summaries through Prisma
  - excludes route geometry, coordinates, images, and health metrics from assistant chat context
  - answers simple activity-history questions such as "did I run yesterday?" deterministically before calling the model
  - passes the same recent activity summaries into the model prompt for richer history and planning answers
- Do not expose arbitrary SQL or raw database rows to the model. Add backend tool functions with typed input/output when the assistant needs more app capability.

## Local Language Interpretation

- `App/LocalIntelligence.swift` owns the shared interpretation contract and Apple Foundation Models implementation. A small `@Generable` route schema chooses the operation using only the current message and whether a manual draft exists. Workout turns use a dedicated sport schema and extract exact source spans before requesting numeric duration or optional details. No matching source span means no field update. Short semantic confirmations check candidate spans before optional fields are accepted, and distinguish a whole-message duration answer from a generic logging request. Duration components are extracted only from the matched time phrase; a duration cited from inside a pace phrase is excluded so native distance/pace arithmetic remains authoritative. Optional distance, pace, date, time and setting also require a second source check before accepting values. Model explanations and source spans are neither logged nor stored. General conversation and plan changes never run workout extraction. Availability and app-locale checks precede generation; unsupported inputs or generation failures fall back to `POST /v1/assistant/interpret`.
- During an active manual-workout draft, a reply whose exact time span covers the entire message can take the duration-only path after normal operation routing and an Apple-model duration-only check. It uses four generations (route, source span, semantic check, numeric components), skips sport and optional-field extraction, and preserves the draft's other values. Mixed replies retain full extraction. Native bounds, cancellation, provider fallback, and review/Save remain shared with the full path.
- Each turn supplies bounded reference context: current draft, current instant/time zone, measurement preference, current screen/workout ID, allowed destinations, and at most four recent messages of 400 characters each. Routing and basic extraction use only the current input; relative-date extraction uses reference dates. Each local generation has a 15-second cancellation deadline. Messages over 4,000 characters ask the user to shorten input rather than silently truncating it. App locale is explicit in model instructions. Fresh sessions avoid hidden state surviving Reset.
- Interpretation covers completed-workout logging, new activity preparation, navigation, assistant capability/task routing, cancellation, and clarification. Number words and multilingual phrases are interpreted semantically; there is no keyword/regex fallback for arbitrary assistant text.
- The model proposes values only. Swift validates ranges and fixed-format dates/times, converts units, sums duration components, and derives duration from distance/pace. Missing fields preserve the draft; invalid values do not modify it. Native validation runs before a provider result is accepted. Invalid Apple output logs only operation and rejected field category, then tries the server; invalid server output reports `invalid_output` and uses direct entry. Generation success alone is not interpretation success. Activity setup supports one distance or duration goal and retains the final Start tap. Manual workouts retain review and Save. Existing plan/workout mutations remain server-authoritative and confirmation-gated.
- If both interpreters are unavailable, the assistant explains the failure and offers direct workout entry. An in-progress draft is preserved and opens in the review form. `Enter workout details` is always available as an explicit form action. Dismissed assistant sends are cancelled before local actions execute.
- `assistant_interpretation_completed` records only `source_type` (`apple`, `server`, or `none`) and `result` (`success`, `unavailable`, `invalid_input`, `invalid_output`, or `cancelled`), plus the existing coarse `latency_bucket` values (`under_250ms`, `250ms_1s`, `1s_3s`, `3s_8s`, `8s_plus`). Existing engagement instrumentation remains. No prompt, model output, duration, distance, date, or destination selection is added to this event. Diagnostics contain operation/provider and safe error type/code only.
- The unused `TodayActivityCompanionSheet` and `TodayActivityCustomizer` duplicate parsers are removed. The older unreferenced onboarding view/analyzer remains outside the production onboarding flow; current plan-intake interpretation already uses the backend context/confirmation contract.
- Fixed-format numeric form fields, App Intent parameters, API payloads, import files, and internal editorial label envelopes remain deterministic. Speech transcription is separate from language interpretation; the assistant microphone remains hidden. `AssistantRecognitionVocabulary` only supplies fixed recognition hints for the dormant bridge.
- Rollout: deploy the backend interpretation route before distributing this iOS change. There is no database migration. Android behavior is unchanged; the endpoint contract can be reused by a future Android interpreter.

Manual verification before release:

- Duration-latency check (2026-10-31, actual Mac Apple model): `one hour and 20 minutes` resolved to 80 minutes with four generations in about 2.1 seconds, versus fifteen generations/about 7.5 seconds in the baseline. Spanish and Chinese 80-minute replies also used four generations. Device timing varies. Mixed sport, pace, setting, question, cancellation, and invalid-zero probes retained the full-path/validation behavior. The mixed reply `one hour yesterday` reached server fallback in both baseline and optimized builds; that existing extraction limitation remains.

- Run these language cases through the actual Apple model on an enabled device. A passing build or fixed-output conversion check does not verify language understanding. The 2026-10-31 Bruce main device probe verified generic logging, `Swim`, `one hour`, `Swim one hour`, `Nadé una hora`, and `游泳一个小时` using the real Apple model without saving or starting an activity.

- English `one hour`, Spanish `una hora`, and Chinese `一个小时` during an active manual draft resolve to 60 minutes; mixed hour/minute phrases retain both components.
- Follow-up corrections preserve other fields; explicit outdoor changes clear indoor; relative dates use the current local date and time zone; distance plus per-unit pace derives duration.
- Questions and negated commands do not open recording or save workouts. Ambiguous or unsupported goals ask for clarification. Nothing starts or saves before the existing user confirmation.
- Exercise Apple available/unavailable, unsupported language, server failure, cancellation, and Reset. Confirm direct form entry remains available and no prompt/output appears in diagnostics or analytics.

### Siri And App Intents

Siri should be treated as a parallel system-level command surface, not a replacement for the in-app assistant microphone.

Current Siri scope:

- App Intents/App Shortcuts prepare activities from system voice commands.
- Supported shortcut families:
  - distance run: `3K`, `5K`, `10K`
  - timed run: `20 minutes`, `30 minutes`, `45 minutes`
  - freestyle run
  - distance bike: `3K`, `5K`, `10K`
  - timed bike: `20 minutes`, `30 minutes`, `45 minutes`
  - freestyle bike
- Route parsed Siri intent values into the same `SessionIntent` and `ActivityGoal` path used by the in-app assistant.
- Open the app to `RecordView` with the activity and goal selected.
- Keep the final in-app `Start` tap for now, so accidental Siri triggers do not immediately start GPS recording.
- App Shortcut phrase parameters are represented as preset `AppEnum` values because shortcut phrases allow only one parameter and reject free-form measurement parameters in this target.

Apple API notes:

- `StartWorkoutIntent` exists in App Intents as a system workout intent. Apple documents it as an App Intent for starting workouts, with `workoutStyle`, `suggestedWorkouts`, `openAppWhenRun`, and `perform()` hooks. It is especially documented around Apple Watch Ultra Action Button workout actions.
- Legacy SiriKit `INStartWorkoutIntent` explicitly models `goalValue`, `workoutGoalUnitType`, workout name, workout location, and open-ended workouts. It remains useful as a conceptual reference for the typed data Siri can provide for workout requests.
- Current Assistant Schemas documentation lists domains such as books, browser, camera, files, mail, photos, system, and others; do not assume a public `.workout` assistant schema exists unless Apple documents it for the current SDK.

Implementation shape:

- `OutboundActivityIntents.swift` defines focused App Intents for distance, timed, and freestyle run/bike prep.
- `PreparedActivityLaunch.swift` persists a compact launch request in `UserDefaults`.
- `MainTabView` consumes stored launch requests on appear and when the scene becomes active.
- Reuse `RecordView` confirmation rather than starting the recorder inside `perform()`.
- Future work can evaluate conforming to Apple's `StartWorkoutIntent`, but only if it still supports Outbound's prepare-first UX.

Useful references:

- Apple `StartWorkoutIntent`: https://developer.apple.com/documentation/appintents/startworkoutintent
- Apple `INStartWorkoutIntent`: https://developer.apple.com/documentation/intents/instartworkoutintent
- Apple Assistant Schemas: https://developer.apple.com/documentation/appintents/assistantschemas/intent
- Apple Siri and Apple Intelligence App Intents: https://developer.apple.com/documentation/AppIntents/Integrating-actions-with-siri-and-apple-intelligence

### Apple SpeechAnalyzer

`SpeechAnalyzer` is the active local recognizer on iOS 26+.

What it is:

- Apple's newer Speech framework API for analyzing live or recorded spoken audio.
- Apple describes it as an analyzer session that owns one or more modules, accepts audio input, controls analysis, and emits async results.
- For transcription, the relevant module is `SpeechTranscriber`; for voice activity detection, use `SpeechDetector`.
- It uses Swift concurrency: apps provide audio through an `AsyncSequence` of `AnalyzerInput`, and modules expose results through `AsyncSequence`.
- Apple positions it as faster and more flexible than `SFSpeechRecognizer`, with better support for long-form, live, and distant audio.
- It supports asset management through `AssetInventory`, so the app can ensure needed local speech assets are installed.

Why it may fit Outbound:

- It keeps voice command recognition on-device and avoids adding a backend dependency for short commands.
- `SpeechDetector` can later replace the current debounce/silence behavior with a real VAD module.
- `SpeechTranscriber` results can still feed the deterministic `AssistantActivityCommandParser`.
- `prepareToAnalyze(in:)` and model-retention options can reduce first-result latency for the assistant sheet.

Risks and constraints:

- It is iOS 26+ / modern-SDK work. Keep `SFSpeechRecognizer` only for older OS versions.
- It is still transcription, not intent parsing. Outbound still needs typed command parsing after transcription.
- Asset installation and locale support are explicit startup steps; failed asset prep should surface a listening error instead of silently falling through.
- `AnalyzerInput` requires 16-bit signed PCM, and the live transcription model may reject the hardware sample rate. The mic tap must convert into a `SpeechTranscriber.availableCompatibleAudioFormats` format rather than assuming the device's native 48 kHz format is supported.
- iOS has limits on simultaneous analyzer/backing model instances, so live workout voice, assistant voice, and any future dictation features must coordinate ownership.

Recommended migration:

1. Extract the current nested assistant speech code into an `AssistantSpeechRecognizer` protocol if the implementation grows further.
2. Add `SpeechDetector` or analyzer finalization to detect end-of-speech instead of relying only on a debounce.
3. Feed finalized transcription into `AssistantActivityCommandParser`.
4. If SpeechAnalyzer still misses command accuracy targets, add the backend OpenAI transcription path as a higher-accuracy final pass.

Useful references:

- Apple `SpeechAnalyzer`: https://developer.apple.com/documentation/speech/speechanalyzer
- Apple Speech framework overview: https://developer.apple.com/documentation/speech/
- Apple WWDC25 `SpeechAnalyzer` session: https://developer.apple.com/videos/play/wwdc2025/277

## File Map

- `ios/Outbound/Outbound/App/OutboundApp.swift`: assistant capabilities, message model, store, persistence, and server-owned companion response/action flow.
- `ios/Outbound/Outbound/App/LocalIntelligence.swift`: structured local interpretation, bounded generation, validation, and server fallback.
- `ios/Outbound/Outbound/App/AssistantRecognitionVocabulary.swift`: fixed hints for the dormant speech bridge.
- `ios/Outbound/Outbound/App/OutboundActivityIntents.swift`: App Intents and App Shortcuts for Siri/system activity prep.
- `ios/Outbound/Outbound/App/PreparedActivityLaunch.swift`: persisted pending activity launch request shared by App Intents and the app shell.
- `ios/Outbound/Outbound/Core/APIClient.swift`: assistant chat request/response transport to the backend.
- `ios/Outbound/Outbound/App/MainTabView.swift`: standalone assistant launcher and expanded assistant presentation from the main app tabs.
- `ios/Outbound/Outbound/Activity/RecordView.swift`: compact live-session assistant entry.
- `ios/Outbound/Outbound/App/ProfileView.swift`: assistant screen, quick starts, message bubbles, composer, and speech recognition bridge.
- `backend/src/routes/assistant.ts`: assistant chat endpoint.
- `backend/src/services/assistantInterpretation.ts`: schema-validated server interpretation fallback.
- `backend/src/services/ai.ts`: configured-provider assistant reply generation.

## Extension Ideas

- Expand typed assistant actions beyond activity prep into settings, goals, history, or social destinations.
- Add deep links from assistant replies into specific screens such as companion settings, activity history, or social sections.
- Expand planning to generate structured weekly cards instead of plain text.
- Add support-specific diagnostics for auth setup, permissions, and imports.
- Add richer screen-aware quick prompts instead of one global prompt set.
