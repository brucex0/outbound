# Runna Training-Plan Research

Research date: 2026-11-10 (Pacific)

This summarizes Runna's public help-center descriptions of coaching and progression rules; they do not disclose the exact internal algorithms. Plan behavior also differs by plan family.

## Publicly described behavior

- **Starting fitness and progression:** Starting fitness uses running ability, current weekly mileage, longest recent run, and recent race times. Ability sets initial mileage and long-run defaults. Race plans follow a weekly mileage curve, with the weekly maximum increase determined by current mileage and a separate limit on long-run progression. Experienced runners may receive higher targets without a faster build rate. Non-distance plans use a weekly percentage based on ability and runs per week; higher frequency means a lower rate. ([How Runna builds around current fitness](https://support.runna.com/en/articles/15231838-how-does-runna-build-your-training-plan-around-your-current-fitness))
- **New, Return, and Path plans:** The article describes two weekly progression constraints, applying the more conservative one, with gradual walk-run stages toward continuous running and no pace targets. These mechanics are distinct from race-plan progression. ([How Runna builds around current fitness](https://support.runna.com/en/articles/15231838-how-does-runna-build-your-training-plan-around-your-current-fitness))
- **Paces and mileage:** Current race times determine pace targets based on current ability, rather than the desired finish time. Changing estimated race time does not change weekly mileage. ([Race time and pace targets](https://support.runna.com/en/articles/6205998-adjusting-your-estimated-race-time-and-pace-targets); [mileage calculations and adjustments](https://support.runna.com/en/articles/14666572-how-runna-calculates-your-mileage-and-how-to-adjust-it))
- **Preferences:** Available preferences can limit maximum session distances, hard sessions per week, structured long-run frequency, or difficulty. Changing preferences regenerates the plan. Which controls are available depends on plan family. ([Training preferences](https://support.runna.com/en/articles/10393191-how-to-use-training-preferences))
- **Returning after illness or a break:** “Not Feeling 100%” pauses mileage and pace progression. Runna describes a mileage cap in the first week after a break and a return long-run cap after two or more weeks without a long run. ([Injury and overtraining risk](https://support.runna.com/en/articles/15279082-how-does-runna-reduce-the-risk-of-injury-and-overtraining))
- **Pace Insights:** The feature compares prescribed and achieved paces in intervals, tempo sessions, time trials, and some long runs, including consistency. It can propose pace shifts that require user acceptance. Accepted shifts change paces while preserving workouts. The public description does not publish the thresholds. ([Pace Insights](https://support.runna.com/en/articles/14656203-what-are-pace-insights-and-how-do-they-work))
- **Recovery:** Runna describes deloads and tapers. Half marathon and longer plans, or plans lasting at least 10 weeks, have a three-week taper; shorter plans for 10 km and below have a two-week taper. Hard sessions are reduced or removed, and the long run drops from its peak; exact reduction amounts are not published. ([Recovery in a training plan](https://support.runna.com/en/articles/15272605-how-does-runna-build-recovery-into-your-training-plan))

## What the public material does not establish

It does not provide exact mileage equations, caps, ability tables, pace-conversion methods, workout-selection logic, taper reductions, or adaptation thresholds. These findings are a behavioral reference, not evidence of a faithful or exact clone. In particular, formulas such as the “10% rule,” Riegel, or VDOT should not be attributed to Runna based on these sources.

## Plainstride relevance

The descriptions may help frame behavioral comparisons for Plainstride. Exact replication would require controlled comparisons across plans and inferred approximations. This research authorizes no implementation decision.
