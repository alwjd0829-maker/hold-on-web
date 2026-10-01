# Build151 — background recovery + other-audio priority

Base: Build150 final test baseline.

Changes:
- HOLD ON no longer tries to fight a primary/non-mixable music/video audio session. It yields recording when iOS reports a secondary-audio silence hint, deactivates its audio session, and waits for the primary audio to end.
- When the primary audio ends, HOLD ON waits briefly, then automatically rebuilds/restarts the audio engine if the user still intended HOLD ON to remain ON.
- Existing interruption/phone-call recovery remains; recovery retries are now single-flight/cancellable to avoid repeated session activation attempts.
- If HOLD ON still cannot restore standby after staged retries and no other primary audio/interruption is active, it marks runtime standby OFF while preserving the user's desired-ON intent for foreground relaunch recovery.
- At that point, it sends one local notification: “HOLD ON이 꺼졌어요. 필요한 순간이라면 대기 모드를 다시 켜주세요.”
- No new in-app status indicator was added.
- Notification permission is requested when HOLD ON is enabled so the failure alert can be delivered.
- Build number: 151.

Physical-device checks required:
1. HOLD ON ON -> YouTube Music playback: music should not become quieter/telephone-like or fail to start because HOLD ON repeatedly reclaims the session. HOLD ON may yield temporarily.
2. Stop YouTube Music -> HOLD ON should recover automatically within a short delay.
3. Repeat with Instagram/VLLO/video playback and Bluetooth.
4. Phone call -> end call -> HOLD ON recovers.
5. Force an unrecoverable audio condition if possible -> only after retries fail, local notification appears.
6. Normal standby for several hours; confirm no spontaneous OFF.

This environment cannot perform Xcode/iPhone runtime validation.
