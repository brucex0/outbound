# Assistant

Open this when changing the in-app AI assistant, its chat UX, or the app-context it uses for discovery, navigation, support, brainstorming, and planning.

## Product Intent

- Position the assistant as a concierge for understanding and using Outbound, not only as a workout coach.
- Keep the first version local-first so the feature still works without backend dependencies.
- Reuse existing app context such as selected coach, saved activities, and current goal progress to make responses feel grounded.
- Make the assistant always reachable across the app, but quiet by default.

## UX Principles

- Always reachable: the assistant should be visible everywhere in some form.
- Context-aware: the expanded assistant should use the current screen or flow when suggesting next steps.
- Low-noise: default to a passive icon, not constant interruption.
- Coach-adjacent: useful and motivating, but distinct from the live `VirtualCoach`.
- Typed outcomes over generic chat: prefer navigation, explanation, planning, and suggestions over long free-form responses.

## Shell Model

- Primary shell is a standalone sparkles icon in the main app chrome.
- The icon sits to the left of the floating tab switcher in the bottom chrome row as a separate control, not inside a shared navigation container.
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

- Record start / pre-activity:
  - primary jobs: suggested-session help, simple planning
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
- `brainstorm`: generate options for routines, goals, or product ideas
- `plan`: turn vague intent into a simple next step or weekly structure
- `suggest_session`: propose a likely next workout or direction
- `summarize_progress`: reflect recent activity or goal momentum

## Current Implementation Shape

- `MainTabView` owns the persistent assistant launcher for the main app tabs.
- `RecordView` owns the compact live-session assistant entry.
- `AssistantView` remains the expanded assistant surface with:
  - a short hero summary
  - five capability chips: Discover, Navigate, Support, Brainstorm, Plan
  - quick-start prompt cards
  - a lightweight conversation timeline
  - a bottom composer with a microphone shortcut for short activity-start commands, including an animated listening wave and live transcript text in the composer
- The Reset button clears the stored conversation and restores the seeded intro message.

## Response Strategy

- `AssistantStore` owns draft state, stored messages, quick suggestions, and response generation.
- Messages persist in `UserDefaults` under `assistant_store_messages_v1`.
- `AssistantContext` currently includes:
  - selected coach display name
  - saved activity count
  - current week distance
  - current goal summary line, when present
- Activity-start commands are deterministic V1 actions, not open-ended chat. The speech request uses command-specific recognition hints, and the parser normalizes common short-command variants such as `ten kay run`, `5 k`, and `thirty minute run`. Phrases such as `start a 10K run` or `bike for 45 minutes` prepare the shared activity start page with the parsed session goal, then require the user to tap Start. During voice input, a recognized command executes after the live partial transcript stays stable briefly; the composer Send button uses the same parser before falling back to assistant chat, so corrected voice text and typed commands route the same way.
- The response stack is:
  - try the backend assistant chat endpoint first
  - fall back to Apple Foundation Models when available on device
  - fall back again to deterministic local copy so the UI still works everywhere
- Backend chat keeps provider keys on the server rather than in the iOS app.
- The current assistant backend path follows the BoatShare pattern: OpenAI-compatible server-side calls to DeepSeek with JSON-shaped responses for predictable parsing.

## Voice Recognition Upgrade Path

Current state:

- The assistant microphone uses `SpeechAnalyzer` with `SpeechTranscriber` on iOS 26+.
- The SpeechAnalyzer path reserves the transcriber locale through `AssetInventory`, installs missing speech assets when needed, and converts mic buffers into one of `SpeechTranscriber.availableCompatibleAudioFormats` before creating `AnalyzerInput`.
- Older OS versions still use `SFSpeechRecognizer`.
- Both paths show local live partial transcripts and then run the deterministic parser for activity-start commands.
- The app gives speech recognition command-specific hints for short activity phrases.
- This keeps V1 simple and native, but recognition quality can still be brittle for commands such as `start a 10K run`.

Recommended next step:

