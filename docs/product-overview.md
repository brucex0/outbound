# Current Product Shape

Plainstride (internally still named Outbound in targets and source paths) is an iOS fitness recording app. Login uses native Sign in with Apple verified by the Plainstride backend; Firebase is used for Analytics and Messaging when the app has a local `GoogleService-Info.plist`.

Primary flow:

1. App launches into the production `Social · Today · Me` shell, centered on Today.
2. New authenticated accounts see the simplified runner intake, editable understanding, calibration, and first-plan onboarding; completed accounts skip it.
3. Today combines an inspirational spark, one AI-adjusted workout, vertical workout detail, readiness, Quick Start, and a Together invitation.
4. Me includes a cached, server-authoritative Progress entry with matched week/month/28-day comparisons, sport-specific multi-range trends, grounded companion insights, PR history, race predictions, and recent activity stat highlights.
5. Me launches suggested sessions directly, while the bottom-row activity button quick-starts into the shared freestyle start page and returns to live sessions when one is already active.
6. During an activity, the camera/map experience uses a compact bottom status card with Pause while active, then Resume and Finish once paused; runners can invite accepted connections in app to follow precise live location, pace, distance, and heart rate and send short original voice cheers that play through the guide audio path.
7. GPS is recorded in activity/photo metadata but is not displayed in the overlay.
8. Finish stops recording and presents a motivation reflection above Save Activity. Closing the review requires confirmation before the unsaved activity is discarded, then returns to Me.
9. Save writes the activity manifest, source/gear/indoor metadata, track points, photo metadata, and JPEG files locally through `LocalActivityStore`.
10. Social is always available through authenticated, share-safe connections, groups, group runs, invitations, and activity posts; private plan and health causes remain outside social responses.
11. Me consolidates plan progress, weekly totals, learned runner insights, history, measurement settings, and optional cycle-aware guidance.
