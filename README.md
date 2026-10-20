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

The website documentation library generates browser-viewable PDFs for the user guide, feature catalogue, open-source contributor guide, privacy and data-handling overview, permissions and authorization guide, license and third-party notices, SDK and toolchain reference, terms of use, security and disclosure guide, app overview, source-level repository audit, and notification centre/beta sync guide. Documents are source-informed references, not proof that every capability has shipped in every beta artifact. The FAQ page covers installation, offline behavior, handwriting, documents, privacy, permissions, and releases.

Legal and security PDFs are informational, not legal advice or certification. Platform permissions, cloud behavior, feature availability, signing, and supported release artifacts must be verified for the exact build and deployment.

## Website notification Control Room

- Public notification centre: `/notifications`.
- Private Control Room: `/control-room` (not linked in public navigation).
- Apply `supabase/migrations/003_website_notifications.sql` to the same Supabase project used by the website and app.
- Website public variables: `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.
- Server-only variables: `SUPABASE_SERVICE_ROLE_KEY`, `SNOTE_ADMIN_PASSWORD` (12+ characters), and `SNOTE_ADMIN_SESSION_SECRET` (32+ characters). Never use a `NEXT_PUBLIC_` prefix for secrets.
- The Flutter app imports published notices into its local inbox when Updates & notifications is opened and retries every five minutes while that screen stays open. This is in-app online sync, not OS background push. FCM/APNs delivery needs a separate implementation and platform credentials.

## Release

Tag a version such as `v1.0.0` after review and tests. The release workflow defines current platform artifacts; check each release for asset availability and signing state.

Required GitHub Actions secrets for cloud-enabled workflows:
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

## License

Snote is distributed under the MIT License. See [LICENSE](LICENSE). Third-party dependencies and bundled assets may carry separate notices.
