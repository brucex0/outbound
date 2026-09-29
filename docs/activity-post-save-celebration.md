# Activity Post-Save Celebration

Open this when implementing or changing the small celebration shown after a durable activity save.

## Product Intent

Give each saved activity a brief, personal moment of recognition. The celebration should make showing up feel rewarding without creating a points system, streak pressure, or a delay the runner cannot skip.

## Product Contract

- Show only after the activity has been durably saved locally. A failed or ineligible save never shows it.
- Present a centered, rounded activity postcard over a softly tinted full-screen background.
- Draw the saved route as a bright, rounded line when at least two route points exist. Normalize the coordinates into the postcard bounds; do not show map tiles or start/end labels. For activities without a route, use the same simple looping path on both platforms.
- Animate the route drawing from start to finish over 1.4 seconds. A small, friendly runner mascot follows the line and gives a brief wave at the end. Keep its construction simple vector geometry so both platforms can reproduce the same silhouette and colors without platform-specific emoji or system artwork.
- Show one short, warm message. V1 default: “You made time for this today.” Use the same copy for every activity; do not imply a personal record or make claims from activity data.
- Keep the post-save page open until the runner acts; do not auto-dismiss the celebration or automatically return to the main page.
- For eligible Run, Bike, Hike, and Swim activities, place the postcard and celebration message at the top of the optional stretch page. Show selectable Full-body reset (4 min), Lower-body reset (3 min), and Quick reset (90 sec) programs below it. The runner can start the selected program or choose `Done` to close the page.
- For ineligible activities, show the postcard, message, and localized `Done` action without stretch choices.
- The celebration card's route trace runs once over 1.4 seconds, then remains visible while the runner chooses what to do.
- Respect Reduce Motion / system animator duration scale: show the completed route and mascot pose without tracing, movement, or confetti. Do not play sound or haptics in V1.
- Keep user-authored content and route coordinates out of analytics. Record a bounded `activity_post_save_celebration` feature exposure and stretch funnel events with only activity type, stable routine ID, and bounded dismissal result.

## Platform Status

- iOS implements this contract first so the owner can review the combined celebration and stretch-choice experience.
- Android should match this contract after the iOS experience is approved; until then its current post-save flow is intentionally not considered parity-complete.

## Visual Direction

- Primary accent: the app’s activity orange, with a pale warm postcard surface and dark readable text.
- Route: rounded stroke, about 5 pt at the reference 360 pt card width.
- Mascot: compact, solid-color cartoon runner with circular head, rounded torso, and simple limbs; no facial detail required. Use the same orange, navy, and cream palette on iOS and Android.
- Avoid confetti, loud gradients, score counters, streaks, or achievement language in this first version.

## Acceptance Checks

- A successful save shows the postcard once; save failure and rejected short activities do not.
- The route animation, mascot pose, message, persistent page, stretch choices, and Done behavior match across iOS and Android after parity work is complete.
- Route-less/manual activities still show the same celebration with the shared decorative path.
- Reduce Motion shows a static completed card and keeps `Done` available.
- All visible text is localized in English, Spanish, and Simplified Chinese.
- Analytics sends no route, exact metrics, activity identifiers, or message content.
