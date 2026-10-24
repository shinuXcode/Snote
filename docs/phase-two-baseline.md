# Snote Phase Two — Reproducible Baseline

## Snapshot identity

- Baseline code commit: `25d1277e3b0035a8ddf51591d2651ba72ad1a77e` (main, 2026-10-24).
- Release workflow run: https://github.com/shinuXcode/Snote/actions/runs/40077529538
- Flutter version configured in CI: `3.47.3` (Linux x64 hosted runner).
- Dart version: emitted by the Flutter toolchain in the workflow log; exact standalone version string still needs to be copied into a retained run report.
- App manifest: `app/pubspec.yaml`; direct declared dependency entries: 35 including 2 Flutter SDK dependencies (33 third-party direct dependencies); 2 dev dependency entries.
- GitHub repository size shown by API: 5,310 KiB-equivalent repository-size units; this is not a release artifact measurement.

## Measured current-main release build

Source: Android build log for run 40077529538, job 120824036988.

- Release command: `flutter build apk --release`.
- Universal APK: Flutter build log reported **129.8 MB** (rounded human-readable value, not an exact byte count).
- Android artifact upload ZIP: **61,405,343 bytes**. This is a compressed Actions artifact containing the APK, **not** the APK's own byte size.
- Material Icons tree-shaking: 1,645,184 bytes down to 35,604 bytes (97.8% reduction) in this build log.
- Web artifact upload ZIP: **15,139,668 bytes**. This is the compressed Actions artifact, not the uncompressed web output directory.
- Linux artifact upload ZIP: **13,903,805 bytes**.
- Windows artifact upload ZIP: **19,623,470 bytes**.
- macOS artifact upload ZIP: **231,609,338 bytes**.
- iOS artifact upload ZIP: **29,049,522 bytes**.
- Artifact archive sizes above are retained as delivery-pipeline observations only. Do not compare these ZIP sizes directly with raw APK, AAB, app bundle, or web-directory sizes.

## CI status and known warnings

Release workflow run 40077529538 completed successfully. Android, Linux, Windows, macOS, iOS (unsigned), Web, and publish-release jobs passed. Formatting, analyzer, and tests passed in each platform job according to the step results; analyzer uses `--no-fatal-infos --no-fatal-warnings`, so a successful exit does not imply zero diagnostics.

Warnings observed in the Android job:
- Flutter warns that `pasteboard` and `pdfx` apply Kotlin Gradle Plugin and may need migration for future Flutter versions.
- Android build log includes `Caught exception: Already watching path: .../app/android`, but the build continued and succeeded.
- CI actions emit Node.js 20 deprecation warnings for some action versions.

No active failing job was reported by the completed current-main release workflow. This is not proof that there are no latent regressions; the build is a smoke/release check, not an end-to-end device regression suite. The version metadata mismatch documented in `docs/repository-dry-size-optimization.md` remains unresolved.

No measured startup time, memory profile, frame timing, handwriting latency, or PDF loading/scrolling benchmark is currently available. These require a defined device/test scenario and should not be fabricated from hosted CI timings.

## Source-size snapshot

The tracked-file inventory at commit `d734a393ccc1b231553eda9f70f585f656789bb2` counted 151 blobs:
- 83 Dart files under `app/lib/`, totaling **1,407,086 bytes** of Dart source at the inventory snapshot.
- 19 test files.
- 34 website files.
- `website/public/snote-logo.png`: 1,298,678 bytes.
- `app/lib/features/notes/editor_v2/editor_v2_page.dart`: 416,334 bytes.
- `app/lib/features/notes/note_editor_page.dart`: 296,631 bytes.
- `app/lib/features/notes/notes_home_page.dart`: 90,578 bytes.
- `app/lib/features/notes/editor_v2/editor_v2_ink_painter.dart`: 83,313 bytes.
- `app/lib/canvas_engine/widgets/snote_canvas.dart`: 57,807 bytes.
- `app/lib/canvas_engine/painters/canvas_painter.dart`: 46,660 bytes.

These are Git blob sizes, not compiled-code or runtime-size measurements.

## Added reproducible CI measurement

The Phase Two branch extends the CI smoke workflow to:
1. Build the universal release APK, per-ABI release APKs, and release AAB with Flutter 3.47.3.
2. Capture exact raw byte sizes and APK SHA-256.
3. Summarize APK ZIP entries by native-library ABI, Flutter assets, DEX, and other groups.
4. Record web output bytes and largest web files.
5. Record Dart source count/bytes and largest Dart files.
6. Count packages in `flutter pub deps --json` output and group by dependency kind when the SDK's JSON schema provides it.

The exact measurements from that enhanced workflow are pending until its CI run completes. This report deliberately separates already observed measurements from pending measurements.

## Reproducible local commands

Run from `app/` using Flutter 3.47.3 and the same platform toolchain:

```bash
flutter --version
dart --version
flutter pub get
flutter pub deps --style=compact
flutter pub deps --json > /tmp/snote-pub-deps.json
dart format --output=none --set-exit-if-changed .
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --reporter expanded
flutter build apk --release
flutter build apk --release --split-per-abi
flutter build appbundle --release
flutter build web --release
flutter build linux --release
```

For each comparison, record commit SHA, runner/OS, Flutter/Dart versions, exact command, artifact path, exact bytes, SHA-256 where applicable, and whether the build used obfuscation, shrinking, or split debug symbols. Compare the same artifact type and build flags only.

## Runtime/performance baseline protocol — not yet measured

Before changing the canvas, editor, or PDF code, define a repeatable device and scenario and record:
- cold-start and warm-start time (same device, app state, and run count);
- peak/steady-state memory under a fixed notebook workload;
- frame timing/jank during page scroll, zoom, and ink playback;
- handwriting input-to-visible-ink latency using a consistent test method;
- PDF open-to-first-page time and scrolling frame timing on a fixed local PDF;
- note persistence/reopen correctness and PDF annotation integrity.

Use Flutter DevTools timeline/memory, profile builds, and device-side recordings. Keep device model, OS, refresh rate, PDF fixture, note fixture, and sample count with the results. Until collected, these metrics remain **not measured**.
