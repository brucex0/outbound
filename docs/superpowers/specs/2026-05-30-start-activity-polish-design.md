# Start Activity Polish Design

## Goal

Make the activity start screen feel more polished and usable, with the immediate bug fix that the selected `Custom` goal button must not wrap.

## Scope

Polish only the setup screen in `RecordView`. Do not change the live camera/map recording surfaces, activity persistence, or goal data model.

## Selected Direction

Use the recommended polish pass:

- Use compact wrapping goal preset chips so short labels stay small while longer labels such as `Half marathon` can use the room they need.
- Keep goal mode controls compact and stable with one-line labels.
- Reduce oversized card radius and spacing so the screen reads as a focused setup tool rather than stacked oversized cards.
- Make the Music card less visually heavy by using a lighter inline action row.
- Keep the orange Start button as the strongest visual action.
- Increase top breathing room enough that the title does not visually compete with the close and assistant controls.

## Validation

Run build-only compile checks. The project instruction says not to run the test suite unless explicitly requested.
