# Coherent AI Running Companion

Open this when building the shared AI companion, durable runner memory, context compilation, permissioned agent actions, or dynamic workout adaptation.

## Mission

Outbound should feel like one running companion that understands how a runner trains and lives, makes visibly better decisions for the runner's actual day, acts with appropriate permission, and learns from outcomes.

The companion is a copilot rather than an unrestricted autopilot. Its memory includes life context that can plausibly affect training, recovery, motivation, safety, or communication. Direct statements become facts; repeated evidence becomes confidence-scored hypotheses; consequential assumptions require confirmation.

The product loop is:

```text
observe -> understand -> decide -> ask or act -> explain -> measure outcome -> learn
```

## Chosen Architecture

Use one logical companion identity backed by a modular companion kernel. Do not create independent planning, motivation, memory, and live-coaching agents. The shared kernel coordinates deterministic services through versioned contracts:

```text
Runner event
    -> Evidence journal
    -> Runner-model projector
    -> Context Compiler
    -> Reasoning orchestrator
    -> Candidate actions
    -> Policy, safety, and permission gate
    -> Typed action execution
    -> Outcome observation and learning
```

The language model interprets ambiguous context, compares validated candidates, and communicates naturally. It is not the database, policy engine, source of truth, or direct action executor.

Execution is tiered:

- The backend owns durable memory, context retrieval, deeper reasoning, plan orchestration, and cross-device continuity.
- The device owns latency-sensitive and offline behavior, especially live-session telemetry, reviewed safety behavior, and deterministic fallbacks.
- Both operate from the same versioned runner model and compiled session brief.

## Memory Model

The model context window is never treated as durable memory.

### Memory layers

1. **Durable identity and facts:** goals, availability, restrictions, preferences, routines, communication style, and explicit runner statements.
2. **Current state:** today's workout, plan phase, recent training load, readiness, active constraints, and pending actions. Compute this from authoritative source data.
3. **Learned runner model:** confidence-scored beliefs about recovery, realistic capacity, intensity tolerance, scheduling, and motivation. Each belief has provenance, freshness, and consequence level.
4. **Episodic memory:** meaningful events such as a difficult long run, travel disruption, a comeback, or a correction. Store structured event records and concise summaries rather than full transcripts.
5. **Raw history:** activities, check-ins, messages, sensor summaries, and outcomes. Keep these queryable and retrieve them only when relevant.

### Trust and lifecycle

Each belief records a stable key, typed value, supporting and contradicting evidence, confidence, status, timestamps, expiry policy, sensitivity, and consequence level.

- User corrections supersede inferences while preserving an audit trail.
- Contradictory evidence lowers confidence instead of silently replacing history.
- Expired beliefs stop influencing decisions.
- Consequential beliefs require stronger provenance or explicit confirmation.
- Temporary conditions expire automatically and do not become identity.
- The runner can inspect, edit, correct, and forget memories in a `What Outbound knows about me` surface.

## Context Compiler

Every reasoning request declares a task such as `adapt_today`, `answer_training_question`, `prepare_week`, `post_run_reflection`, or `live_coaching`. The Context Compiler produces a bounded, typed context package for that task.

It must:

- start with an explicit token budget;
- load mandatory safety, privacy, and authority rules;
- fetch authoritative current state through typed tools;
- rank beliefs and episodes by relevance, recency, confidence, consequence, and unresolved status;
- deduplicate overlapping facts, evidence, and summaries;
- reserve capacity for tool results, reasoning, and the response;
- emit a context manifest listing included and omitted records and their versions.

A representative deeper-planning budget is:

```text
System contract and policies       15%
Current runner and plan state      25%
Retrieved memories and evidence    25%
Recent conversational state        10%
Tool-result reserve                10%
Reasoning and response reserve     15%
```

Actual budgets are task-specific and measured in tokens, not percentages alone. Live coaching uses a much smaller precompiled package and does not perform broad retrieval for every telemetry update.

### Conversation compaction

Conversation state contains:

- the last few verbatim turns;
- a structured checkpoint with the objective, decisions, open questions, and promised follow-ups;
- validated memories promoted into the runner model.

Older dialogue compacts into structured state. Do not repeatedly summarize summaries without resolving them against stable facts and evidence, because that creates semantic drift.

### Retrieval and caching

Use direct typed lookup for authoritative state, filtered scoring for beliefs and episodes, and semantic retrieval for candidate past conversations or experiences. Embeddings discover candidates but never establish truth; consequential use resolves back to records with provenance.

Cache a small runner-core summary tied to a runner-model version, precompile Today and live-session briefs, and cache retrieval by task plus runner-model and plan versions. Domain events invalidate caches. Never cache stale authorization or safety state.

## Situational Intelligence

Dynamic inputs such as weather and location are decision signals, not durable memories or unfiltered prompt content.

```text
Raw sources
    -> Normalized, expiring signals
    -> Relevance and quality gate
    -> Decision-state snapshot
    -> Constraint resolution
    -> Validated workout candidates
```

