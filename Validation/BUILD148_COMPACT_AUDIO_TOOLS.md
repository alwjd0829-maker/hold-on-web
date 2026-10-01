# Build 148 — compact audio editor tool row

Device feedback from Build147 confirmed playback gain (1×–5×), quiet-section cleanup, and HOLD ON Photos album behavior work, but the two new audio tools created a second row and pushed the editor below the visible screen.

Build148 changes only the entry layout for the four audio-edit actions:
- Split → scissors icon + “나누기”
- Exclude/restore current segment → minus/restore icon + “제외” or “복원”
- Quiet-section cleanup → muted-speaker icon + “무음 제거”
- Playback gain → speaker icon + current gain, e.g. “음량 3×”

All four controls now occupy one equal-width row with the same 42 pt control height. No scrolling was added and the long explanatory line introduced with the new tools was removed so the section does not grow vertically. Functional behavior of the four actions is unchanged. Accessibility labels retain the full Korean action names.
