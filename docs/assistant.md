# Assistant

Open this when changing the in-app AI assistant, its chat UX, or the app-context it uses for discovery, navigation, support, brainstorming, and planning.

## Product Intent

- Position the assistant as a concierge for understanding and using Outbound, not only as a workout coach.
- Keep the first version local-first so the feature still works without backend dependencies.
- Reuse existing app context such as selected coach, saved activities, and current goal progress to make responses feel grounded.
- Make the assistant always reachable across the app, but quiet by default.

## UX Principles

- Always reachable: the assistant should be visible everywhere in some form.
- Context-aware: collapsed hints should change with the current screen or flow.
- Low-noise: default to passive or contextual presence, not constant interruption.
- Coach-adjacent: useful and motivating, but distinct from the live `VirtualCoach`.
- Typed outcomes over generic chat: prefer navigation, explanation, planning, and suggestions over long free-form responses.

## Shell Model

- Primary shell is a persistent bottom assistant bar in the main app chrome.
- The bar stays collapsed by default and expands into a richer assistant surface on demand.
- During live recording, the assistant switches to a compact entry mode so it does not compete with the camera/map workout UI.

### Presence Levels

- Passive: visible, minimal, waiting.
- Contextual: visible with one short screen-aware hint.
- Active: expanded conversation or guided workflow.

## Screen Map

### Main surfaces

- Today / Me:
  - default hint examples: `Want a simple plan for today?`, `Help me decide what to do`
  - primary jobs: planning, discovery, goal setup, progress explanation
- Social:
  - default hint examples: `Find the right social loop`, `What can I do here?`
  - primary jobs: navigation, feature explanation, brainstorming, social suggestions
- Settings / integrations:
  - default hint examples: `Need help setting this up?`, `What does this do?`
  - primary jobs: support, permission explanation, setup troubleshooting

### Activity-adjacent surfaces

- Record start / pre-activity:
  - hint examples: `Need help choosing a session?`, `Turn this into a quick plan`
  - primary jobs: suggested-session help, simple planning
- Live recording:
  - compact-only mode
  - primary jobs: lightweight help only
  - do not introduce a large, distracting chat surface by default
- Post-run / reflection:
  - hint examples: `Reflect on this session`, `What should I do next?`
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

- `MainTabView` owns the persistent assistant shell for the main app tabs.
- `RecordView` owns the compact live-session assistant entry.
- `AssistantView` remains the expanded assistant surface with:
  - a short hero summary
  - five capability chips: Discover, Navigate, Support, Brainstorm, Plan
  - quick-start prompt cards
  - a lightweight conversation timeline
  - a bottom composer
- The Reset button clears the stored conversation and restores the seeded intro message.

## Response Strategy

- `AssistantStore` owns draft state, stored messages, quick suggestions, and response generation.
- Messages persist in `UserDefaults` under `assistant_store_messages_v1`.
- `AssistantContext` currently includes:
  - selected coach display name
  - saved activity count
  - current week distance
  - current goal summary line, when present
- The response stack is:
  - try the backend assistant chat endpoint first
  - fall back to Apple Foundation Models when available on device
  - fall back again to deterministic local copy so the UI still works everywhere
- Backend chat keeps provider keys on the server rather than in the iOS app.
- The current assistant backend path follows the BoatShare pattern: OpenAI-compatible server-side calls to DeepSeek with JSON-shaped responses for predictable parsing.

## File Map

- `ios/Outbound/Outbound/App/OutboundApp.swift`: assistant capabilities, message model, store, persistence, and optional Apple Foundation Models responder.
- `ios/Outbound/Outbound/Core/APIClient.swift`: assistant chat request/response transport to the backend.
- `ios/Outbound/Outbound/App/MainTabView.swift`: persistent assistant shell, collapsed hints, and expanded assistant presentation from the main app tabs.
- `ios/Outbound/Outbound/Activity/RecordView.swift`: compact live-session assistant entry.
- `ios/Outbound/Outbound/App/ProfileView.swift`: assistant screen, quick starts, message bubbles, and composer.
- `backend/src/routes/assistant.ts`: assistant chat endpoint.
- `backend/src/services/ai.ts`: Anthropic-backed assistant reply generation.

## Extension Ideas

- Add typed assistant actions that can deep-link into specific settings, goals, history, or social destinations.
- Add deep links from assistant replies into specific screens such as coach settings, activity history, or social sections.
- Expand planning to generate structured weekly cards instead of plain text.
- Add support-specific diagnostics for auth setup, permissions, and imports.
- Add richer screen-aware quick prompts instead of one global prompt set.