Each signal records its type, typed value, temporal and geographic scope, confidence, source, freshness, privacy classification, and possible effects. Signal families include weather, air quality, terrain, altitude, daylight, location safety, recovery, schedule, travel, training load, equipment, facilities, preferences, and social commitments.

### Decision hierarchy

Resolve signals in this order:

1. Eliminate options that violate safety constraints.
2. Enforce training invariants and recovery limits.
3. Satisfy hard life, time, and location constraints.
4. Preserve the workout's physiological purpose where possible.
5. Rank remaining candidates by runner preference.
6. Minimize disruption to the rest of the plan.

Preferences never outweigh safety. Scores may rank options within a stage but must not flatten the hierarchy into one opaque number.

The Context Compiler includes only signals capable of changing the current decision and records excluded signals in the context manifest. The system generates several safe candidate actions before the model compares them.

### Temporal scope and impact radius

Signals can be momentary, daily, temporary, recurring, or durable. Apply the smallest necessary change:

- weather usually changes today;
- travel may change several days;
- illness may require recovery and gradual return;
- a goal-date change may affect the broader plan.

Dynamic conditions do not become memory. A repeated choice under those conditions may become a behavioral hypothesis, such as a preference for indoor running during heavy rain.

### Location privacy

- Use approximate location for forecasts when possible.
- Access precise location only for route or live-safety purposes.
- Do not send raw coordinates to the reasoning model.
- Derive bounded facts such as `hilly route`, `poor air quality`, or `sunset in 35 minutes`.
- Keep coaching-location permission separate from social and live-sharing permission.

## Reasoning and Action Loop

The bounded loop is:

```text
Trigger -> Assess -> Retrieve -> Propose -> Validate -> Act or Ask -> Explain -> Observe
```

Triggers include runner requests, readiness and feedback, material plan-state changes, missed or completed workouts, scheduled reviews, and reviewed live-session thresholds. All processing is idempotent and deduplicated.

A lightweight router determines task, urgency, required data, risk, and whether an LLM is needed. Simple questions and reviewed rules remain deterministic.

The model emits a structured proposal containing intent, assessment, evidence references, typed candidate actions, confidence, and proposed runner-facing explanation. It cannot mutate state. Unsupported actions fail closed.

The proposal validator independently checks:

- evidence existence, quality, and freshness;
- reviewed training-load and progression constraints;
- injury, symptom, and safety policies;
- schedule and plan invariants;
- privacy and tool-access permissions;
- reversibility and confirmation requirements;
- recent duplicate or conflicting actions;
- confidence appropriate to the action's consequence.

Validation may approve, reject, replace with a reviewed safer action, or downgrade the proposal to a clarifying question.

### Permission tiers

- **Tier 0 — communicate:** answer, summarize, and explain.
- **Tier 1 — reversible convenience:** prepare a workout, snooze a prompt, or move a low-priority session within an approved window.
- **Tier 2 — meaningful training change:** alter intensity, weekly structure, or a key workout. Require confirmation by default.
- **Tier 3 — sensitive or external:** health-related escalation, sharing, messaging another person, or privacy changes. Always require explicit intent and confirmation.

The runner may tighten permissions but cannot authorize unsafe coaching behavior.

### Execution and outcomes

The typed executor applies approved changes transactionally with idempotency keys. The action ledger records the trigger, evidence, context manifest, model and policy versions, proposal, validation result, permission state, before and after values, execution status, and rollback information.

Generate explanations from the validated execution record so the companion cannot claim an action occurred when it did not.

Link later evidence to the decision: acceptance, rejection, completion, feedback, reversal, and correction. Repeated rejection lowers confidence or changes the companion's interaction strategy.

## Cross-Surface Product Contract

Every surface calls one orchestration boundary with runner ID, surface, task, input or trigger, relevant entity IDs, client capabilities, and offline state. It receives a structured message, proposed actions, confirmation request, suggested replies, updated conversation state, and context receipt.

- **Today:** one high-value daily intervention answering what matters, whether the workout fits, and what changed.
- **Conversation:** ambiguity resolution, planning, explanation, corrections, and typed outcomes rather than endless chat.
- **Post-run:** ask the most informative unanswered question and distinguish observations, hypotheses, learned beliefs, and proposed changes.
- **Weekly planning:** deterministic services own progression and load bounds; the model interprets life context and compares validated structures.
- **Live coaching:** consume a precompiled session brief containing workout purpose, targets, restrictions, readiness, cue preferences, priorities, and forbidden behavior. On-device telemetry chooses moments; local constrained generation verbalizes cues.

A small versioned communication policy supplies personality, warmth, directness, verbosity, vocabulary, voice, and interruption tolerance across all surfaces. Situational constraints adjust expression without creating a different agent identity.

An attention policy ranks proactive interventions by expected benefit, urgency, confidence, and interruption cost. Allow one primary proactive item at a time, enforce quiet hours and frequency limits, suppress repetition, and learn from ignored or welcomed interventions.

## Data Model and Components

Authoritative activities, plans, profiles, goals, readiness, feedback, restrictions, and integrations stay in their owning domains. The companion accesses them through typed tools instead of copying them into chat memory.

