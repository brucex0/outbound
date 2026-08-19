# Backend Release Readiness And Cost

Open this when deciding how to host the public backend, sizing the database, or estimating monthly infrastructure cost. Estimates are in USD as of August 2026 and exclude taxes, support plans, and App Store costs.

## Current Setup

- Cloud Build builds the backend container; Cloud Run hosts the Hono API in `us-central1`.
- Cloud Run has 1 vCPU, 512 MiB memory, concurrency 100, scale-to-zero enabled, a one-instance ceiling, private VPC egress, and a dedicated runtime service account. This intentionally favors minimal pre-release cost over cold-start latency or horizontal capacity.
- Prisma connects to the dedicated, zonal `db-g1-small` Cloud SQL instance over private IP with a five-connection per-instance pool ceiling.
- Cloud Storage holds private activity photos and avatars.
- Firebase provides authentication; the API also calls an external AI provider.
- Database and AI values are Secret Manager references. Database credentials were regenerated during the move; the AI provider key still requires provider-side replacement and revocation after its Secret Manager migration.
- Cloud SQL has automated backups, seven-day point-in-time recovery, storage auto-growth, encrypted-only connections, no public IP, and deletion protection.
- A three-region uptime check and email-backed uptime/5xx alerts are active. A billing-account administrator must still create the monthly budget because project Owner access does not grant budget administration on the billing account.
- Application rate limits protect general API, auth, AI, and transcription traffic. They are per instance; move to a shared limiter when adversarial traffic or scale makes global enforcement necessary.
- Private photo and avatar reads redirect to 15-minute signed Cloud Storage URLs. A full external HTTPS load balancer and Cloud CDN can be added when measured media egress justifies it.
- Recovery drill completed August 18, 2026: an on-demand backup succeeded, a 01:35 UTC point-in-time clone completed, and an isolated validation job found all 10 seeded training-plan templates. Temporary drill resources were deleted afterward.

## Recommended Public-Launch Setup

- Keep Cloud Build and Cloud Run. A VPS would add operating work without improving the product at this stage, and a migration to AWS would not meaningfully change the monthly bill at this scale (see "AWS Comparison" below) — stay on GCP unless a non-cost reason emerges (existing AWS org, an AWS-only dependency, existing team AWS expertise).
- Move Outbound to its own Cloud SQL instance with dedicated CPU and memory. Don't over-provision on day one: a shared-core `db-g1-small`, or the smallest dedicated-core tier (1 vCPU / 3.75 GB), is normally enough at launch traffic. Size up only when metrics justify it.
- Start with a properly sized single-zone database and automated backups; add regional high availability when usage or revenue justifies it. Consider a read replica as a cheaper middle ground if the actual pressure is read load rather than failover risk.
- Enable point-in-time recovery, deletion protection, storage auto-growth, enforced encrypted connections, and restricted network access.
- Move database and AI credentials to Secret Manager and rotate the currently configured credentials.
- Use a dedicated least-privilege Cloud Run service account.
- Remove the one-instance Cloud Run ceiling, set safe database connection limits, and add a minimum instance if cold-start latency is unacceptable — for a consumer app with an auth flow on the critical path, a 1-2 second cold start is often noticeable enough that one warm instance (roughly $10-20/month) is worth it.
- Tune Cloud Run concurrency before scaling out horizontally: Cloud Run bills per instance, not per request, so raising concurrency (e.g., toward 80-200 concurrent requests per instance for a Hono app) is materially cheaper than adding more instances.
- Add a CDN or cached signed-URL layer (Cloud CDN, or cache headers on signed URLs) in front of Cloud Storage for photos and avatars. Serving media straight through the API is usually more expensive than caching it, and this has more cost impact than most of the IAM hardening steps below.
- Add application-level rate limits, abuse controls, health monitoring, alerts, cost budgets, and representative load tests.
- Keep project-wide Owner access limited to protected emergency administrators; use narrower roles and MFA for routine access.

## Security Hardening Checklist

Treat this as a pre-launch gate, not a nice-to-have — most items are cheap to implement now and expensive to retrofit after an incident.

