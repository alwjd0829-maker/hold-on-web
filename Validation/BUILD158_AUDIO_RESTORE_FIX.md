# Build 158 — audio restore reliability

- Adds an explicit **원본으로 복구** control in the audio editor.
- Original restore clears audio split/exclusion edits and resets playback gain to 1× while preserving the original source file.
- Restoring a selected part of a merged quiet-removal range now subtracts that segment from the excluded range instead of requiring exact range equality.
- Adds audio-edit render revisions so stale overlapping autosaves cannot overwrite a newer restore/edit result.
- Build 157 monetization and five-use free trial behavior otherwise remains unchanged.
