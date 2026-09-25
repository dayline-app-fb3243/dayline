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

### Combined Continue flow: production checklist

The prototype now presents one Continue button and Apple, Google, and email choices. The A/B/C email row is a design trial, not a working account resolver. Do not ship the demo Apple/Google sheets as real provider authentication. Replace them with the signed native Apple authorization and Google's official SDK; validate signed identity tokens on the server. The $99 developer membership alone does not create an account backend, Google client, SMS provider or sync.

- Create a secure account service and ownership model that binds a verified Apple/Google subject or confirmed email to one Dayline account. Do not decide that a typed email is "new" or "existing" solely on-device, and do not expose account-existence results in the public UI. Support an established account returning by the same provider, and a safe, verified recovery/linking path for a different provider.
- For email, normalize and check basic format, then send a one-time code or link to that address and verify it on the server before creating an account or revealing any data. A syntactically valid address is not proof of a real mailbox or ownership. A typo pointing to someone else's inbox must not create an account for the typist or reveal the other person's account. Let the person edit and resend, rate-limit attempts, and show a neutral "Check your email" response rather than confirming whether an account exists. Add explicit recovery and address-change verification.
- Verify phone ownership with an actual server-issued expiring SMS code; rate-limit and handle delivery failures, number changes and reused phone numbers. Never accept any six digits in production. The prototype's phone code and email code remain local demo steps.
- Persist a per-account first-setup flag on the server, separate from per-device OS permissions. Only first-time accounts need account setup. Returning accounts on a new iPhone may need the device's own permission prompts and a short contextual explanation; OS-granted permissions cannot be inherited from another phone. Existing installs should check the live authorization state and ask only for missing permissions when a feature needs them, not replay the whole onboarding unconditionally.
- Configure and test real data persistence and restoration by verified account, including local-to-account migration, attachment/media backup, logout isolation, two-device conflicts and reinstall recovery. Current local SwiftData is deleted on uninstall; Demo history is seeded sample content, not restored user data.
- Keep the simulated Google picker only in labeled prototype builds. A production Google sign-in must use the official provider surface/SDK and actual device accounts; do not imitation-clone security UI. A real Apple authorization sheet is provided by AuthenticationServices and must be tested on signed hardware.
- Keep `-demo` fixture data isolated from the empty default build, and confirm that an empty fresh install has no fabricated visits, Day score, or widget value. A seeded Demo is an illustrative few-month history, not proof of sync.

Sources for design/security decisions: Apple's Sign in with Apple HIG (https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple), Google sign-in branding (https://developers.google.com/identity/branding-guidelines), OWASP email verification guidance (https://cheatsheetseries.owasp.org/cheatsheets/Email_Validation_and_Verification_Cheat_Sheet.html), Google's email enumeration protection (https://cloud.google.com/identity-platform/docs/admin/email-enumeration-protection).

## People and sharing launch gate

- Build an account backend/server, data ownership rules, and authenticated account lookup before using user identities for sharing.
- Request Contacts permission at the point of use, import only the fields needed with consent, and match friends by verified phone/email through the backend. The app reads authorized on-device Contacts for invitations; the seeded Demo still shows sample people, and no server-side friend matching exists.
- Implement follow requests, acceptance/rejection, sharing visibility, revocation, and streak updates with an authenticated social graph. Current "Follow" and "Ask" pills only change local button state; demo friends are fixed sample values. The hide-from-my-ring toggle is local UserDefaults state, not a sharing permission.
- Replace the placeholder invite URL with a tested live destination, and verify the Messages composer on a physical device. An invite UI or local button state does not establish that any person received or accepted a request.

## Final release cleanup

- After the real account, verification, social, sync, invite, and notification services are integrated and tested, remove all seeded/demo/fake code paths from the shipping app: `DAYLINE_DEMO_BUILD`, `-demo` launch switches, sample user/accounts/people, arbitrary verification-code acceptance, simulated Google account choice, placeholder URLs and data, and preview-only mocks. Keep test fixtures isolated in test targets, not production code. Audit the built app for these paths before release.

## Public-facing support and privacy

- Publish a production privacy policy that accurately describes the actual account, location, health, photo, voice/Speech, Contacts, social sharing, analytics, retention, deletion and cloud storage behavior after services are implemented. Replace prototype-only statements and verify App Store privacy disclosures against the shipped build.
- Add an in-app link to that privacy policy and test it on a device.
- Add in-app support actions to contact David/the Dayline team and report a problem. Decide and verify the support address or destination before wiring or publishing the links; no address is assumed here.

## Native phone integrations

- Contacts permission and on-device contact selection/invitation are wired. Validate limited/full access and updates on real iPhones; implement authenticated server-side membership matching before labeling any contact as already on Dayline or enabling actual follow/share requests. Never infer membership from the phone's Contacts app.
- HealthKit reads step count and workouts with read-only authorization; when HealthKit is unavailable, Motion pedometer can provide phone steps. Test Health permissions, Watch/phone source overlap, empty/denied access, and live updates on real devices. The seeded Demo shows sample history because a fresh simulator has no steps.
- Messages composer uses `MFMessageComposeViewController` where the device can send SMS; otherwise it falls back to the system share sheet. Test the real composer, recipient and live invite destination on a physical iPhone; the simulator did not render a usable Messages composer.
- Verify voice-note capture, permission prompts, playback and Speech-framework transcription on a real iPhone. A simulator does not provide a reliable microphone or Speech engine, so CI cannot establish that transcripts work. Test successful words, denied Speech permission, silence, failure and delayed recognition; the bubble must show only an actual transcript and remain playable when no transcript exists.
