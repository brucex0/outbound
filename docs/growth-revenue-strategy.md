# Growth And Revenue Strategy

Open this when deciding free-versus-paid access, rewards, referrals, sponsorships, commerce placements, advertising, or monetization experiments. This is the product strategy; current entitlement mechanics remain in `docs/invitation-entitlements.md` and `docs/subscriptions.md`.

Reviewed on 2026-09-12 using current Plainstride product plans and the market references below.

## Decision

Plainstride will use a growth-first hybrid model:

- Keep the useful core broadly free so runners can build a habit, invite others, and participate socially without first becoming customers.
- Let runners experience dynamic planning and live coaching before asking them to pay. During the learning launch, favor full-feature beta access behind hard cost and abuse limits.
- Let users earn bounded Plus access through qualified referrals, healthy activity, and useful community contributions.
- Use Plus for abundant, more personalized, and higher-cost experiences rather than making the basic app unusable.
- Develop opt-in sponsorship and commerce as a complementary revenue stream, not as the sole source of funding.
- Do not interrupt workout preparation, live activity, safety guidance, or completion with interstitial advertising.

Free access is an amplifier, not a growth engine by itself. Growth must come from a repeated outcome runners value and naturally share: a trusted recommendation, an adaptive plan, a supported workout, or a meaningful social experience.

## Why Not A Hard Paywall

- A hard paywall reduces the number of runners who can experience the product, weakens referral participation, and slows learning before product-market fit.
- RevenueCat's 2026 benchmarks show hard paywalls monetize an install much better than freemium in the first 35 days, but that is a revenue result rather than evidence of broader user growth. Freemium also produces more late conversions.
- Plainstride needs enough real use to prove that adaptive guidance and trusted social loops retain runners. Optimizing early download-to-paid conversion would answer the wrong question at the learning-launch stage.
- The free tier must nevertheless deliver a complete outcome. It cannot feel like a collection of disabled controls leading to Plus.

## Why Not Pure Advertising

- Plainstride naturally creates few ad impressions. A runner may see only a start and finish surface for each workout plus a limited number of social sessions.
- Published North American banner benchmarks are generally below $1 per thousand impressions. At 16 start/finish impressions per monthly active runner, network banners would yield only a fraction of a cent per runner per month. Even 40 impressions per runner remains only a few cents at typical banner rates.
- At 100,000 monthly active runners, roughly 40 banner impressions each and a $0.35-$1.50 eCPM would produce about $1,400-$6,000 per month before considering geography, fill, seasonality, operating work, and product impact.
- Higher-paying interstitial and rewarded-video formats are a poor fit for a trusted fitness guide and would encourage Plainstride to optimize attention rather than runner outcomes.
- Dynamic planning and live audio have variable costs. Commodity ad revenue may not cover those costs for an engaged free user.
- Direct sponsorship can be worth much more than ad-network inventory, but it becomes credible only after Plainstride has a concentrated, measurable, and sufficiently large active audience.

The implication is not "no commercial content." It is to sell useful, opt-in participation and purchase intent rather than low-value attention.

## Product Access Model

### Free Core

Keep these useful without payment:

- activity recording and history
- deterministic, safety-bounded planning and adjustments
- fixed reviewed workout guidance and safety-critical cues
- progress, goals, and basic runner utilities
- trusted connections, Circles, activity sharing, events, and core social participation
- basic live location sharing and privacy controls

### Experienced Before Payment

Give every runner enough access to understand the differentiator:

- dynamic plan recommendations and adjustments
- personalized live-coaching sessions
- original live voice cheers
- selected premium progress or personalization experiences

During the learning launch, these may be fully available under server-side cost limits. Later, replace unlimited access with a meaningful recurring allowance rather than an immediate hard gate.

### Plus

Plus should mean more availability and depth:

- abundant or unlimited dynamic coaching within fair-use and safety limits
- deeper plan personalization and adaptation
- advanced progress, analysis, and recovery insights
- expanded voice, guide, or customization options when they are real sources of value
- an optional sponsor-free experience if commercial placements become material

Do not remove recorded history, safety features, social relationships, or the ability to complete a workout when access expires.

## Earned Access

Use premium access as growth currency. Award bounded Plus days, coaching sessions, or guest passes instead of cash.

Reward outcomes that create durable value:

- a referred runner completes a qualifying activity
- a new runner completes onboarding and multiple real workouts
- a lapsed runner safely returns and rebuilds a habit
- a runner makes a useful, non-spam community contribution
- a runner completes an opt-in sponsored challenge
- a runner provides approved research or high-quality product feedback

Guardrails:

- Measure activated and retained referrals, not invitations sent.
- Cap recurring rewards so they complement rather than replace Plus.
- Include rest, recovery, and flexible consistency; never reward unsafe exercise volume.
- Do not reward likes, spam, indiscriminate contact sharing, or manipulative streak maintenance.
- Keep rewards understandable: show what was earned, why, and when it expires.

The existing personal-invitation qualification and grant composition are defined in `docs/invitation-entitlements.md`.

