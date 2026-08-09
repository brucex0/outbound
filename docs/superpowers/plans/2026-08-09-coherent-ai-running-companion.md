# Coherent AI Running Companion Implementation Plan

Implement the approved companion-kernel design in vertical slices. Preserve the modular-monolith backend, existing deterministic fallbacks, and authenticated domain boundaries. Do not run the test suite; use TypeScript and Xcode build-only validation.

## Slice 1: Companion contracts and persistence

Files:

- `backend/prisma/schema.prisma`
- `backend/src/services/companion/contracts.ts`
- `backend/src/services/companion/types.ts`

Work:

1. Add durable records for runner evidence, beliefs, episodes, conversation state, context manifests, situational signals, agent actions, and outcomes.
2. Add cascade-safe user relations, stable-key uniqueness, idempotency constraints, lifecycle timestamps, and retrieval indexes.
3. Define Zod request/response contracts for companion turns, memory inspection and correction, situational signals, action proposals, decisions, and context receipts.
4. Keep the legacy assistant request compatible while the iOS client migrates.

## Slice 2: Shared runner-model projection

Files:

- `backend/src/services/companion/evidenceService.ts`
- `backend/src/services/companion/runnerModelProjector.ts`
- `backend/src/services/personalization/personalizationService.ts`

Work:

1. Append idempotent evidence for profile updates, readiness, feedback, explicit memory corrections, and action outcomes.
2. Project typed beliefs with provenance, confidence, expiry, sensitivity, and consequence levels.
3. Preserve existing `RunnerInsight` responses while backing new companion reads with the richer belief model.
4. Persist immutable runner-model snapshots that reference the evidence and projector version used.

## Slice 3: Situational intelligence and Context Compiler

Files:

- `backend/src/services/companion/situationalIntelligence.ts`
- `backend/src/services/companion/domainToolGateway.ts`
- `backend/src/services/companion/contextCompiler.ts`

Work:

1. Normalize client-provided weather, location-derived, schedule, travel, and recovery signals with source, freshness, confidence, privacy, and scope.
2. Expire stale signals and keep raw coordinates out of model-facing context.
3. Assemble task-specific runner-core, current-state, belief, episode, conversation, and situational sections.
4. Enforce deterministic character/token budgets, deduplicate content, reserve response capacity, and persist an inspectable context manifest.
5. Use direct authoritative lookups for profile, plan, readiness, feedback, and activities; use ranked retrieval only for beliefs and episodes.

## Slice 4: Companion reasoning, validation, and actions

Files:

- `backend/src/services/companion/candidateGenerator.ts`
- `backend/src/services/companion/policyValidator.ts`
- `backend/src/services/companion/actionExecutor.ts`
- `backend/src/services/companion/companionOrchestrator.ts`
- `backend/src/services/ai.ts`

Work:

1. Route deterministic activity-history and memory questions without an LLM where possible.
2. Generate deterministic workout candidates for time constraint, fatigue, soreness, weather, and explicit schedule-change requests.
3. Let the model interpret compiled context and return typed proposals but never mutate state.
4. Validate evidence freshness, safety hierarchy, training invariants, permission tier, reversibility, and duplicate actions.
5. Execute only approved typed actions with idempotency, before/after state, rollback metadata, and an action ledger.
6. Generate runner-facing explanations from validated or executed records.

## Slice 5: Companion API

Files:

- `backend/src/routes/companion.ts`
- `backend/src/routes/assistant.ts`
- `backend/src/index.ts`

Work:

1. Add authenticated endpoints for turns, snapshot, memories, corrections/forgetting, situational signals, and action decisions.
2. Evolve `/assistant/chat` into a compatibility adapter over the companion orchestrator.
3. Return messages, proposals, confirmation requests, suggested replies, runner-model version, and context receipt.
4. Fail closed for mutations and degrade to grounded deterministic responses when provider reasoning is unavailable.

## Slice 6: iOS contracts and conversation integration

Files:

- `ios/Outbound/Outbound/Core/APIClient.swift`
- `ios/Outbound/Outbound/Domains/Athlete/CompanionContracts.swift`
- `ios/Outbound/Outbound/App/OutboundApp.swift`

Work:

1. Add Codable companion context, response, proposal, memory, signal, and action-decision types.
2. Make `AssistantStore` consume the shared companion turn endpoint while retaining local fallback replies.
3. Persist structured conversation state identifiers rather than treating the full transcript as server memory.
4. Render confirmation-required proposals and submit decisions through typed APIs.

## Slice 7: Memory controls and cross-surface context

Files:

- `ios/Outbound/Outbound/Features/Personalization/PersonalizationViews.swift`
- `ios/Outbound/Outbound/Domains/Athlete/PersonalizationStore.swift`
- `ios/Outbound/Outbound/Features/Simplified/SimplifiedAppShell.swift`

Work:

1. Add `What Outbound knows about me` with confirmed and inferred memories, confidence, provenance summary, expiry, correction, and forgetting.
2. Surface one companion-driven Today intervention and its evidence-backed explanation.
3. Keep current readiness and feedback flows, but ensure they write evidence consumed by the shared runner model.
4. Avoid exposing raw location, health, or private evidence in UI explanations.

## Slice 8: Compiled live-session brief

Files:

- `backend/src/services/companion/sessionBrief.ts`
- `backend/src/routes/companion.ts`
- `ios/Outbound/Outbound/Coach/SessionAnalysisProvider.swift`
- `ios/Outbound/Outbound/Coach/VirtualCoach.swift`

Work:

1. Add a compact session-brief endpoint tied to runner-model and plan versions.
2. Include workout purpose, targets, relevant restrictions, readiness, cue preferences, priorities, and forbidden behavior.
3. Consume the brief in live coaching while preserving deterministic on-device timing and offline fallback.
4. Upload only bounded post-session evidence summaries, not raw continuous telemetry.

## Slice 9: Documentation, build verification, and deployment

Files:

- `docs/assistant.md`
- `docs/personalized-running-companion.md`
- `docs/backend-architecture.md`
- `docs/backend-deploy.md`
- `docs/INDEX.md`

Work:

1. Document the implemented contracts, ownership, privacy behavior, rebuild command, and rollout sequence.
2. Run Prisma generation and `npm run build`.
3. Run the documented Xcode build-only command without invoking tests.
4. Deploy the Cloud Run service using the documented project and region.
5. Pin and execute the database-push job against the deployed image before relying on new routes.
6. Verify `/health` and authenticated companion route behavior with non-sensitive requests.
7. Commit the final implementation with unrelated workspace files excluded.

## Completion Criteria

- Chat, Today, personalization, and live-session preparation share a versioned runner model.
- The Context Compiler produces bounded, persisted manifests and does not dump raw history into prompts.
- Dynamic signals are typed, expiring, privacy-filtered, and considered through a deterministic constraint hierarchy.
- Consequential actions require validated typed proposals and appropriate permission.
- Memories are inspectable, correctable, forgettable, and tied to evidence.
- Provider or retrieval failures retain a useful deterministic app experience.
- Backend and iOS compile successfully, the schema is deployed, and live Cloud Run health verification succeeds.
