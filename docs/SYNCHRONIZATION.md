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
- Schema v11 adds sync_metadata and append-only sync_operations.
- Note/folder queue mutations append journal operations in the same SQLite transaction.
- Each installation receives a persistent device ID and monotonic local sequence.
- SyncJournal exposes local status and pending operations.
- SyncTransport defines a provider-neutral encrypted-object contract.
- HTTPS WebDAV adapter supports collection discovery, bounded object listing, immutable create-only uploads and downloads.
- Google Drive adapter stores immutable encrypted objects in the user's private `appDataFolder`; it accepts a short-lived OAuth token from the host app and never stores credentials.
- Journal delivery now has atomic leases, idempotent acknowledgement, retry release and stale-lease recovery.
- Journal and WebDAV tests cover rollback, sequence order, retries, recovery, HTTPS-only URLs and object path validation.
- Settings exposes a Sync & Devices page without claiming network providers are connected.

## Remaining work
1. Connect journal leases to an encrypted change-pack builder and verified apply pipeline.
2. Implement QR-authenticated LAN pairing and transfer.
3. Add Google OAuth consent/token refresh and user-facing Drive account setup; the appDataFolder transport is implemented.
4. Add user-facing HTTPS WebDAV configuration and connection testing; the transport is implemented.
5. Add domain-specific merge for handwriting, text, folders, attachments and PDF annotations.
6. Add key recovery, device revocation, retention and garbage collection.
7. Add platform-specific best-effort background scheduling and user-facing provider setup.

## Constraints
- Never sync the SQLite database file as a unit.
- Never let multiple devices overwrite one shared manifest.
- Exchange immutable per-device change packs and content-addressed encrypted objects.
- Retain history until active devices acknowledge a safe checkpoint or the user removes a device.
- Never log note content, credentials, recovery secrets or keys.
- Revocation cannot erase plaintext already downloaded by a previously trusted device.
- Background execution is best effort and controlled by each operating system.
