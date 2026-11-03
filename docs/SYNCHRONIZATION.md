# Snotee Sync architecture (hybrid-sync foundation)

## Product guarantees
- Local note editing and persistence never depend on network availability.
- No Snotee-hosted server, mandatory account, or remote database.
- Sync transports are optional adapters owned/configured by the user.
- No provider is connected and no automatic cross-device sync is enabled by this foundation branch.
- Remote storage must receive encrypted immutable objects only.

## Existing architecture
- Notes, folders, pages and attachment metadata use SQLite through SnoteDatabase.
- NoteRepository and FolderRepository maintain a coalescing sync_queue for pending entity changes.
- SyncJournal records per-device monotonically sequenced operations.
- Google Drive and HTTPS WebDAV adapters implement immutable object transport.
- Google Drive OAuth sign-in is wired through google_sign_in 7.x on Android, iOS and macOS; the adapter requests only the Drive appDataFolder scope and obtains SDK-managed access tokens on demand.
- Manual notebook export/import uses AES-256-GCM and a password-derived key.

## Implemented in this branch
- Schema v12 adds durable retry scheduling to journal operations.
- Schema v13 adds per-device remote cursors, applied-pack de-duplication and a conflict ledger.
- Attachment create, cover metadata update, move and delete mutations append journal operations in the same SQLite transaction as their metadata changes.
- Permanent note purge and expired-trash cleanup journal attachment/page tombstones and note purges before deleting rows.
- Journal delivery supports atomic leases, capped exponential retry backoff, active lease renewal and expired-lease recovery.
- SyncChangePack defines a versioned immutable snapshot/delta payload and encrypts its manifest and operation payload using AES-256-GCM.
- SyncDeviceKeyStore stores a local 256-bit key through FlutterSecureStorage. This is local key storage only; it does not yet establish a shared multi-device key.
- SyncObjectIntegrity collects a bounded encrypted object and verifies exact byte length and SHA-256 before returning the bytes to the caller.
- SyncCheckpointStore provides an atomic transaction boundary for remote domain writes, applied-pack de-duplication and source-device cursor advancement.
- Conflict revision records can be persisted and resolved, but no merge algorithm or conflict UI is connected yet.
- Home branding uses the shared 512×512 PNG master in the mobile header, desktop header, drawer and empty workspace. The app and website copies are byte-identical.

## Required integration work before enabling sync
1. Build entity snapshot and delta serializers that include all note, folder, page, stroke, attachment, cover, PDF annotation, bookmark, sticker, template, favorite and settings data.
2. Capture attachment/stroke bytes into independently verifiable chunks; reconcile file and SQLite lifecycle safely.
3. Connect journal lease claim, pack construction, AES-GCM encryption, upload, remote discovery, bounded download verification, decryption and atomic application into one cancellable orchestration engine.
4. Persist operation-level deduplication and vector-clock/revision metadata across devices.
5. Implement deterministic merge rules for non-overlapping changes and preserve both revisions when automatic merge is unsafe.
6. Implement manual conflict-resolution UI and safe note-delete/edit and folder-move conflict behavior.
7. Add shared-key QR pairing, key exchange/recovery/rotation/revocation and device management.
8. Configure platform OAuth client IDs and test Google consent, token expiry/reconnect and revocation on real devices. The native Google Sign-In SDK manages native access-token renewal; the app does not receive or persist a refresh token. A server-managed refresh-token flow for unattended/background sync is not included. Add Drive resumable uploads and race-safe collision handling.
9. Add WebDAV settings, secure credentials, capability discovery and scalable listing.
10. Implement authenticated local-network discovery/transfer and WebRTC signaling/data channels only after the common change-pack protocol is stable.
11. Add encrypted full/incremental backup, restore validation, background scheduling and metered/battery-aware policy.
12. Run multi-device Android/Windows/Web tests, crash/offline/corruption scenarios and large-library performance benchmarks.

## Google Drive OAuth setup (beta)

The beta uses the official google_sign_in 7.2.x plugin. Authentication is separate from Drive authorization. Snotee requests only:

`https://www.googleapis.com/auth/drive.appdata`