New companion records are:

```text
RunnerEvidence
RunnerBelief
RunnerModelVersion
CompanionEpisode
ConversationState
AgentAction
AgentOutcome
SituationalSignal
ContextManifest
```

Domain events such as `activity.completed`, `readiness.submitted`, `workout.feedback_received`, `workout.missed`, `plan.changed`, `runner.fact_corrected`, and agent action outcomes feed an append-only evidence journal. An idempotent projector creates beliefs and immutable runner-model versions. Given the same evidence and projector version, Outbound must be able to reproduce the same structured understanding.

Target modular boundaries are:

```text
CompanionOrchestrator
|-- TaskRouter
|-- ContextCompiler
|   |-- DomainToolGateway
|   |-- MemoryRetriever
|   |-- SituationalIntelligence
|   |-- TokenBudgeter
|   `-- ContextManifestWriter
|-- ReasoningProvider
|-- CandidateGenerator
|-- ProposalValidator
|   |-- TrainingPolicy
|   |-- SafetyPolicy
|   |-- PrivacyPolicy
|   `-- PermissionPolicy
|-- ActionExecutor
|-- ExplanationComposer
`-- OutcomeTracker

RunnerModel
|-- EvidenceJournal
|-- BeliefProjector
|-- EpisodeBuilder
`-- ModelVersionStore
```

## Mapping from Current Outbound

- Extend `RunnerProfile`, `RunnerInsight`, and `RunnerModelVersion` into the shared runner model.
- Keep `AssistantStore` as client conversation and rendering state, not durable intelligence.
- Evolve `/assistant/chat` into a general companion-turn endpoint.
- Make `assistantActivityTools` one typed member of `DomainToolGateway`.
- Move current personalization adjustment rules behind the shared proposal validator.
- Make `VirtualCoach` consume a compiled session brief from the same runner-model version.
- Preserve deterministic local fallbacks for offline and provider failure states.
- Implement this as a modular monolith before considering service or multi-agent decomposition.

## Reliability and Evaluation

Degrade by capability:

- reasoning failure falls back to the deterministic plan;
- retrieval failure limits claims instead of inviting guesses;
- action failure never produces a success explanation;
- unavailable validation causes mutations to fail closed;
- offline writes retain timestamps and idempotency keys;
- conflicts become visible proposals rather than silent last-write-wins updates;
- live coaching continues from the compiled session brief;
- malformed proposals may be repaired once and otherwise fail closed.

Create a versioned synthetic scenario suite covering fatigue, pain, travel, weather, limited data, contradictions, corrections, stale memory, simultaneous constraints, and prompt injection in imported or user-authored text.

Measure factual grounding, policy compliance, memory accuracy, omitted-critical-context rate, unnecessary confirmations, action acceptance and reversal, proactive usefulness, latency, context tokens, and cost. Every decision must be replayable from its context manifest, runner-model version, model version, and policy version.

Operational logging defaults to structured identifiers and decision metadata rather than full private prompts. Track task distribution, retrieval budgets, validator rejection reasons, execution failures, provider latency and cost, dismissals, corrections, and rollbacks.

## Delivery Slices

1. **Shared runner understanding:** unify current domains behind typed tools; introduce evidence, beliefs, model versions, and memory controls.
2. **Context Compiler:** add task definitions, token budgets, retrieval, conversation checkpoints, manifests, and replay; keep chat read-only.
3. **Permissioned actions:** add typed proposals, validators, action ledger, and confirmations; begin with moving or shortening today's workout and updating explicit preferences.
4. **Outcome learning:** connect acceptance, completion, rejection, reversal, and correction to belief confidence and interaction preferences.
5. **Cross-surface coherence:** move Today, post-run, weekly review, and chat onto the same response contract and runner-model version.
6. **Compiled live companion:** generate and consume session briefs while retaining deterministic on-device timing and fallbacks.
7. **Proactive intelligence:** add scheduled reviews and event triggers after usefulness, interruption cost, and rollback behavior are measurable.

## First Meaningful Release

Prove one closed loop:

> The runner says this week is unusually busy. Outbound stores the temporary constraint with an expiry, proposes a safe revised week, explains the evidence and tradeoff, applies it after permission, observes completion and feedback, and expires the temporary constraint instead of treating it as permanent identity.

This slice demonstrates holistic understanding, bounded agency, context-window discipline, memory lifecycle, situational reasoning, and outcome learning without requiring the entire long-term system.

## Acceptance Criteria

- All companion surfaces use the same versioned runner understanding.
- No consequential action can bypass typed proposal validation and permission policy.
- Every applied action is explainable and replayable from stored versions and evidence.
- Context assembly stays within task-specific token budgets and exposes a manifest.
- Dynamic signals expire and do not pollute durable runner memory.
- Corrections, contradictions, forgetting, and temporary constraints behave explicitly.
- The system retains a useful deterministic experience when cloud reasoning is unavailable.
- The first release completes the busy-week loop from evidence through measured outcome.
