# Build146 candidate — phone-call interruption recovery

Scope intentionally limited to the Build145 phone-call regression observed on-device.

Changes:
- Preserve desired HOLD ON state when an AVAudioSession interruption begins/ends.
- Do not immediately rebuild AVAudioEngine at `interruptionEnded`; wait 650 ms for the input route to settle, then recreate the engine.
- Keep the existing staged recovery retries as fallback.
- Cancel pending interruption recovery if the user explicitly turns HOLD ON off.
- Add diagnostics event `interruptionEnded` and distinct recovery reason `interruptionEndedDelayed`.

No UI, memory-card, subtitle, export, routine, quick-control, or rolling-buffer product behavior was intentionally changed.

DEVICE CHECK REQUIRED:
1. HOLD ON ON -> receive normal phone call -> end call -> HOLD ON should stay ON and microphone should recover automatically.
2. Repeat with app backgrounded/locked.
3. Repeat twice in succession.
4. After recovery, use 잡기 -> 저장 and confirm exactly one memory with valid audio.
5. Confirm no iOS crash banner / in-app crash warning.
