# Snote Flutter app

Snote is a local-only notebook. Notes, folders, settings and attachments stay on this device; the app has no account, login, signup, remote database or cloud-sync requirement.

## Run locally

```sh
flutter pub get
flutter run
```

## Supported targets

Android, iOS, macOS, Windows, Linux and Web.

## Storage

The app uses its local SQLite database and platform-local file storage. Export notebooks regularly if you need a portable backup.

## Release builds

Platform workflows generate native project files and release artifacts in GitHub Actions. iOS CI builds are unsigned; App Store distribution requires Apple signing.