This scope is for the app's private Drive appDataFolder; it does not grant access to the user's ordinary Drive files. The OAuth service is in `app/lib/features/sync/google_drive_oauth_service.dart`, and the transport receives an access-token provider rather than persisting a bearer token.

### Google Cloud configuration

1. Open [Google Cloud Console](https://console.cloud.google.com/), create/select a project, and enable **Google Drive API**.
2. Configure the OAuth consent screen (branding, support email, developer contact). While the app is in Testing, add each tester's Google account under Test users.
3. Create an **Android OAuth client** using the beta package name `com.snote.snote.beta` and the SHA-1 certificate fingerprint for each signing identity you will distribute (debug, locally signed release, and Google Play app-signing certificate if applicable).

   **Important beta CI limitation:** `.github/workflows/beta.yml` currently generates a new temporary signing keystore on every run. Its SHA-1 therefore changes between beta APKs, so one Android OAuth client cannot reliably authorize all CI beta releases. For repeatable beta OAuth, create one persistent beta keystore, keep it outside Git, configure it as GitHub Actions secrets, and update the signing step to use that keystore on every run. Until that is done, use a locally signed build with a stable keystore for OAuth testing; do not register a one-run CI fingerprint as the permanent identity.
4. Create an **iOS OAuth client** using the exact iOS bundle identifier. Add its reversed client ID as a URL scheme in `ios/Runner/Info.plist` (URL Types).
5. Create a **Web application OAuth client ID**. The Android SDK uses this as its `serverClientId`; do not use the Android client ID in that field.
6. Supply the public client IDs at build time. Do not add a client secret to Flutter code, Git, APK assets, or `--dart-define`.

Example Android build:

```bash
cd app
flutter pub get
flutter build apk --release \
  --dart-define=GOOGLE_OAUTH_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID
```

Example iOS/macOS build:

```bash
flutter build ios --release \
  --dart-define=GOOGLE_OAUTH_IOS_CLIENT_ID=YOUR_IOS_CLIENT_ID
```

The beta currently enables interactive native sign-in on Android, iOS and macOS. Web needs the Google-rendered sign-in button integration; Windows and Linux need a separate desktop OAuth/PKCE implementation and are intentionally not presented as supported by this service. For Android, verify the generated application ID and SHA-1 against the OAuth client before testing. Obtain fingerprints with `cd app/android && ./gradlew signingReport` after generating the Android runner.

### Token lifecycle and security boundary

- Tokens are requested just-in-time and passed directly to the Drive transport; they are not stored in SQLite, preferences, logs, sync packs or source control.
- The native Google Sign-In SDK is asked for a current authorization on each transport request and may renew its cached access token. If authorization is no longer available, Sync Center asks the user to reconnect.
- The Web implementation of `google_sign_in` does not refresh access tokens automatically after one hour; a fresh user authorization is required. Web sign-in UI is not yet wired in this beta.
- The plugin does not expose a durable refresh token to this app. True unattended refresh-token management requires a carefully secured backend that exchanges an authorization code and stores the refresh token, or a separate native installed-app OAuth/PKCE implementation. No client secret belongs in the app.
- Disconnect uses the SDK's disconnect operation to revoke the app's Google authorization. Revocation cannot remove encrypted data already synced to a Drive account.
- OAuth sign-in only authenticates access to the transport. It does not by itself prove that note snapshots, conflicts, attachments, or two-way sync are production-ready.
## Constraints
- Never sync the SQLite database file as a unit.
- Never let multiple devices overwrite one shared manifest.
- Exchange immutable per-device change packs and content-addressed encrypted objects.
- Never pass downloaded bytes to decryption/application before integrity verification succeeds.
- Retain history until active devices acknowledge a safe checkpoint or the user removes a device.
- Never log note content, credentials, recovery secrets or keys.
- Revocation cannot erase plaintext already downloaded by a previously trusted device.
- Background execution is best effort and controlled by each operating system.
- A local device key is not a substitute for authenticated cross-device key exchange.
- A passing build is not evidence of successful cross-device synchronization.

## Branding asset notes
The current Snotee mark is a detailed 512×512 raster illustration with highlights, gradients and texture. It is already shared byte-for-byte between the app and website. A simple SVG wrapper would only embed the same raster and would not improve resolution; a true vector master requires careful tracing/redrawing and visual comparison against the original.
