# Automatic iCloud sync - launch gate

This source still runs a local SwiftData store. Do not set `DAYLINE_CLOUDKIT_ENABLED` or say the user's data is backed up until these are complete:

1. David supplies/chooses an Apple Developer team and a registered app identifier. Keep team credentials out of the repo.
2. Register the private CloudKit container, currently provisionally named `iCloud.app.dayline`, and enable iCloud/CloudKit capability for the app target and signing profile. Replace the provisional name in the guarded model configuration with the registered identifier. The widget should continue reading app-group snapshots, not writing the CloudKit database.
3. Audit the existing SwiftData schema against CloudKit's constraints, especially the unique DayScore.day attribute and stored required properties. Build a migration plan for existing local stores, journal thumbnails, and file-backed voice/video media. SwiftData mirroring alone will not copy recordings in Documents/Voice or Documents/Video, nor Photos-library originals. Include backup/restore for those files or explicitly narrow the promise.
4. Turn the compile flag on only in an appropriately signed configuration. Exercise new install, existing-store migration, offline edits, two-device sync, logout, reinstall and restore on real iPhones signed into the same iCloud account; inspect CloudKit dashboard and error logs. Do not show "Last Backup" from a local timestamp alone.
5. Only then enable Account's backup status UI and update the privacy and account copy. Current UI deliberately says "Not configured".

CI simulator builds and unsigned Xcode project zips do not prove iCloud sync.

## Other release dependencies

- Configure Google Cloud Places API and billing/restrictions for real place opening hours; the current build shows only clearly labeled demo hours or "Hours unavailable" without a key.
- Replace `PeopleStore.inviteText`'s `https://dayline.app/invite` placeholder with a live, tested invite URL/domain. Native Messages composition is wired on capable iPhones; simulator fallback may be a share sheet.
- Enroll in the Apple Developer Program (verify the current membership price and region with Apple), then supply the Team ID and CloudKit container/capabilities above.
- Verify native notification delivery, reminders, and permission persistence on a signed real device, including install/reinstall and Settings changes.