## Sponsorship And Commerce

Prioritize formats that make the product more useful.

### Strong Fits

- Opt-in sponsored challenges with a relevant reward.
- Event and race discovery in Social.
- Destination-race hospitality, entered through an event or travel-planning context.
- Local run-club, running-store, and recovery-service partnerships.
- A user-initiated Gear area with clearly labeled affiliate or sponsored options.
- Generic sponsor support for a community event without changing organic ranking or coaching advice.

### Use Carefully

- A shoe card on start or finish can work as generic sponsorship or user-initiated shopping. Do not target it from private mileage, pace, health, readiness, or location data.
- Celebration offers can live in an optional `Celebration perks` destination. Do not have the guide unexpectedly recommend a restaurant because it observed a personal milestone.
- Sponsored results must be labeled, separable from organic recommendations, dismissible, and reportable when Apple requires it.

### Do Not Ship

- interstitials before, during, or after a workout
- advertisements inside live coaching or safety guidance
- behavioral advertising based on workout, HealthKit, route, health, cycle, readiness, or social-relationship data
- paid ranking presented as an organic recommendation
- ad SDKs whose data collection or cross-app tracking cannot be fully explained and controlled

Apple permits advertising in a HealthKit-enabled app but prohibits using HealthKit and sensitive health or fitness data for advertising or behavioral targeting. Plainstride should use privacy-preserving contextual placements and avoid building its model around App Tracking Transparency consent.

## Rollout

### 1. Learning Launch

- Optimize for 25-50 retained runners, not ad revenue or paywall conversion.
- Offer the complete differentiating experience under per-user AI quotas, abuse controls, and a global spend ceiling.
- Ship no third-party advertising SDK.
- Measure whether runners complete two activities, return for another recommendation, invite a qualified friend, and describe a benefit they would miss.

### 2. Retention And Referral Fit

- Keep the free core permanent.
- Introduce a recurring dynamic-feature allowance only after actual per-runner cost is known.
- Test earned access against a conventional time-limited trial.
- Ask for referrals only after a runner experiences a successful outcome.

### 3. Hybrid Monetization

- Offer Plus for abundant and deeper dynamic experiences.
- Introduce one opt-in sponsored challenge or event partnership before adding passive ad inventory.
- Test Gear or event commerce only where users already have purchase intent.
- Keep paid and sponsored surfaces operationally independent so either can be disabled without weakening the free product.

### 4. Scale

- Build a direct sponsorship package only after Plainstride can show audience concentration, active-runner reach, challenge completion, brand-safe measurement, and repeatable campaign operations.
- Consider broader marketplace or hospitality partnerships only where local inventory is dense enough to be useful.
- Do not increase ad load merely to compensate for weak retention.

## Scorecard

Judge growth before monetization:

- onboarding completion
- first recommended workout started and completed
- two qualifying activities within the first seven days
- retained runners at days 7, 30, and 90
- percentage of retained runners who invite one appropriate person
- invitation-to-activated-runner conversion
- organic share or invitation contribution to new activated runners

Judge monetization without losing trust:

- AI and audio cost per activated and retained runner
- dynamic-feature allowance exhaustion and earned-access usage
- free-to-Plus conversion after a demonstrated outcome
- Plus retention and revenue per install
- sponsored-challenge opt-in and completion
- offer dismissal, hide, and complaint rates
- sponsor or affiliate revenue per active runner
- retention and workout completion before and after each commercial experiment

Do not adopt an experiment that raises short-term revenue while materially reducing workout completion, qualified referrals, retention, trust, or privacy.

## Decision Gates

- Keep full-feature beta access while the primary uncertainty is product value and variable cost remains bounded.
- Introduce allowances when cost per engaged free runner becomes material or abuse appears, not simply because subscription plumbing exists.
- Expand Plus when retained users repeatedly request more availability or depth.
- Sell direct sponsorship when the audience can deliver a credible campaign outcome; do not promise scale before it exists.
- Reconsider the model if sponsor and commerce revenue per active runner becomes large and repeatable enough to subsidize dynamic features without increasing ad pressure.

## Market References

- [RevenueCat, State of Subscription Apps 2026 — Health & Fitness](https://www.revenuecat.com/state-of-subscription-apps-2026-health-and-fitness)
- [Sensor Tower, State of Mobile Health & Fitness Apps 2025](https://sensortower.com/blog/state-of-mobile-health-and-fitness-in-2025)
- [Mistplay, mobile ad eCPM benchmarks](https://business.mistplay.com/resources/mobile-ads-ecpm)
- [Strava Business, sponsored challenges and segments](https://business.strava.com/resources/advertising-strava)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple, protecting HealthKit user privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)

These sources are directional rather than forecasts for Plainstride. RevenueCat describes subscription apps using its platform, ad benchmarks vary by country, platform, format, fill, and season, and Strava publishes selected campaigns from a much larger audience. Plainstride's own cohort behavior and unit economics remain authoritative.
