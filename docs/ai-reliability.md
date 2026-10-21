# AI Reliability

Open this for structured AI failures, model qualification, retry behavior, or AI alerts.

## Request policy

- Assistant, plan intake, and plan adjustment keep their existing 20-second total deadline; live-coach planning keeps 45 seconds.
- SDK retries are disabled explicitly. Allow at most two primary attempts, retrying only transient network, 429, or server errors with 250–499 ms jitter. OpenAI `Retry-After` takes precedence; if it cannot fit the original deadline, skip the retry rather than wait beyond the deadline. A timeout proceeds to the alternate rather than retrying the same model.
- Assistant/live-coach `AI_FALLBACK_VALIDATED=true` enables `AI_FALLBACK_MODEL` (default `gemini-3.6-flash`). Leave disabled until the real output contract passes qualification. Both models use identical prompts, context, locale, and validation. Plan intake/adjustment retain their configured primary plus deterministic fallback; they are outside the model-failover qualification scope.
- With an alternate enabled, the primary gets 45% of the total deadline; the alternate gets the remaining time, with one attempt. This changes the primary timeout, not the overall deadline.
- Three transient failures within 60 seconds open a per-process, per-model circuit for 30 seconds; one subsequent probe can close it. Instances do not share circuit state. This is overload protection, not a capacity guarantee.
- Terminal failure retains existing product fallbacks. Live-coach reviewed workout instructions remain available when generation fails. Model failover does not bypass output validation or safety decisions.

## Qualification

Run the compiled `dist/scripts/checkAIReliability.js` as a temporary Cloud Run job using the API runtime identity, the global Vertex endpoint, zero job retries, and a 30-minute task timeout. No database or runner data is needed.

Environment:

```text
GEMINI_VERTEX_PROJECT_ID=outbound-494602
GEMINI_VERTEX_LOCATION=global
AI_RELIABILITY_MODELS=gemini-3.8-flash,gemini-3.6-flash
AI_RELIABILITY_ROUNDS=3
```

For an image containing this revision:

```sh
gcloud run jobs create outbound-ai-reliability --project=outbound-494602 --region=us-central1 \
  --image="$CANDIDATE_IMAGE" --service-account=outbound-api-runtime@outbound-494602.iam.gserviceaccount.com \
  --command=node --args=dist/scripts/checkAIReliability.js \
  --set-env-vars=GEMINI_VERTEX_PROJECT_ID=outbound-494602,GEMINI_VERTEX_LOCATION=global \
  --max-retries=0 --task-timeout=1800s
gcloud run jobs execute outbound-ai-reliability --project=outbound-494602 --region=us-central1 --wait
# Read ai_reliability_sample / ai_reliability_summary logs before cleanup.
gcloud run jobs delete outbound-ai-reliability --project=outbound-494602 --region=us-central1 --quiet
```

The script interleaves the actual assistant and full half-marathon planner for English, Simplified Chinese, and Spanish, three rounds, with three seconds between requests. It disables retries, fallback, and circuits within that process (`AI_RELIABILITY_BENCHMARK=true`); never enable that flag on the API service. Runtime schema, supported moments, and exact workout instruction coverage remain enforced. Logs contain metadata only. Successful schema validation is not a complete language or coaching-quality review.

Set `AI_RELIABILITY_MODE=failover` and `AI_FALLBACK_MODEL=gemini-3.6-flash` in a separate job execution to force a nonexistent primary and verify real alternate responses through both product validators in all three languages. This checks the shared failover path, not a simulated successful response. Controlled 429/timeout checks cover the error classification. Qualification scripts return nonzero when any screening group fails.

Initial screening gates: at least 95% first-attempt success, assistant p95 ≤8 seconds, coach p95 ≤25 seconds, and a valid response for every operation/locale. Latency percentiles use successful requests only; failures are reported separately and never excluded from the success rate. This small sample cannot establish an SLA. An alternate also needs sufficient latency headroom for its reserved deadline. Use production observations over several days before concluding sustained reliability; if Gemini misses these gates, evaluate GPT with the same fixtures before selecting it. ChatGPT/Codex subscription access is not an application API credential.

## Monitoring

```sh
python3 scripts/configure-ai-monitoring.py          # preview
python3 scripts/configure-ai-monitoring.py --apply  # idempotent configure
```

The script reuses notification channels from `Outbound API 5xx errors`. It creates production-service-only log counters for generation outcomes, terminal failures, capacity errors, and successful requests exceeding the latency target. Alerts fire at two terminal failures in ten minutes or three 429/timeout attempts in five minutes, or three slow successes in ten minutes (assistant >8 seconds; coach >25 seconds). Synthetic Cloud Run jobs are excluded. New metrics may take a few minutes to become available before alert creation; rerun if metric propagation returns 404.

