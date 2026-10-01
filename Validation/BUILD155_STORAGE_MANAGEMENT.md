# Build155 — Storage management finalization

- Added Settings > 저장공간 관리.
- Shows HOLD ON local data size (saved memories + trash + rolling cache).
- Cleanup entry points: 오래된 기억 (30/90/365 days), 내보낸 기억, large memories first.
- Cleanup selection first moves memories to 지운 기억함; actual bytes are reclaimed when trash is emptied.
- Empty trash permanently removes rendered audio, card image, and original non-destructive source audio.
- Successful video export to Photos is tracked locally from Build155 onward via `exportedToPhotosAt`.
- Existing exports made before this tracking field cannot be reliably inferred without broader Photos read permission, so they are not auto-classified.
- Build number: 155.
