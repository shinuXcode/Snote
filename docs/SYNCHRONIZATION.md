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
8. Add Google OAuth consent, refresh and secure token lifecycle; Drive resumable uploads and collision-safe create.
9. Add WebDAV settings, secure credentials, capability discovery and scalable listing.
10. Implement authenticated local-network discovery/transfer and WebRTC signaling/data channels only after the common change-pack protocol is stable.
11. Add encrypted full/incremental backup, restore validation, background scheduling and metered/battery-aware policy.
12. Run multi-device Android/Windows/Web tests, crash/offline/corruption scenarios and large-library performance benchmarks.

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