`ai_attempt` and `ai_generation` JSON logs include operation, model, outcome, safe failure category/status, bounded validation-failure classification, elapsed milliseconds, attempt count, and fallback usage. Inspect these to distinguish recovered errors from user-visible failures. Do not log provider error messages, prompts, response bodies, runner identifiers, or user content. These are operational events, not Firebase product analytics.

```sh
gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="outbound-api" AND (jsonPayload.event="ai_attempt" OR jsonPayload.event="ai_generation")' \
  --project=outbound-494602 --account=bruce.xia74@gmail.com --freshness=1h --limit=100 --format=json
```

## Verification record

- Backend TypeScript build and deploy-script syntax check passed.
- Controlled synthetic checks passed: one bounded retry after 429; invalid-output fallback validation; no retry on 403; fallback retains budget after timeout; circuit opens after three transient failures; failed half-open probes reopen; successful probes close; canceled probes release the lock.
- Runtime screening on 2026-10-21 used the production service identity, global Vertex, actual assistant/half-marathon prompts and validators, synthetic data, and no retries. The interleaved comparison was stopped early after clear failure; in-flight canceled calls are excluded.

| Screening | Assistant | Coach | Successful-call p95 (assistant / coach) | Decision |
| --- | --- | --- | --- | --- |
| Gemini 3.8 Flash, interleaved | 1/6 | 2/5 | 7.51s / 12.15s | Failed: six timeouts, one 429, one invalid output |
| Gemini 3.6 Flash, interleaved | 6/6 | 5/5 | 4.54s / 8.42s | Initially promising; required separate qualification |
| Gemini 3.6 Flash, separate qualification | 8/9 | 5/9 | 7.10s / 8.73s | Failed: four 429s, one invalid output |

- Safe quota diagnostics did not establish a specific small project cap; treat the cause of the observed 429s as unresolved. Do not claim a quota increase or a different provider fixes it without measurement.
- Neither model qualifies as a validated alternate. `AI_FALLBACK_VALIDATED` remains **false**. First-attempt results are screening observations, not an estimated production SLA. Plan-intake/adjustment semantic behavior and real-device playback were not re-evaluated in this task.
- OpenAI access probe with the owner-supplied local credential returned HTTP 429 with `insufficient_quota` / `credit_balance_exhausted`. The owner funded the API project; a subsequent access probe succeeded in 2.72 seconds. Local workload qualification follows separately. No OpenAI credential was copied into the repository or deployed.

