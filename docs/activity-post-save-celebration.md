# Activity Post-Save Celebration

Open this when implementing or changing the small celebration shown after a durable activity save.

## Product Intent

Give each saved activity a brief, personal moment of recognition. The celebration should make showing up feel rewarding without creating a points system, streak pressure, or a delay the runner cannot skip.

## Product Contract

- Show only after the activity has been durably saved locally. A failed or ineligible save never shows it.
- Present a centered, rounded activity postcard over a softly tinted full-screen background.
- Draw the saved route as a bright, rounded line when at least two route points exist. Normalize the coordinates into the postcard bounds; do not show map tiles or start/end labels. For activities without a route, use the same simple looping path on both platforms.
- Animate the route drawing from start to finish over 1.4 seconds. A small, friendly runner mascot follows the line. As it reaches the finish, a playful ice-cream sundae pops in with a short sprinkle burst, holds briefly, then fades away to uncover the route. Keep both illustrations simple vector geometry so both platforms can reproduce the same shapes without platform-specific emoji or system artwork.
- Show one short, warm message. V1 default: “You made time for this today.” Use the same copy for every activity; do not imply a personal record or make claims from activity data.
- Keep the post-save page open until the runner acts; do not auto-dismiss the celebration or automatically return to the main page.
- For eligible Run, Bike, Hike, and Swim activities, place the postcard and celebration message at the top of the optional stretch page. Offer two selectable, timed routines: a full-body cooldown (about 5 minutes) and a focused hip-flexor, hamstring, and glute routine (about 2½ minutes). The runner can start the selected routine or choose `Done` to close the page.
- For ineligible activities, show the postcard, message, and localized `Done` action without stretch choices.
- The celebration card's route trace runs once over 1.4 seconds, then remains visible while the runner chooses what to do.
- Respect Reduce Motion / system animator duration scale: show the completed route, mascot pose, and fully formed sundae without tracing, movement, or flying sprinkles; fade the sundae after a short pause. Do not play sound or haptics in V1.
- Keep user-authored content and route coordinates out of analytics. Record a bounded `activity_post_save_celebration` feature exposure and stretch funnel events with only activity type, stable routine ID, and bounded dismissal result.

## Platform Status

- iOS and Android show the same route celebration and, for eligible activities, place it above the optional stretch choices. Each platform uses native vector drawing and respects its system reduced-motion setting.

## Routine Content Basis

- The full-body cooldown covers glutes, hamstrings, inner thighs, calves, and quadriceps, following the movement families in the [NHS post-exercise stretch routine](https://www.nhs.uk/live-well/exercise/how-to-stretch-after-exercising/). It uses 30-second holds, the upper end of ACE's [10–30 second beginner flexibility guidance](https://www.acefitness.org/resources/everyone/blog/6499/flexibility-exercises-for-beginners/), with both sides shown as separate timed steps.
- The focused option pairs hip-flexor, hamstring, and glute stretches based on ACE's beginner examples, including its note that repetitive aerobic exercise such as running can make the hip flexor a relevant area to stretch. Each side gets a separate 20-second step.
- These are optional general-wellness routines, not personalized injury treatment or claims that stretching prevents soreness. Keep movement gentle and stop for pain or unusual discomfort.

## Visual Direction

- Primary accent: the app’s activity orange, with a pale warm postcard surface and dark readable text.
- Route: rounded stroke, about 5 pt at the reference 360 pt card width.
- Mascot: compact, solid-color cartoon runner with circular head, rounded torso, and simple limbs; no facial detail required. Use the same orange, navy, and cream palette on iOS and Android.
- Sundae: three cheerful pastel scoops in a golden waffle cone, a small cherry, and a handful of colorful vector sprinkles. Keep the burst close to the route finish and inside the postcard.
- Avoid screen-filling confetti, loud gradients, score counters, streaks, or achievement language in this first version.

## Acceptance Checks

- A successful save shows the postcard once; save failure and rejected short activities do not.
- The route animation, mascot and sundae artwork, message, persistent page, two stretch choices, and Done behavior match across iOS and Android after parity work is complete.
- Route-less/manual activities still show the same celebration with the shared decorative path.
- Reduce Motion shows a static completed card and keeps `Done` available.
- All visible text is localized in English, Spanish, and Simplified Chinese.
- Analytics sends no route, exact metrics, activity identifiers, or message content.
