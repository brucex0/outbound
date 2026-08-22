# Start Activity Polish Design

## Goal

Make the activity start screen feel focused and launch-ready, with a compact setup hierarchy that keeps configured values visible without competing with Start.

## Scope

Polish only the setup screen in `RecordView`. Do not change the live camera/map recording surfaces, activity persistence, or goal data model.

## Selected Direction

Use the recommended polish pass:

- Use compact wrapping goal preset chips so short labels stay small while longer labels such as `Half marathon` can use the room they need.
- Keep goal mode controls compact and stable with one-line labels.
- Reduce oversized card radius and spacing so the screen reads as a focused setup tool rather than stacked oversized cards.
- Replace the photo card, Music card, Route row, and Run options card with one horizontal setup row: Music, Route, Live Track, Shoes, and More.
- Every setup control keeps an SF Symbol, visible label, current value, and a minimum 44-point target. Configured controls use the orange selected treatment plus a checkmark so selection never depends on color alone.
- Music opens the existing authorization and quick-pick choices in a compact sheet. Route opens the existing route library entry point and reflects the prepared route. Live Track offers the default trusted contact, another enabled contact, or Off.
- Shoes is first-class. With active shoes it exposes the existing selection menu and shows the selected/default shoe. Without active shoes it opens Add Shoe and shows a dismissible, persisted one-time coachmark explaining mileage tracking.
- More contains only the lower-frequency Group Run setup and Indoor/Outdoor environment selection. Shoes is not duplicated there.
- Remove the large pre-activity photo preview. A small circular Photo launch control reuses the existing camera and captured-photo state and becomes visibly configured after capture.
- Replace the full-width Start bar with a dominant circular orange play control beside Photo. Preserve preparation, countdown, prepared-route, recording, and save semantics.
- Show transient Live Track and group-operation failures as temporary toast feedback rather than status copy inserted into the setup layout.
- Do not surface unsupported countdown or audio-guidance settings.
- Increase top breathing room enough that the title does not visually compete with the close and assistant controls.

## Validation

Run build-only compile checks. The project instruction says not to run the test suite unless explicitly requested.
