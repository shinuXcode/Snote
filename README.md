# Snotee

Open-source, offline-first handwriting and rich-text notes for Android, iOS, Windows, macOS, Linux and Web.

## Repository

- `app/` — Flutter client and local SQLite/file storage
- `website/` — multipage product showcase and downloads
- `.github/workflows/` — CI, beta and release automation

## Privacy and storage

Snotee is local-only in production: no Supabase, remote database, account, login, signup or cloud sync. Notes are stored on the device using SQLite and local files. Use notebook export to create portable backups. The beta workflow/version is kept separate and unchanged by this refactor.

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
