# Snotee Sync architecture (beta foundation)

## Product guarantees
- Local note editing and persistence never depend on network availability.
- No Snotee-hosted server, mandatory account, or remote database.
- Sync transports are optional adapters owned/configured by the user.
- This foundation does not upload note content. Provider tiles remain disconnected until implementations pass integration and security tests.

## Existing repository findings
- Notes and folders use SQLite through SnoteDatabase.
- NoteRepository and FolderRepository maintain a coalescing sync_queue for pending entity changes.
- The app already supports encrypted notebook export/import and QR transfer.
- The production README promises local-only storage.

## Foundation added
- Schema v10 adds sync_metadata and append-only sync_operations.
- Note/folder queue mutations append journal operations in the same SQLite transaction.
- Each installation receives a persistent device ID and monotonic local sequence.
- SyncJournal exposes local status and pending operations.
- SyncTransport defines a provider-neutral encrypted-object contract.
- Settings exposes a Sync & Devices page without claiming network providers are connected.

## Next stages
1. Add tests for journal atomicity, migration from v9, duplicate handling and crash recovery.
2. Define immutable encrypted object and manifest formats.
3. Implement QR-authenticated LAN pairing and transfer.
4. Implement Google Drive appDataFolder and user-selected-folder adapters.
5. Implement WebDAV with ETag/conditional-write support.
6. Add domain-specific merge for handwriting, text, folders, attachments and PDF annotations.
7. Add key recovery, device revocation, retention and garbage collection.
8. Add platform-specific best-effort background scheduling.

## Constraints
- Never sync the SQLite database file as a unit.
- Never let multiple devices overwrite one shared manifest.
- Exchange immutable per-device change packs and content-addressed encrypted objects.
- Retain history until active devices acknowledge a safe checkpoint or the user removes a device.
- Never log note content, credentials, recovery secrets or keys.
- Revocation cannot erase plaintext already downloaded by a previously trusted device.
- Background execution is best effort and controlled by each operating system.
