# HOLD ON Build 147 — final integration candidate

Date: 2026-09-28
Base: Build146 phone-interruption candidate / Build145 UI baseline

## Newly integrated for Build147
- Phone-call interruption delayed recovery from Build146 retained (650 ms route-settle delay + staged retries).
- Intermittent external-media volume/quality issue: recording/playback session no longer opts into Bluetooth HFP; A2DP output mixing is preferred while HOLD ON remains a built-in-mic recorder.
- Playback-only gain: each memory can be listened to at 1×/2×/3×/4×/5× without rewriting the saved/original audio.
- Quiet-section cleanup: conservative long near-silent spans can be marked as excluded ranges; the result uses the existing non-destructive edit path and remains Undo/Redo/resettable.
- Photos: camera photos and exported videos are saved to the normal Photos library and also added to a `HOLD ON` album.
- Export speed: the static base card now seeds the intermediate video with two still samples instead of writing one duplicate still frame per second; final 4 fps waveform/subtitle composition and highest-quality pass are retained.

## Previously requested items verified present and intentionally retained
- Neutral monochrome lock-screen H; no app-controlled blue success highlight.
- Quick capture: H -> waveform -> check -> H, successful audio capture is not converted to a failure solely because ActivityKit visibility/start races.
- Memory list preview: larger isolated playback strip, only one preview at a time, remaining-time display, app/background transition stops playback.
- `잡은 순간` marker and jump control in list/detail/editor.
- Title: one line, full width first, auto-shrink, Aa diagonal overlay, select-all on entry, export/detail width alignment.
- Subtitle: single-screen edit, direct timeline move/trim, `나누기 / 여기부터 / 여기까지`, style sheet, select-all text editing, WYSIWYG preview/export path.
- Memory swipe delete -> 지운기억함.
- 55-minute capture warning + one-hour save-without-storage auto-cancel.
- `저장하지 않고 중단` confirmation retained.
- External-audio interruption recovery/watchdog diagnostics retained.
- Rolling voice AAC disk-write reduction retained.
- Exported video waveform motion retained so silent social-feed playback still reads as an audio memory.

## Routine behavior — important product constraint
- Routine OFF can be applied automatically while the process is alive.
- Routine ON remains notification/tap-to-ON rather than silently starting a microphone session from a suspended/terminated app. This is intentionally unchanged from the current product rule; do not mark exact background auto-ON as device-PASS without a real iPhone test.

## Verification performed here
- `Validation/verify_build147.py`: 65/65 source/static checks PASS.
- Every active Swift source file passes `swiftc -parse` syntax parsing in the available environment.
- No Xcode/iOS SDK is available in this environment, so this is NOT an Xcode compile PASS and NOT an iPhone runtime PASS.

## Required physical-device final test
1. HOLD ON ON -> receive/end a phone call -> stays/recover ON -> capture/save valid audio; repeat locked/backgrounded and twice in succession.
2. HOLD ON ON -> play video/audio in Photos/YouTube/Instagram, speaker and Bluetooth; confirm no intermittent attenuated/telephone-quality output regression.
3. Memory playback gain 1× through 5×; confirm audible increase without app crash, route loss, or destructive source change.
4. `조용한 구간 정리` on speech with pauses; confirm only intended long quiet spans turn gray, playback skips them, Undo/Redo/reset restore correctly.
5. Capture a photo after save; confirm it appears in Recents and `HOLD ON` album.
6. Export a memory video; confirm it appears in Recents and `HOLD ON` album, waveform moves, subtitles/title match preview, export time is improved.
7. Memory list/detail/editor playback: play/pause/seek, `잡은 순간`, remaining time, leave app -> playback stops.
8. Lock screen/Control Center: H -> waveform -> check -> H; no false crash/failure banner.
9. Routine OFF and ON-notification tap path once.
10. One long standby observation after the above changes before App Store submission.
