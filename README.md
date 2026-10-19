# Snote

Open-source, offline-first handwriting and rich-text notes for Android, iOS, Windows, macOS, Linux and Web.

## Project links

- Website: https://snote-showcase.vercel.app/
- Documentation and PDF library: https://snote-showcase.vercel.app/docs
- Frequently asked questions: https://snote-showcase.vercel.app/faqs
- Releases and downloads: https://snote-showcase.vercel.app/download
- Source repository: https://github.com/shinuXcode/Snote
- Founder / creator: Sadab
- License: [MIT](LICENSE)

## Repository layout

- `app/` — Flutter client, canvas/ink engine, local persistence, and tests
- `website/` — Next.js showcase, docs, FAQ, release download interface, and optional account portal
- `supabase/` — database schema and row-level-security migrations
- `.github/workflows/` — CI and release automation

## Core behavior

Snote is designed local-first. Authentication and cloud sync are optional at the client layer; cloud behavior requires a correctly configured Supabase project. The same account can be used by supported clients and the web portal to browse or export cloud-synced notes.

## Local development

Flutter client:

```sh
cd app
flutter pub get
flutter analyze
flutter test
flutter run
```

Cloud-enabled builds can use compile-time configuration:

```sh
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
```

Website:

```sh
cd website
npm install
npm run typecheck
npm run build
npm run dev
```

## Documentation

The website documentation library provides PDF downloads for the user guide, feature catalogue, open-source contributor guide, privacy and data-handling overview, permissions and authorization guide, license and third-party notices, terms of use, security and disclosure guide, app overview, and source-level repository audit. The FAQ page covers installation, offline behavior, handwriting, documents, privacy, permissions, and releases.

Legal and security PDFs are informational, not legal advice or certification. Platform permissions, cloud behavior, feature availability, signing, and supported release artifacts must be verified for the exact build and deployment.

## Release

Tag a version such as `v1.0.0` after review and tests. The release workflow defines current platform artifacts; check each release for asset availability and signing state.

Required GitHub Actions secrets for cloud-enabled workflows:
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

## License

Snote is distributed under the MIT License. See [LICENSE](LICENSE). Third-party dependencies and bundled assets may carry separate notices.
