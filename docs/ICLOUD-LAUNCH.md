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

## Account and sign-in launch gate

- Connect an email delivery service and verify one-time email codes server-side. The current local onboarding accepts any six digits and sends no email.
- Connect SMS delivery and server-side phone verification. The current local onboarding accepts any six digits and sends no text. Do not treat the locally saved number as verified or use it for real friend discovery.
- Configure a Google OAuth client and implement Google Sign-In with token verification. A local account-choice walkthrough in the seeded demo is not Google authentication; never collect Google passwords in it.
- Verify Sign in with Apple, token validation, account creation, failure and cancellation on a signed physical device with the app's registered identifier.
- Verify account deletion and migration between local demo data and real accounts before publishing. Until real services are connected, the Xcode projects are prototypes, not production authentication.

## People and sharing launch gate

- Build an account backend/server, data ownership rules, and authenticated account lookup before using user identities for sharing.
- Request Contacts permission at the point of use, import only the fields needed with consent, and match friends by verified phone/email through the backend. Current PeopleStore rows are hard-coded sample names and addresses; no real Contacts read or friend matching exists.
- Implement follow requests, acceptance/rejection, sharing visibility, revocation, and streak updates with an authenticated social graph. Current "Follow" and "Ask" pills only change local button state; demo friends are fixed sample values. The hide-from-my-ring toggle is local UserDefaults state, not a sharing permission.
- Replace the placeholder invite URL with a tested live destination, and verify the Messages composer on a physical device. An invite UI or local button state does not establish that any person received or accepted a request.
