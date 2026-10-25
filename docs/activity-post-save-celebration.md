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
- Keep the post-save page open until the runner acts; do not auto-dismiss the celebration or automatically return to the main page. On iOS, Today recommendation refreshes must retain the existing recording-view identity while its fullscreen flow is visible, including recorder-idle review and post-save phases. Done rebuilds setup with the current recommendation.
- For eligible Run, Bike, Hike, and Swim activities, place the postcard and celebration message at the top of the optional stretch page. Offer a standing reset, a longer standing stretch, and an upper-body stretch. See `stretch-routines.md` for the reusable catalog/editor contract. Keep the existing floor-based lower-body and hips/hamstrings routines under `More routines · Mat options`. The runner can start the selected routine or choose `Done` to close the page.
- For ineligible activities, show the postcard, message, and localized `Done` action without stretch choices.
- The celebration card's route trace runs once over 1.4 seconds, then remains visible while the runner chooses what to do.
- Respect Reduce Motion / system animator duration scale: show the completed route, mascot pose, and fully formed sundae without tracing, movement, or flying sprinkles; fade the sundae after a short pause. Do not play sound or haptics in V1.
- Keep user-authored content and route coordinates out of analytics. Record a bounded `activity_post_save_celebration` feature exposure and stretch funnel events with only activity type, stable routine ID, and bounded dismissal result.

## Quick Sharing

- After a durable save, show Share beside Done below the celebration message, above any stretch choices. Both celebration-only and stretch-eligible activities use the same actions. On iOS, use matching capsule buttons with a 44 pt minimum height in a centered row capped at 320 pt; primary emphasis comes from Share’s fill. Use the plain localized Share label (`分享`), without an ellipsis. Preparing the card replaces the label with a spinner without changing button size. The Chinese stretch-offer layout was visually checked in the iOS simulator after a synthetic save; Android’s text-only adjustment passed Kotlin compilation. Share event names/properties and save/share behavior are unchanged.
- Share opens the existing activity-card preview with Save Image and the system share sheet. Closing either sharing surface retains the celebration and selected stretch routine. Saving and Done do not depend on sharing or backend sync.
- Card preparation disables duplicate Share taps; a preparation failure shows a temporary localized toast and allows retry. Optional referral-link failure falls back to the public invitation URL.
- Existing `activity_share_previewed` and `activity_share_action` events use `source_type=post_save`; no activity IDs, route coordinates, exact metrics, or content are emitted.
- Android uses the same Share/Done placement in both post-save layouts, returning the locally persisted activity from save directly to the existing Android card renderer and preview. The preview offers Save Image and the system share sheet without navigating to history. Preparation, image-save, and share-launch failures show localized temporary toasts and safe diagnostics.
- Verification: iOS Simulator build-only compile and Android `:app:assembleDebug` passed; no tests run. Manual device checks remain on both platforms for preview dismissal retaining the stretch choice, offline sharing, and both post-save layouts.

## Platform Status

- iOS and Android show the same route celebration and, for eligible activities, place it above the optional stretch choices. Each platform uses native vector drawing and respects its system reduced-motion setting.

## Routine Content Basis

