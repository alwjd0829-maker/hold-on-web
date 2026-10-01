# Build 160 — phone recovery + watchdog false-positive fix

- Based on Build159 release candidate; monetization and product UI otherwise unchanged.
- Phone interruption start cancels the pending heartbeat fallback notification.
- Phone interruption end now deactivates the stale audio session, lets the route settle, recreates AVAudioEngine, and retries recovery if needed.
- Heartbeat fallback is delayed to 4 minutes and wording is non-definitive (status check), because a delayed heartbeat is not proof that the microphone stopped.
- Confirmed recovery failure still sends the definitive immediate `HOLD ON이 꺼졌어요.` notification.
- CURRENT_PROJECT_VERSION: 160.
