# Snote Flutter app

## Run locally

Set the optional cloud configuration when you want account sync:

flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...

For Google OAuth on a native build, also set:

--dart-define=SUPABASE_REDIRECT_URI=com.snote://auth-callback

Without Supabase variables, Snote remains a local-first notebook.

## Supported targets

Android, iOS, macOS, Windows, Linux and Web.

## Release builds

Platform workflows generate native project files, launcher icons and release artifacts in GitHub Actions. iOS builds in CI are intentionally unsigned; App Store distribution still needs Apple signing configured by the owner.
