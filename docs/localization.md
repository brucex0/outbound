# Localization

Open this when adding or reviewing languages, user-facing copy, locale-aware formatting, translated backend content, speech, or App Intents.

## Scope

Plainstride will initially support:

- English (`en`) as the development and fallback language.
- Simplified Chinese (`zh-Hans`).
- Spanish (`es`) without a region-specific variant.

Traditional Chinese is a separate future localization (`zh-Hant`), not an automated conversion of Simplified Chinese. The first release should follow the system or iOS per-app language setting; it does not need a custom in-app language picker.

Localization covers every user-facing surface, including accessibility, system permission prompts, Live Activities, share text, generated plans, assistant and coach responses, speech recognition, and spoken coaching. User-authored content such as activity titles, biographies, and messages must remain unchanged.

## Implemented Foundation

- The Xcode project declares English, Spanish, and Simplified Chinese regions.
- `Localizable.xcstrings` contains the extracted SwiftUI and App Intent surface with Spanish and Simplified Chinese translations. Product, health, safety, coaching, and running terminology received an explicit review after machine seeding.
- `InfoPlist.xcstrings` localizes every privacy usage description.
- The Live Activity extension owns a target-specific catalog for its compact metric labels; activity names and status values are localized before entering ActivityKit state.
- `AppLanguage` provides canonical API (`en`, `es`, `zh-Hans`) and speech (`en_US`, `es_ES`, `zh_CN`) locale mappings based on the active iOS app language.
- User-facing product language uses **companion**, never **coach** or **coaching**. Simplified Chinese uses `跑步伙伴`; Spanish uses `compañero` and the informal `tú` voice. Internal legacy type and payload names may still retain `Coach` where renaming would be an unrelated migration.
- Every API request sends `Accept-Language` and `X-Plainstride-Locale`. Backend middleware normalizes unsupported or regional variants to one supported locale.
- Assistant and companion AI prompts require the requested language. Their responses identify the locale used, and deterministic companion and cycle-aware fallbacks are available in all three languages.
- Training-plan and personalization caches are tagged with their generation locale and ignored after an app-language change.
- Custom decimal formatting follows the active locale while metric/imperial selection remains independent.
- Speech recognition, speech-analysis assets, spoken coaching voices, command hints, and deterministic activity parsing support English, Spanish, and Mandarin, including localized duration and distance units.

The catalogs are product-authored translations and still require native-speaker release review, as described below. User-authored content remains unchanged.

## Resource Strategy

Use Xcode String Catalogs as the source of truth:

- `Localizable.xcstrings` for app and Live Activity interface copy.
- `InfoPlist.xcstrings` for privacy usage descriptions and other localized bundle values.
- App Intents localization resources where required by the intents metadata tooling.

SwiftUI literals such as `Text("Start Run")` can participate in automatic extraction. Plain `String` properties do not become localized merely because they are later passed to `Text`; domain display properties and helper-produced copy must use `String(localized:)` or expose a `LocalizedStringResource`.

Prefer stable semantic keys for strings with domain meaning, for example:

```swift
static let easyRunTitle = LocalizedStringResource("workout.easy_run.title")
```

English prose may remain an extraction key for small, view-local labels where it improves readability. Add translator comments for ambiguous terms, fitness vocabulary, interpolation variables, and space-constrained controls.

## Domain And Persistence Rules

Persist stable semantic values, never localized presentation:

- Store `.easy`, `.imperial`, `long_run`, and similar identifiers.
- Localize enum titles, workout labels, weekdays, effort levels, recognition names, and status text at render time.
- Do not translate user-entered activity titles, profile fields, messages, contact names, or imported provider content.
- Record the locale of cached generated prose. Refresh or regenerate that prose when the active language changes rather than presenting stale English inside a localized screen.
- Existing persisted English display strings may be reset, reseeded, or migrated to semantic identifiers because the product is pre-public release.

## Interpolation And Plurals

Whole sentences belong in the catalog. Do not concatenate translated fragments or assume English word order.

Replace manual constructions such as `"\(count) runners"` and singular/plural ternaries with catalog plural variations. Exercise at least zero, one, two, and large-number cases. Chinese generally uses one grammatical form while English and Spanish require plural handling, but all locales should use the same semantic entry.

Interpolated values must be named or documented well enough for translators to understand whether they represent a person, distance, duration, count, workout, or date. Accessibility labels need their own complete localized sentences when the visible fragments would not produce natural spoken output.

## Locale-Aware Formatting

Language, locale, and measurement preference are related but independent:

- A Chinese-language user can select miles.
- A Spanish-language user can select kilometers.
- Dates, relative dates, decimal separators, and unit placement follow the active locale.
- Sport-standard clock durations such as `42:18` may remain language-neutral.
- Unit selection continues to follow `MeasurementUnitSystem`.

