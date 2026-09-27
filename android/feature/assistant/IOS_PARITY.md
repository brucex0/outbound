# Assistant iOS parity

Open this file when changing Android assistant behavior, its launcher entry points, or the shared companion request contract.

## Authoritative iOS sources and Android counterparts

| iOS source | Android counterpart |
| --- | --- |
| `ios/Outbound/Outbound/App/OutboundApp.swift` — capability model, destination catalog, persistent transcript, request routing, typed actions, and local response fallback | `core/assistant/CompanionContracts.kt`, `core/assistant/CompanionRepository.kt`, and `feature/assistant/AssistantViewModel.kt` |
| `ios/Outbound/Outbound/App/ProfileView.swift` — contextual assistant sheet, quick starts, conversation, confirmations, manual-workout entry, and speech UI | `feature/assistant/AssistantScreen.kt`; manual logging routes to Me and its existing Add activity entry |
| `ios/Outbound/Outbound/App/AssistantActivityCommandParser.swift` — deterministic run/bike prep from text and voice | `core/assistant/VoiceCommands.kt`; the assistant passes parsed goals to `PlainstrideApp` and opens recording setup without starting GPS |
| `ios/Outbound/Outbound/Features/Simplified/SimplifiedAppShell.swift` — persistent launcher, destination highlights, and Today context | `app/PlainstrideApp.kt` — persistent launcher, current top-level context, typed destination routing, and post-action Today refresh |
| `ios/Outbound/Outbound/Activity/RecordView.swift` — compact live-session assistant entry | `feature/recording/RecordingScreen.kt` — compact sparkles control above the live map/camera; `PlainstrideApp` opens the contextual assistant over the active session |
| `ios/Outbound/Outbound/Core/APIClient.swift` and `Domains/Athlete/CompanionContracts.swift` — companion turn and decision payloads | `core/assistant/CompanionRepository.kt` and `CompanionContracts.kt` — same endpoint, task/surface, confirmation, and action result fields |

## State and behavior contract

- Persistent launcher is available from Social, Today, and Me. The live recording HUD exposes a compact assistant entry alongside voice commands.
- The assistant starts with a persisted introduction and offers Discover, Navigate, Support, Brainstorm, and Plan prompts. Today and live-session contexts replace generic prompts with context-specific suggestions.
- Turns send the current surface, inferred companion task, bounded recent transcript, and device time zone to `POST /v1/companion/turns`. Assistant text and actions remain separate from analytics.
- Companion action confirmations show the server title, explanation, accept, and reject labels. Accept/reject outcomes are appended to the transcript; successful Today mutations trigger a Today refresh.
- A recognized navigation request uses a local typed destination catalog, adds an explicit Open action, then routes within the app. It cannot choose arbitrary views.
- Typed and spoken `start`/`begin`/`go for` run and bike commands parse distance, duration, or freestyle goals and open recording setup with a final Start tap required. Stable live partial transcripts can trigger a recognized command; non-command transcripts stay editable in the composer.
- Companion API failures and generic provider-failure messages receive a localized deterministic response, and the conversation remains account-scoped in the local cache. Reset clears the account conversation and the intro is restored next time the assistant opens.
- Manual workout quick start routes to Me and points to its existing Add activity action. Android retains its platform-specific activity-entry review UI.

## Shared resources, analytics, accessibility

- Assistant copy is translated in `src/main/res/values/strings.xml`, `values-es/strings.xml`, and `values-zh-rCN/strings.xml`.
- The event contract uses `assistant_launcher_opened` and `assistant_meaningful_engagement`, with only a bounded destination and entry source. Prompts, responses, workout details, and runner data are never included.
- Launcher and microphone controls have localized accessibility labels. Suggestion, send, confirmation, and navigation actions use native Compose buttons and keep the active recording controls visible behind the assistant route.
- Companion request recent-message objects contain only role and text. Account IDs remain in the repository key and are not added to request content or analytics.

## Reference scenarios

1. Open from Today, choose “Make this workout easier,” review the confirmation, reject it, and verify the original workout remains visible.
2. Accept a Today adjustment and verify the Today card refreshes after the server confirms execution.
3. Ask “open activity history,” choose Open, and verify the correct destination opens.
4. Type or dictate “start a 5K run”; verify recording setup shows a 5 km target and does not start until the user taps Start.
5. Dictate a non-command question; verify the transcript remains editable and can be sent as assistant chat.
6. Open from the active recording HUD, ask “How am I doing?”, and verify the turn uses the live-session surface while the recording remains active.
7. Simulate an unavailable or generic-failure companion response and verify a localized answer is appended without exposing raw error text.
8. Reset and reopen in English, Spanish, and Simplified Chinese; verify the localized intro and prompts.

## Current status and platform differences

- Implemented: persistent launcher and active-session entry, context-specific Compose experience, companion API and confirmation flow, deterministic navigation/activity prep, account-scoped persistence, localized fallback, and Android analytics.
- Platform adaptation: Android uses `SpeechRecognizer` and localized deterministic copy as fallback. Apple `SpeechAnalyzer` and Foundation Models are iOS-only. Android manual activity entry remains the existing Me-tab review flow rather than the iOS inline workout parser/card.