GPT follow-up candidate: [GPT-6 Luna](https://developers.openai.com/api/docs/models/gpt-6-luna), using Responses structured outputs and low or no reasoning. This is a candidate for measurement, not a claim of better application reliability. The owner supplied a local credential and resolved its initial credit-balance error. The owner explicitly approved Secret Manager import and runtime access on 2026-10-20 (America/Los_Angeles); cloud qualification must pass before deployment.

Deployment: `outbound-api-00168-lb9` serves 100% of traffic with failover disabled. Its matching additive Prisma schema job completed, planning maintenance uses the same image, and `/health` returned 200. All three AI alert policies use the existing API operator channel.

## Optional GPT transport

- `gpt-*` model IDs use the [Responses API with strict structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs), identical prompt/context and product validation, low reasoning for assistant/coaching, and `store: false`. Temperature is omitted with reasoning enabled, per [migration guidance](https://developers.openai.com/api/docs/guides/latest-model/gpt-6-astra.md#migration-quickstart).
- Error bodies and output text are never logged. Billing exhaustion is classified as `quota_exhausted`, without a pointless same-model retry. A separately validated provider can recover provider-specific configuration failures.
- Local comparison loads `OPENAI_API_KEY` from the existing owner-controlled file into the child process only. It does not upload the credential or change cloud IAM. Local latency does not establish Cloud Run latency.
- Cloud evaluations mount `OPENAI_API_KEY=outbound-openai-api-key:latest` from the owner-approved secret. Deployment requires `OPENAI_API_KEY_SECRET=outbound-openai-api-key` when GPT is configured; the deploy script does not grant IAM or import keys. Production keeps its current Gemini route and failover disabled until cloud qualification passes.

Local GPT adapter checks passed: official endpoint, strict-schema mapping, low reasoning without unsupported temperature, `store: false`, output/usage normalization, incomplete-response rejection, billing-vs-rate-limit classification, same-provider billing fail-fast, server-directed retry delays within the total deadline, independent-provider recovery, and startup/deploy guards for missing credentials. No test suite was run.

## Local GPT screening (2026-10-21)

Same synthetic prompts, strict schemas, product validators, three languages and three rounds; one attempt per call, sequential and paced. These ran on the operator machine using the existing local credential, not Cloud Run. No 429s or timeouts occurred in these 36 calls.

| Model / workload | Valid responses | Successful-call p95 | Screening result |
| --- | --- | --- | --- |
| GPT-6 Luna / assistant | 9/9 | 2.40s | Passed |
| GPT-6 Luna / coach | 7/9 | 10.43s | Failed: two Spanish outputs rejected by product validation |
| GPT-6.1 Sol / assistant | 9/9 | 4.57s | Passed; assistant-alternate candidate |
| GPT-6.1 Sol / coach | 9/9 | 24.33s | Passed |

Proposed route: `APP_AI_MODEL=gpt-6-luna`, `GEMINI_LIVE_COACH_PLANNER_MODEL=gpt-6.1-sol` (the existing planner setting accepts GPT IDs), and `AI_FALLBACK_MODEL=gpt-6.1-sol`. With failover enabled after cloud qualification, assistant uses Sol as its alternate. Coaching deduplicates the identical primary/alternate model and retains reviewed deterministic guidance if generation fails; Luna is not qualified as a coach alternate. Training-plan intake/adjustment remains on its current configured Gemini primary with deterministic fallback.

The owner approved storing the supplied credential as `outbound-openai-api-key` and granting secret-scoped `roles/secretmanager.secretAccessor` to `outbound-api-runtime@outbound-494602.iam.gserviceaccount.com`. Version 1 was imported via stdin without printing the key or copying it into the repository. Cloud qualification uses that reference; production model changes remain conditional on the workload and failover gates. This explicit approval resolved the earlier automatic-review rejection of persistent credential access.

GPT-capable source image built successfully: `us-central1-docker.pkg.dev/outbound-494602/cloud-run-source-deploy/outbound-ai-reliability@sha256:7b0dbaa84dc447d3310e9bc068bbf36054dc53ec7f393cd1194bf11ac39a6ce9`. It contains source and dependencies only, with no OpenAI credential. Backend compile, controlled adapter/policy checks, configuration/deploy guards, and deploy-script syntax checks passed.

Latest funded-key [rate-limit response headers](https://developers.openai.com/api/docs/guides/rate-limits#rate-limits-in-headers) on 2026-10-21 reported Luna at 30,000 requests/minute and 180M tokens/minute, and Sol at 15,000 requests/minute and 40M tokens/minute. Sol's earlier probe reported 5,000 / 1M before the later snapshot; quotas are not fixed availability guarantees. Project-token limit headers were absent in both probes. These are account-specific observations, not model-wide promises or a load test.


## Cloud GPT screening (2026-10-20 America/Los_Angeles)

The approved candidate ran with the production runtime identity and Secret Manager reference. Synthetic fixtures, validators, locales, first-attempt policy and gates matched the local screening. No runner data was used. All 36 direct calls completed without rate limits or timeouts.

| Model / workload | Valid responses | Successful-call p95 | Direct screening |
| --- | --- | --- | --- |
| GPT-6 Luna / assistant | 9/9 | 3.06s | Passed |
| GPT-6 Luna / coach | 9/9 | 13.48s | Passed this run; earlier local 7/9 still disqualifies coach routing |
| GPT-6.1 Sol / assistant | 9/9 | 3.95s | Passed |
| GPT-6.1 Sol / coach | 9/9 | 24.21s | Passed direct run; additional cloud rejection below blocks promotion |

A separate forced-primary-404 run exercised the real Sol alternate: assistant 3/3, p95 5.22s; coach 2/3, successful-call p95 21.91s. Spanish coaching failed `product_validation` after 23.29s. No output text was logged, so the exact rejected phrase was not inspected. The failover job correctly returned failure. The direct job passed, but that does not erase the additional validation failure: Sol coaching was 11/12 across cloud calls (91.7%), below the 95% gate. Luna assistant and Sol assistant fallback passed their workload checks; the proposed complete split did not qualify.

**Deployment decision:** no production model or traffic changes. Keep revision `outbound-api-00168-lb9` and failover disabled; do not promote the split based only on the passing direct run. Improve the coaching prompt while preserving its contract, then requalify before rollout. No prompt optimization was included in this credential/qualification task. The approved secret remains available for that follow-up. Both temporary qualification jobs were removed after collecting metadata. These small samples do not establish sustained availability or an SLA.

Verification: documentation diff check passed; no application source changed and no test suite ran. Real-device playback was not verified.
