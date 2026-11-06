# iOS Input and Keyboard Behavior

Open this when adding or changing editable text, search, comments, or numeric forms.

## Policy

- Use native SwiftUI input, keyboard avoidance, and scroll dismissal. Leave `scrollDismissesKeyboard` at its automatic default unless a specific screen needs a different interaction.
- Use `FocusState` only for deliberate navigation or completion: Search performs its existing search and clears focus; Next advances to the next editable field; Done clears focus without saving; Send uses the same guarded action as its icon.
- Keep Return as a newline in multiline fields and `TextEditor`. Their existing Send, Continue, Save, or Publish action ends editing when appropriate.
- Keep numeric and phone keyboards. These lack a Return key; provide native scrolling and existing persistent navigation/form actions for completion. Hardware-keyboard Return clears numeric-field focus without saving. Native alert inputs use their alert confirmation/cancel actions.
- Do not add a global keyboard Done toolbar, overlays above the keyboard, responder-chain dismissal, or ancestor tap gestures that compete with field/control taps.
- A non-scrolling sheet may dismiss from an otherwise empty background. The Today adjustment sheet uses a background-only tap target, not a gesture on its controls.
- Preserve validation, draft contents, autocomplete, loading guards, and domain action telemetry. Keyboard Done does not implicitly save or publish.
- Use semantic keyboard types, capitalization, content types, and autocorrection settings. Usernames, codes, and email addresses must not be autocorrected.

## Audited Surfaces

The iOS audit covers all 58 text-input declarations, including reusable helpers and native alerts.

| Surface | Behavior |
| --- | --- |
| Music, route library, Groups, people, meetup-place search | Search submits through the existing action and clears focus. Autocomplete remains active during typing. Meetup-place selection and existing connection navigation already clear focus. |
| Profile and onboarding identity | Next advances through related fields; the final text field uses Done. Profile email advances to phone. Multiline bio keeps newlines. Numeric fields use their existing scrollable forms. |
| Shoes | Brand/model advances to retirement distance; selecting a catalog match ends editing. Existing Add/Cancel actions complete the sheet. |
| Comments | Keyboard Send and the paper-plane icon share a nonempty-draft guard and the existing send/failure handling. Both clear focus. |
| Assistant and plan goal composer | Return keeps newlines; their existing send action clears focus. |
| Rewards | Go and the existing redeem button use the same guarded action and clear focus. |
| Group creation, themes, notices, settings | Next moves to the next related field; final single-line fields use Done. Multiline descriptions and notices keep newlines. Existing create/publish/save actions end editing. |
| Activity creation/editing, route publishing, calorie weight | Single-line titles use Done or Next as appropriate. Existing save/publish actions clear focus. Numeric fields keep number pads and native scrolling. |
| Feedback, memory correction, legacy intake, plan constraints/success text | Multiline editing and native scroll dismissal remain unchanged; existing screen actions complete editing. |
| Activity goal editor and weight/invite alerts | Existing goal Save/Cancel clears focus and closes the sheet. Native alerts own their input and confirmation/cancel lifecycle. |
| Today adjustment note | Multiline Return; apply clears focus; tapping empty sheet background dismisses. |

Submission telemetry is defined in `docs/product-analytics.md`; it excludes input content and field identifiers.

## Verification

Build only (do not run tests unless requested):

```sh
./scripts/build-install-bruce-main.sh --build-only
```

Manual device checks remain required after keyboard changes:

- Search using both the keyboard and icon; verify results and cleared focus, including empty queries and cached results.
- Advance through identity/profile fields; verify Next reaches the intended field and Done does not save.
- Scroll a short numeric form to dismiss; verify Save/Cancel stays reachable and values remain intact.
- Add newlines to feedback, bio, notes, and assistant messages; ensure no unintended send/save.
- Send a comment by keyboard and icon; verify empty drafts do not send and the existing failed-send recovery remains available.
- Check compact devices, a third-party keyboard, hardware keyboard, VoiceOver, and large text for obstructed controls or changed focus order.

The audit and compile check do not establish device animation, keyboard geometry, or accessibility behavior.