1. **Credentials**: rotate every credential currently in use (DB, AI provider, any API keys), then move them to Secret Manager. Never leave them in environment variables checked into build config.
2. **Database network exposure**: restrict Cloud SQL to private IP / authorized networks only; do not leave it open to `0.0.0.0/0`. Enforce SSL/TLS on all connections.
3. **Least privilege**: give Cloud Run its own service account scoped to only what it needs (Cloud SQL client, Secret Manager accessor, Cloud Storage object access) — not a broad Editor role.
4. **IAM hygiene**: audit who has project-level Owner; restrict it to a small emergency-access group with MFA enforced. Use predefined or custom roles for day-to-day engineering access.
5. **Backups and recovery**: enable point-in-time recovery and deletion protection on Cloud SQL before launch, not after the first incident. Test a restore at least once.
6. **Rate limiting and abuse controls**: apply per-user and per-IP limits at the application layer, especially on the AI endpoints and auth-adjacent routes, before opening signups publicly.
7. **Logging discipline**: never log auth tokens, raw location payloads, health data, or full AI prompts/responses. Configure log exclusions for noisy routine traffic to control both cost and exposure.
8. **Media access**: serve private photos/avatars via short-lived signed URLs rather than public buckets or long-lived links.
9. **Dependency and container hygiene**: keep the Cloud Build pipeline pinned to scanned, minimal base images; enable vulnerability scanning on the container registry if not already on.
10. **Monitoring and alerting**: stand up health checks, uptime alerts, and error-rate alerts before launch so a failure is caught by a dashboard, not a user report.

## Monthly Cost Estimate

| Stage | Estimated monthly cost | Notes |
| --- | ---: | --- |
| Current development setup | $10–25 | Excludes AI usage and meaningful media growth. |
| Lean public launch | $60–100 | Dedicated single-zone Cloud SQL, backups, low Cloud Run usage, secrets, and basic monitoring. |
| Launch with regional database HA | $110–180 | Adds a failover database and duplicated storage/compute. |
| Hundreds to low-thousands of active users | $150–500 | Depends on request patterns, database load, media, live-location traffic, and background work. |

Typical lean-launch components:

- Dedicated single-zone Cloud SQL: about $40–65.
- Database storage and backups: about $5–15.
- Cloud Run: about $0–20 at light traffic; one warm instance can add roughly $10–20.
- Secret Manager, standard metrics, and modest logging: usually $0–5 at this scale.
- IAM hardening, application rate limiting, and database connection limits: normally no material recurring charge.

This lean-launch range is already close to the cost-optimal point for a managed-platform approach on either GCP or AWS — provider choice is not the biggest lever available (see below). The biggest lever is capping AI spend before launch, since that line item alone can exceed the entire infrastructure budget if left unbounded.

## Cost Optimization Opportunities

- **AI spend controls (highest-impact item)**: enforce per-user quotas, model routing (cheaper models for routine requests), token/response-length budgets, streaming with hard timeouts, and billing alerts before release. This is consistently the largest variable cost and the easiest one to let run away.
- **Committed use discounts**: once traffic is steady (a few months post-launch, not at day one), a 1-year Committed Use Discount on the Cloud SQL instance typically saves ~25–30% over on-demand pricing.
- **Cloud Run concurrency tuning**: prefer raising per-instance concurrency over scaling out instance count; it directly reduces the number of billed instances for the same request volume.
- **CDN/caching for media**: cache photos and avatars at the edge instead of serving every request through the API and Cloud Storage directly.
- **Storage growth alerts**: auto-growth prevents outages but not cost creep — set a budget alert tied to Cloud SQL storage so unbounded growth (e.g., from unpruned logs or orphaned media metadata) is caught early.
- **Log volume**: exclude noisy, low-value log lines (health checks, routine polling) from ingestion to control Cloud Logging cost, on top of the safety reason to avoid logging sensitive payloads.

## Cost Risks

