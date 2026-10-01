# HOLD ON Build 149 — upload number fix

App Store Connect rejected the previous upload because the archive reported bundle version 147, while 147 had already been uploaded.

This candidate preserves the Build148 compact-audio-tools source and changes the Xcode project build number to 149 for all four build configurations. Codemagic preflight is also pinned to 149 so a stale/mismatched project version fails before archive/publish.
