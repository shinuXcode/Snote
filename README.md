# Snote

Open-source, offline-first handwriting and rich-text notes for Android, iOS, Windows, macOS, Linux and Web.

## Repository

- app/ — Flutter client
- website/ — multipage showcase and authenticated note portal
- supabase/ — database/RLS migrations
- .github/workflows/ — CI, diagnostics and release automation

## Core behavior

Snote writes locally first. Authentication and cloud sync are optional at the client layer; once configured, queued changes synchronize against the authenticated Supabase account.

The same account can be used by Flutter clients and the web portal to browse and export cloud-synced notes.

## Local setup

Flutter:
flutter pub get
flutter run

Cloud-enabled:
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...

Website:
cd website
npm install
npm run typecheck
npm run build
npm run dev

## Release

Tag a version such as v0.3.2. The release workflow builds Android, Windows, Linux, macOS, iOS (unsigned) and Web artifacts, then publishes them to GitHub Releases.

Required GitHub Actions secrets:
- SUPABASE_URL
- SUPABASE_PUBLISHABLE_KEY

## License

MIT