Prefer Foundation format styles and `Measurement` formatting. Audit custom formatting in `Core/SessionFormatting.swift` and API display adapters for hard-coded words, decimal formats, `km`, `/km`, and English unit placement. Keep internal calculations in canonical meters and seconds.

## Backend And Generated Content

All endpoints capable of returning user-facing prose must receive a canonical locale (`en`, `es`, or `zh-Hans`). Use one consistent transport, preferably `Accept-Language` plus an explicit locale field in AI prompt context where needed.

The preferred contract boundary is:

- Backend returns semantic workout structure, identifiers, quantities, and state.
- Client localizes standard titles, workout steps, weekdays, effort levels, and status labels.
- Backend or AI generates truly dynamic explanations, assistant replies, and coach messages in the requested locale.
- Responses containing generated prose include the locale used so caching and offline behavior are deterministic.

Prompts must require the requested language while preserving proper names, numeric values, and safety meaning. The English rule-based/offline fallbacks need equivalent catalog-backed or locale-specific content so loss of network does not silently switch the experience to English.

## Speech And App Intents

Visual localization does not automatically localize voice behavior.

- Select speech-recognition locales compatible with the active app language and available on-device assets.
- Add Spanish and Mandarin vocabulary and parsing paths for deterministic activity commands, including distance and duration units.
- Select an appropriate `AVSpeechSynthesisVoice` for generated coaching locale, with a documented fallback if the exact language voice is unavailable.
- Localize App Intent titles, parameter labels, dialogs, shortcuts phrases, and invocation examples.
- Keep spoken measurement units consistent with the user's measurement preference.

Unsupported recognition or synthesis must degrade visibly and safely; it must not reinterpret a command using English-only assumptions.

## Implementation Sequence

### 1. Foundation And Core Journey

- Add `es` and `zh-Hans` to the Xcode project and create the string catalogs.
- Localize bundle permission descriptions.
- Cover authentication, simplified onboarding, Today, activity setup, live activity controls, finish/save, primary Me settings, errors, and accessibility labels.
- Convert model/helper strings encountered by these paths to localized resources.
- Add translator comments and fix layouts exposed by pseudolocalization.

### 2. Domain Correctness

- Convert all enum and fixture display properties to semantic localization keys.
- Replace manual plurals and sentence concatenation.
- Make date, number, measurement, pace, elevation, and temperature presentation locale-aware.
- Cover Together, Progress, activity detail/history, recognition, health, safety, gear, music, feedback, share copy, Live Activities, and notifications if introduced.
- Localize offline plan-library content or replace its prose with semantic content identifiers.
- Audit persistence and cached payloads for localized strings used as durable data.

### 3. Dynamic And Spoken Content

- Propagate locale through planning, personalization, assistant, weather, recognition, and coaching requests.
- Return and cache generated-content locale metadata.
- Add Spanish and Simplified Chinese prompt behavior and deterministic fallbacks.
- Localize activity-command parsing, speech recognition, speech synthesis, and App Intents.
- Validate language switching with existing local data and offline caches.

## Translation Workflow

- English source copy should be product-reviewed before translation to avoid repeatedly translating unstable text.
- Export catalogs through Xcode/XLIFF or provide `.xcstrings` directly to translators.
- Use human review by native speakers familiar with running vocabulary. Machine translation can seed drafts but is not sufficient for permission prompts, health/safety content, onboarding, or coach tone.
- Keep terminology consistent for run, workout, pace, split, effort, readiness, recovery, calibration, live sharing, and training-plan concepts.
- Review translations in the rendered app, not only in a string table.

## Verification

For each supported language:

- Build the app and Live Activity extension.
- Run Xcode pseudolocalization and inspect truncation, wrapping, navigation bars, sheets, compact controls, Dynamic Island, and accessibility output.
- Exercise onboarding through a saved activity, including permission dialogs and offline behavior.
- Check zero/one/two/large counts and interpolated sentences.
- Check metric and imperial preferences independently of language.
- Switch language with existing activities, plan caches, recognition, and profile data.
- Confirm backend responses and offline fallbacks use the requested locale.
- Validate Mandarin and Spanish command recognition and spoken coaching on a device.

## Completion Criteria

- No known system-owned screen or permission prompt falls back to English in `es` or `zh-Hans`.
- No supported primary journey contains mixed-language app-authored content.
- User-authored and imported proper-name content is preserved verbatim.
- Counts and measurements are grammatically and numerically correct.
- Cached generated prose is labeled by locale and cannot silently leak across language changes.
- Voice commands, coaching speech, App Intents, accessibility labels, and Live Activities have an explicit supported-language behavior.
- Native-speaker review is complete for both translations before release.