- Keep Apple Speech as the live preview and offline fallback.
- Record the short push-to-talk utterance locally.
- After speech settles, send the short audio clip to the backend instead of trusting the local transcript.
- Backend transcribes with OpenAI `gpt-4o-mini-transcribe` by default, or `gpt-4o-transcribe` when accuracy matters more than cost.
- Use a transcription prompt that biases toward Outbound command vocabulary:
  - sports: `run`, `bike`, `ride`
  - goals: `3K`, `5K`, `10K`, `kilometers`, `miles`, `20 minutes`, `30 minutes`, `45 minutes`
  - intents: `start`, `set up`, `go for`, `ride for`
- Run the existing deterministic `AssistantActivityCommandParser` on the returned transcript.
- If backend transcription fails, fall back to the Apple Speech transcript already shown in the composer.

Why this shape:

- OpenAI's speech-to-text endpoint supports `gpt-4o-mini-transcribe` and `gpt-4o-transcribe`, which are intended to improve accuracy over older Whisper-style transcription.
- The file-based transcription path is enough for short push-to-talk commands and avoids adding a streaming WebSocket path immediately.
- OpenAI Realtime transcription is the better fit only if Outbound later needs continuous, low-latency workout conversation with server-side voice activity detection.
- Third-party realtime ASR providers such as Deepgram or AssemblyAI may be worth evaluating for always-on or very low-latency voice, but they add another vendor and streaming integration before the product clearly needs it.

Suggested backend contract:

```http
POST /v1/assistant/transcribe-command
Content-Type: multipart/form-data

audio=<short m4a/wav clip>
```

Response:

```json
{
  "transcript": "start a 10K run",
  "confidence": "usable",
  "source": "openai:gpt-4o-mini-transcribe"
}
```

Client behavior:

- Show Apple Speech partials while recording so the UI feels responsive.
- Show a brief `Checking command...` state after speech ends.
- If the backend transcript parses into an activity command, open `RecordView` with the goal selected.
- If it does not parse, leave the best transcript in the composer for editing or normal assistant chat.

Useful references:

- OpenAI speech-to-text guide: https://platform.openai.com/docs/guides/speech-to-text
- OpenAI `gpt-4o-mini-transcribe`: https://platform.openai.com/docs/models/gpt-4o-mini-transcribe
- OpenAI `gpt-4o-transcribe`: https://platform.openai.com/docs/models/gpt-4o-transcribe
- OpenAI Realtime transcription: https://platform.openai.com/docs/guides/realtime-transcription

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

- `ios/Outbound/Outbound/App/OutboundApp.swift`: assistant capabilities, message model, store, persistence, and optional Apple Foundation Models responder.
- `ios/Outbound/Outbound/App/AssistantActivityCommandParser.swift`: deterministic parser for short voice activity commands.
- `ios/Outbound/Outbound/App/OutboundActivityIntents.swift`: App Intents and App Shortcuts for Siri/system activity prep.
- `ios/Outbound/Outbound/App/PreparedActivityLaunch.swift`: persisted pending activity launch request shared by App Intents and the app shell.
- `ios/Outbound/Outbound/Core/APIClient.swift`: assistant chat request/response transport to the backend.
- `ios/Outbound/Outbound/App/MainTabView.swift`: standalone assistant launcher and expanded assistant presentation from the main app tabs.
- `ios/Outbound/Outbound/Activity/RecordView.swift`: compact live-session assistant entry.
- `ios/Outbound/Outbound/App/ProfileView.swift`: assistant screen, quick starts, message bubbles, composer, and speech recognition bridge.
- `backend/src/routes/assistant.ts`: assistant chat endpoint.
- `backend/src/services/ai.ts`: Anthropic-backed assistant reply generation.

## Extension Ideas

- Expand typed assistant actions beyond activity prep into settings, goals, history, or social destinations.
- Add deep links from assistant replies into specific screens such as coach settings, activity history, or social sections.
- Expand planning to generate structured weekly cards instead of plain text.
- Add support-specific diagnostics for auth setup, permissions, and imports.
- Add richer screen-aware quick prompts instead of one global prompt set.
