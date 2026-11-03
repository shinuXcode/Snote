# Snotee

Open-source, offline-first handwriting and rich-text notes for Android, iOS, Windows, macOS, Linux and Web.

**Current main promotion target:** Snotee 2.0.0 (build 97).

## Repository

- `app/` — Flutter client and local SQLite/file storage
- `website/` — multipage product showcase and downloads
- `.github/workflows/` — CI, beta and release automation

## Privacy and storage

Snotee is intentionally offline-first: notes remain on the device using SQLite and local files. No account, hosted database, Snotee server or automatic cross-device sync is required. To move notebooks between devices, use a user-controlled encrypted `.snote` backup and transfer it through a storage or sharing service you choose. The app does not pay for or operate that storage. Full-fidelity export/restore validation, especially for handwriting page and stroke files, remains a separate acceptance requirement.

## Local setup

```sh
cd app
flutter pub get
flutter run
```

For the showcase website:

```sh
cd website
npm install
npm run typecheck
npm run build
```

## Release

The release workflow builds Android, Windows, Linux, macOS, iOS (unsigned) and Web artifacts.

## License

MIT
