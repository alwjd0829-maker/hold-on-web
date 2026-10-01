# Build156 Monetization Integration

- Base: Build155 final storage management baseline.
- Build number: 156.
- Added StoreKit 2 non-consumable Full Access product: `com.soso.holdon.fullaccess`.
- Added Google Mobile Ads SDK through Swift Package Manager.
- AdMob app ID: production app ID in Info.plist.
- Rewarded ads: Build156 deliberately uses Google's iOS rewarded TEST ad unit for TestFlight integration testing. Production rewarded unit is stored in source but not activated until the final release build.
- Free core experience remains unchanged: moment capture/save, post-save camera, card backgrounds/fonts/styles.
- Advanced editor access is gated by either one rewarded ad for that editor session or permanent Full Access.
- Video-to-Photos export is gated by either one rewarded ad for that export or permanent Full Access. Raw audio file export remains available.
- Settings includes Full Access purchase/restore entry.
- Privacy summary now distinguishes local recording data from optional AdMob data processing.
- No ATT prompt was added. Audio content is never sent to AdMob.

Before App Store release, switch `useTestAds` to `false`, re-run TestFlight sanity checks, and complete App Store privacy / AdMob privacy-message configuration as required.
