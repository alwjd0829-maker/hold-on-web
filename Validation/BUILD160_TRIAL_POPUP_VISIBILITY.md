# Build 160 — Free Trial Popup Visibility

Build number remains 160 by request. This revision is based on the phone-recovery Build 160 candidate.

## Change
- Replaced the small bottom toast for premium free-trial remaining uses with a prominent system alert.
- The alert appears before consuming a free use, so the first premium entry clearly shows 5 uses remaining, then 4, 3, 2, 1 on later entries.
- A free use is consumed only when the user taps `무료로 사용`; cancelling does not consume a trial use.
- On the last free use, the alert explicitly says that the next premium use requires a rewarded ad or Full Access.
- After all five uses are consumed, the existing rewarded-ad / Full Access paywall is unchanged.

## Unchanged
- Build number: 160
- Phone interruption recovery changes from Build 160
- Production AdMob IDs
- StoreKit Full Access
- Audio restore/autosave fixes
- Five-use combined premium trial policy