- AI coaching and chat are the largest variable expense and may exceed the core infrastructure bill. Enforce per-user quotas, model routing, token budgets, and billing alerts before release.
- Photo storage, downloads, and live-location updates grow with engagement; apply retention and payload limits.
- Excessive request logging can become expensive. Avoid logging tokens, location payloads, health data, or full AI prompts, and configure exclusions for noisy routine traffic.
- Cloud SQL is likely to remain the largest fixed cost; Cloud Run should stay predominantly usage-based.

## AWS Comparison

Evaluated as an alternative to confirm GCP is still the right call at this stage.

**Database — Cloud SQL vs. RDS**: roughly a wash at this size. A dedicated small Cloud SQL instance runs about $40–65/month; a comparable AWS RDS `db.t4g.small` (2 vCPU / 2 GB — the smallest instance genuinely viable for production Postgres, since the `.micro` tier's 1 GB RAM becomes a bottleneck under real load) runs approximately $27.71/month Single-AZ or about $51.07/month with Multi-AZ failover, plus storage at roughly $0.115/GB-month for gp3. Totals land in the same range as Cloud SQL.

**Compute — Cloud Run vs. AWS equivalents**:
- **AWS App Runner** is the closest match to Cloud Run's simplicity (managed HTTPS, autoscaling, no cluster to run). It bills idle/provisioned memory at $0.007/GB-hour and active processing at $0.064/vCPU-hour plus $0.007/GB-hour while handling requests — a single continuously-busy 1 vCPU / 2 GB instance lands around $46–50/month. Cloud Run's true scale-to-zero (no charge while idle) makes it cheaper than App Runner at this traffic level.
- **AWS Fargate** (via ECS) gives more control but requires managing the cluster/load balancer yourself, with no built-in scale-to-zero; a 1 vCPU / 2 GB task running 24/7 costs roughly $35.74/month on-demand — cheaper than App Runner if the operational overhead is acceptable.

**Verdict**: migrating to AWS would not meaningfully change the monthly bill at this scale. Cloud Run + Cloud SQL remains at least as cheap as App Runner + RDS, while keeping the simpler GCP IAM/Secret Manager model already assumed in this plan. Not recommended unless a non-cost driver (existing AWS org, an AWS-only dependency, team AWS expertise) is present.

**Other platforms considered**: Fly.io or Render (API) with a managed Postgres add-on can undercut both Cloud Run and App Runner at very low traffic, but lack GCP/AWS's breadth of adjacent services (Secret Manager, fine-grained IAM), meaning the security checklist above would need to be rebuilt manually. A Hetzner/DigitalOcean VPS would be cheaper in raw dollars but is intentionally ruled out here, consistent with the existing call that a VPS adds operating work without improving the product for a small team.

## Recommended Rollout

1. Replace and revoke the AI provider key; Secret Manager migration alone does not invalidate the old key.
2. Have a billing-account administrator create the monthly project budget and thresholds.
3. Verify the Monitoring email channel, run the representative load smoke command, and complete a backup restore drill.
4. Review both Owner accounts for MFA and establish narrower day-to-day access roles.
5. Cap AI spend with per-user daily quotas, model routing, and token budgets before opening signups.
6. Launch at an expected baseline of $60–100 per month.
7. Enable regional database HA (or a read replica if the driver is read load rather than failover risk) when downtime risk outweighs the additional $50–80 monthly cost.
8. Once traffic is steady, evaluate a 1-year Committed Use Discount on Cloud SQL for the ~25–30% savings.

Pricing references:

- [Cloud Run pricing](https://cloud.google.com/run/pricing)
- [Cloud SQL pricing](https://cloud.google.com/sql/pricing)
- [Secret Manager pricing](https://cloud.google.com/secret-manager/pricing)
- [Google Cloud Observability pricing](https://cloud.google.com/products/observability/pricing)
- [AWS RDS pricing](https://aws.amazon.com/rds/pricing/)
- [AWS App Runner pricing](https://aws.amazon.com/apprunner/pricing/)
- [AWS Fargate pricing](https://aws.amazon.com/fargate/pricing/)
