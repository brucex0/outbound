# Cycle-Aware Coaching

## Current implementation boundary

The iOS `CycleAwareStore` keeps raw period, energy, and discomfort logs in local app storage. It derives one coarse training signal and sends only that signal, a day, workout identifier when available, and an idempotency key to `POST /v1/personalization/cycle-signal`. The response offers a generic keep, flexible, reduce, or rest action. Neither the social API nor shared Moment responses include raw health inputs or the private reason for an adjustment.

Open this when designing menstrual-cycle logging, symptom check-ins, cycle-aware workout adjustments, HealthKit reproductive-health access, or related privacy safeguards.

## Product Principle

Cycle dates provide context. The runner's actual symptoms, training impact, and individual history determine whether a workout changes.

Use `Cycle-aware coaching`, not `female mode`. Hide its Me and Settings entry points when the onboarding body profile is male; keep it available when the body profile is female or unspecified. The feature remains optional.

Do not prescribe training from menstrual phase alone. Current evidence does not support universal phase-based programming; use individualized symptom monitoring and cautious, user-controlled adaptation instead.

Primary references:

- [Consensus statements on optimizing elite-athlete performance](https://pmc.ncbi.nlm.nih.gov/articles/PMC12334928/)
- [UEFA consensus statement on menstrual-cycle tracking](https://bmjopensem.bmj.com/content/11/3/e002769.full.pdf)
- [ACOG: The Healthy Female Athlete](https://www.acog.org/womens-health/faqs/the-healthy-female-athlete)
- [Apple HealthKit menstrual-flow type](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/menstrualflow)
- [Apple HealthKit privacy guidance](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)

## Entry Point

Place setup under `Me -> Health & body -> Cycle-aware coaching`.

The Me overview presents the feature name with its toggle directly, without a separate private-training-context heading.

Setup must explain:

- symptoms affect different people differently;
- Outbound adapts from the user's own reports and patterns;
- cycle data is never visible in Together, clubs, shared runs, or social posts;
- Apple Health connection and manual logging are both optional.

Do not add this to required onboarding.

## Logging

Support:

- period start and end;
- flow: light, medium, or heavy;
- optional symptoms: cramps, fatigue, headache, low mood, poor sleep, and other;
- training impact: none, a little, or a lot.

Training impact is the primary same-day adaptation input. Keep a quick Today check-in available without forcing the user into a full cycle calendar.

## Today Behavior

Never weaken a workout solely because a period is logged.

- No impact: keep the workout unchanged.
- Mild impact: offer a longer warm-up, effort instead of pace, shorter optional finish, indoor option, or bathroom-friendly route.
- Moderate impact: offer 20-30% less duration, easy running instead of intensity, or move the quality session while preserving safe recovery spacing.
- High impact: recommend rest, walking, or gentle mobility and adapt the week.

Always preserve agency with `Keep planned workout` and `Choose a gentler option` unless an existing independent safety rule requires otherwise.

Explain material changes precisely:

> Your quality workout moved to Thursday. Saturday remains unchanged because recovery spacing is still sufficient.

## Learned Patterns

Do not surface a pattern from one cycle. After at least three sufficiently logged cycles, Outbound may describe a cautious observation and ask permission to act on it.

Use language such as:

- `A pattern may be emerging`;
- `In your last three cycles`;
- `Would you like Outbound to keep key workouts flexible?`.

Avoid deterministic claims about hormones, weakness, injury risk, ovulation, or expected performance.

Options:

- plan with flexibility;
- keep asking each day;
- ignore the pattern.

## Social Privacy

Together may expose only the resulting compatible plan, never the private cause.

Allowed:

> Xia has a compatible easy run Thursday.

Not allowed:

> Xia changed her workout because of cycle symptoms.

Cycle dates, symptoms, contraception, pregnancy status, pain, and adjustment reasons must not appear in social APIs, activity posts, club data, notifications to other people, or group-coaching prompts.

## Data and AI Boundary

- Request HealthKit reproductive-health access separately and with explicit purpose text.
- Keep raw cycle dates, flow, and symptoms on device when feasible.
- Encrypt any required synced reproductive-health data separately from ordinary activity summaries.
- Do not use this data for advertising, attribution, engagement segmentation, or unrelated analytics.
- Do not send raw cycle history to the general assistant or social models.
- Give planning only a temporary derived signal: `no_adjustment`, `offer_flexible_option`, `reduce_load`, or `recommend_rest`.
- Let generative AI explain a deterministic adjustment without receiving the raw reproductive history.
- Support disconnect, export, and complete deletion.

## Health Safeguards

Outbound must not diagnose irregular cycles, amenorrhea, endometriosis, PCOS, pregnancy, or low energy availability.

Persistent missing or materially changed periods can be a health signal in athletes. Provide calm guidance to consult a healthcare professional rather than treating the change as a plan-optimization opportunity.

Severe or concerning symptoms should trigger care guidance, not stronger coaching claims.

## V1 Scope

Include:

- optional Apple Health import;
- manual period start/end;
- limited symptom and training-impact check-in;
- same-day gentler alternatives;
- safe weekly rescheduling;
- private, user-approved pattern learning.

Defer:

- universal phase-based plans;
- fertility or ovulation guidance;
- pregnancy and postpartum coaching;
- PCOS, endometriosis, perimenopause, or other condition-specific guidance;
- hormonal-contraception-based predictions;
- automatic social disclosure of any kind.

The clickable reference is `docs/prototypes/outbound-cycle-aware-flow.html`.