- The standard lower-body cooldown covers glutes, hamstrings, inner thighs, calves, and quadriceps, following the movement families in the [NHS post-exercise stretch routine](https://www.nhs.uk/live-well/exercise/how-to-stretch-after-exercising/). It uses 30-second holds, the upper end of ACE's [10–30 second beginner flexibility guidance](https://www.acefitness.org/resources/everyone/blog/6499/flexibility-exercises-for-beginners/), with both sides shown as separate timed steps.
- The focused option pairs hip-flexor, hamstring, and glute stretches based on ACE's beginner examples, including its note that repetitive aerobic exercise such as running can make the hip flexor a relevant area to stretch. Each side gets a separate 20-second step.
- These are optional general-wellness routines, not personalized injury treatment or claims that stretching prevents soreness. Keep movement gentle and stop for pain or unusual discomfort.

### Standing Content Basis

- The standing heel-forward hamstring position follows the [South Tees NHS standing hamstring guidance](https://www.southtees.nhs.uk/resources/cardiac-rehabilitation-exercise-programme/); the bent-knee calf variant follows [Newcastle Hospitals calf stretch 2](https://www.newcastle-hospitals.nhs.uk/services/injury-prevention-advice-for-runners/).
- Supported standing quads and cross-body shoulders follow [Mayo Clinic basic stretches](https://www.mayoclinic.org/healthy-lifestyle/fitness/in-depth/stretching/art-20546848). Straight-knee calf guidance follows the NHS source above. Instructions are original concise adaptations; these sources do not validate this app's exact routine, drawings, or runtime behavior.
- Keep the existing general-wellness safety guidance. Titles and on-screen instructions are localized in EN/ZH/ES. New standing hamstring, bent-knee calf, and shoulder voice keys are allowlisted server-side; older cached clips are unchanged. Deploy the updated backend before relying on those new title clips; unavailable audio stays silent, while local ticks and visual timing continue. No migration/reset is needed.
- Existing stretch funnel and step events distinguish the new stable routine IDs, so starts, skips, hold-time buckets, and completions can be compared by standing/mat routine without adding personal or location data.

## Visual Direction

- Primary accent: the app’s activity orange, with a pale warm postcard surface and dark readable text.
- Route: rounded stroke, about 5 pt at the reference 360 pt card width.
- Mascot: compact, solid-color cartoon runner with circular head, rounded torso, and simple limbs; no facial detail required. Use the same orange, navy, and cream palette on iOS and Android.
- Sundae: three cheerful pastel scoops in a golden waffle cone, a small cherry, and a handful of colorful vector sprinkles. Keep the burst close to the route finish and inside the postcard.
- Avoid screen-filling confetti, loud gradients, score counters, streaks, or achievement language in this first version.

## Acceptance Checks

- A successful save shows the postcard once; save failure and rejected short activities do not.
- The route animation, mascot and sundae artwork, message, persistent page, standing choices with optional mat routines, and Done behavior match across iOS and Android after parity work is complete.
- Route-less/manual activities still show the same celebration with the shared decorative path.
- Reduce Motion shows a static completed card and keeps `Done` available.
- All visible text is localized in English, Spanish, and Simplified Chinese.
- Analytics sends no route, exact metrics, activity identifiers, or message content.

## Stretch Player Update (October 2026)

- Original lower-body choices are `Standing reset` (six 15-second holds, 1:58 including setup/transitions) and `Standing stretch` (ten 25-second holds, 4:58). Both start with straight-knee calves, bent-knee calves, then standing hamstrings, each side consecutively. The longer routine adds supported quads, then standing cross-body shoulders. No movement requires sitting, kneeling, or lying down.
- Quick requirements: no floor or equipment; support may be used for balance. Longer requirements: no floor; a stable wall/railing is required for the quad movement. The on-screen quad instruction explicitly says to skip if support is unavailable or balance is difficult. Do not suggest movable benches or unstable objects.
- Floor-based routines retain their IDs and hold sequence under expandable `More routines · Mat options`, labeled `Mat · Lower body` and `Mat · Hips & hamstrings`. Standing routines use `post_save_<sport>_standing_quick_v1` / `post_save_<sport>_standing_standard_v1`. Walking eligibility is unchanged; there is no sport-specific medical personalization.
- Remember the last routine actually started, plus a separate last standing choice, locally across sports. Outdoor/unknown-context saves default to the remembered standing choice (quick on first use), even if a mat routine was used last. Explicit indoor saves may restore any remembered routine; floor choices expand automatically when restored. Preference writes happen only on Start, never during view initialization.
- Show an expandable movement/side preview, schematic posture drawings, per-routine support/equipment requirements, and the next posture during playback. Mirror side-specific drawings. Instructions remain on screen; audio speaks only the movement name and side.
- Timing: 3-second initial setup, the catalog-defined hold, one bundled clock tick per second during the final five seconds (no spoken numbers), then a 5-second transition with `Release` and the next title. Audio occupies the transition; extend it if needed to avoid beginning a hold before the title finishes. `Start now` can bypass setup/transition. Duration labels derive from holds plus setup/transitions and are approximate because audio, pauses, and manual controls can extend them.
- Android uses explicit spacing between preview illustrations and text (16 dp), switches and labels (12 dp), and player sections (16 dp); switch rows remain single accessible tap targets. Its visible setup/transition countdown runs concurrently with title playback, one second at a time. Hold at the last preparation second if narration runs longer; never subtract elapsed speech time in a lump. Label the transition separately from the hold.
- Voice is optional. Every cue obeys mute, including clock ticks and completion/release. Clock ticks are local assets and work offline; only posture/release clips are prefetched. Optional transition sound/haptics are independent of voice. Backgrounding pauses the timer and stops playback; resume is manual.
- `POST /v1/live-coach/stretch/audio` requires authentication and accepts only an allowlisted cue key, supported locale, and voice ID. It uses the configured Google guide voice (no LLM, workout context, user text, or phone TTS). The finite server cache shares in-flight generation; rate limit is 20 requests/user/minute. This general-wellness audio is independent of live-run session entitlements.
- The stretch screen receives the selected voice from the existing guide catalog and owns one audio controller through `StateObject`. Never create a guide-settings store during stretch-view initialization: it writes defaults and restarts global audio-pack selection during SwiftUI rendering.
- Clients prefetch and cache WAVs under a versioned locale/voice/cue key. Playback is cache-only so network latency cannot consume hold time. Offline cache misses remain silent with safe diagnostics; the visual timer and controls continue. Backend rollout is required before new installations can fetch cues. Deploy the backend through the existing release process; no schema migration or database reset is needed.
- Stretch starts include bounded `control=clock_tick` to distinguish the countdown sound version. Analytics adds `post_workout_stretch_step_ended` (`held`/`skipped`) and hold-time buckets (`zero`, `under_20`, `20_to_59`, `60_plus`). Routine completion distinguishes `fully_held` from `with_skips`; reaching the last screen does not imply every hold was completed. No posture text, route, or activity identifiers are sent.
- Manual acceptance still required on iOS/Android: standing and mat routines, outdoor/indoor preference restoration, support/skip guidance, left/right drawings, all three languages, cached/uncached/offline audio, mute during playback and completion, pause/resume/background, skips through the last hold, and final-five timing without overlapping titles.

## iOS App Store Review Request

- Count successful durable saves from the recording flow starting with this implementation. Imports, edits, sync, failed saves, and ineligible saves do not count. Persist up to three local activity IDs solely to deduplicate milestone progress; no IDs enter analytics. Existing history is not backfilled.
- After the third save (or a later save if the opportunity was skipped), wait until the runner explicitly exits the celebration or optional stretch flow, then allow one second for the main surface to settle. Require an active scene, idle recording flow, and no presented modal. Backgrounding, leaving the host, or another active flow skips that opportunity; eligibility remains for a later completed workout.
- Use StoreKit’s native SwiftUI `requestReview` environment action. Persist the consumed request before calling it, once per installation across app versions/accounts. There is no sentiment question, rating target, or custom prompt. No deployment-target change, reset, or migration is needed.
- Apple controls presentation; the app cannot observe whether a prompt appeared or a review was submitted. See the analytics contract for the request-only event.
- Verification: iOS Simulator build succeeded; diff whitespace check passed. No test suite run. Source review checked durable-save ordering, both post-save exit paths, import exclusion, and request-only analytics.
- Manual verification remains required on device for first/second/third saves, relaunch persistence, Done with/without stretching, sharing dismissal, failed/discarded saves, backgrounding, and a new recording during the settling delay. Development StoreKit presentation does not prove production presentation.

### Manual Debug Trigger

- In a Debug build, open **Me → Settings → Debug → Test App Store review**, then tap **Request native review prompt**. Repeat as needed; this calls the same native StoreKit action while leaving production eligibility and request persistence untouched. It does not simulate three saves or verify post-save dismissal timing.
- To open that screen directly without sign-in, add `-OutboundDebugAppReview` to the Xcode scheme launch arguments, or run `xcrun simctl launch booted plainstride.outbound -OutboundDebugAppReview` after installing a Debug build. Remove the argument to return to the normal app.
- The screen and launch route are compiled out of Release builds. Apple controls actual presentation; TestFlight may suppress the prompt. Only `feature_exposed` with `feature=debug_app_review_request` is emitted; the production `app_review_requested` funnel is not advanced.
- Verification: Debug iOS Simulator build and diff whitespace check passed. No test suite run. The menu, native prompt presentation, and translated layout have not been exercised at runtime.

## Reusable Catalog And Customization

- The stretch session is independent of saved activities; post-save adapters supply the celebration/share header. See `stretch-routines.md` for entry-point APIs, the shared movement catalog, local per-template edits, and verification limits.
- Duration and equipment labels derive from edited content. Swimming can initially suggest upper body; remembered valid choices take precedence. Mat-containing edits appear under More routines.

- The run-routine update adds three optional After run templates with orange vector artwork. Before run is available only from independent stretch entry points, never after saving. Existing recommendations, standing/mat restoration, Share and Done ownership remain unchanged. See `stretch-routines.md#run-routines`.
