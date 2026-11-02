# Snotee

Open-source, offline-first handwriting and rich-text notes for Android, iOS, Windows, macOS, Linux and Web.

## Repository

- `app/` — Flutter client and local SQLite/file storage
- `website/` — multipage product showcase and downloads
- `.github/workflows/` — CI, beta and release automation

## Privacy and storage

Snotee 2.0 is offline-first: notes remain on the device using SQLite and local files. No account or login is required. Export and local backup remain available. Cross-device cloud sync is still under development and is not advertised as production-ready until OAuth, conflict resolution, background retries and two-device restore tests pass.

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
