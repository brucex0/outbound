# Backend Release Readiness And Cost

Open this when deciding how to host the public backend, sizing the database, or estimating monthly infrastructure cost. Estimates are in USD as of August 2026 and exclude taxes, support plans, and App Store costs.

## Current Setup

- Cloud Build builds the backend container; Cloud Run hosts the Hono API in `us-central1`.
- Cloud Run currently has 1 vCPU, 512 MiB memory, concurrency 80, and a one-instance maximum.
- Prisma connects the API to the `outbound` Postgres database on a shared, zonal Cloud SQL `db-f1-micro` instance.
- Cloud Storage holds private activity photos and avatars.
- Firebase provides authentication; the API also calls an external AI provider.
- The current shape is suitable for development and light beta traffic, but it is not ready to support hundreds to thousands of active users reliably.

## Recommended Public-Launch Setup

- Keep Cloud Build and Cloud Run. A VPS would add operating work without improving the product at this stage.
- Move Outbound to its own Cloud SQL instance with dedicated CPU and memory.
- Start with a properly sized single-zone database and automated backups; add regional high availability when usage or revenue justifies it.
- Enable point-in-time recovery, deletion protection, storage auto-growth, enforced encrypted connections, and restricted network access.
- Move database and AI credentials to Secret Manager and rotate the currently configured credentials.
- Use a dedicated least-privilege Cloud Run service account.
- Remove the one-instance Cloud Run ceiling, set safe database connection limits, and add a minimum instance only if cold-start latency is unacceptable.
- Add application-level rate limits, abuse controls, health monitoring, alerts, cost budgets, and representative load tests.
- Keep project-wide Owner access limited to protected emergency administrators; use narrower roles and MFA for routine access.

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

## Cost Risks

- AI coaching and chat are the largest variable expense and may exceed the core infrastructure bill. Enforce per-user quotas, model routing, token budgets, and billing alerts before release.
- Photo storage, downloads, and live-location updates grow with engagement; apply retention and payload limits.
- Excessive request logging can become expensive. Avoid logging tokens, location payloads, health data, or full AI prompts, and configure exclusions for noisy routine traffic.
- Cloud SQL is likely to remain the largest fixed cost; Cloud Run should stay predominantly usage-based.

## Recommended Rollout

1. Rotate credentials and move them to Secret Manager.
2. Create a dedicated single-zone Cloud SQL instance with backups, point-in-time recovery, and deletion protection.
3. Configure Cloud Run autoscaling and database connection limits.
4. Add rate limits, monitoring, budget alerts, and load tests.
5. Launch at an expected baseline of $60–100 per month.
6. Enable regional database HA when downtime risk outweighs the additional $50–80 monthly cost.

Pricing references:

- [Cloud Run pricing](https://cloud.google.com/run/pricing)
- [Cloud SQL pricing](https://cloud.google.com/sql/pricing)
- [Secret Manager pricing](https://cloud.google.com/secret-manager/pricing)
- [Google Cloud Observability pricing](https://cloud.google.com/products/observability/pricing)
