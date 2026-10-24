# Repository DRY, Architecture and Binary-Size Optimization

## Scope and safety contract

This work is isolated on `refactor/repository-dry-size-optimization`, based on `main` at the start of the audit. Do not merge until the repository CI and release-size checks pass. Do not remove dependencies based only on their names: confirm imports, transitive/plugin requirements, platform coverage, and tests first.

## Baseline snapshot

- Repository: `shinuXcode/Snote`
- Baseline branch: `main`
- Baseline commit observed: `b4dee2f176bb3233e0aa601c0d7fdf107ad39839`
- GitHub repository size reported at inspection: `5310` (GitHub repository-size unit; not a built APK size).
- Flutter application root: `app/`
- Website root: `website/`
- CI / beta / release workflows: `.github/workflows/ci.yml`, `.github/workflows/beta.yml`, `.github/workflows/release.yml`
- Flutter toolchain configured in workflows: `3.47.3`
- The release workflow builds Android, Linux, Windows, macOS, unsigned iOS, and Web.
- **Artifact-size baseline is not yet available.** It must be measured from the same release build command and runner before/after changes; repository size is not a substitute for APK/AAB or platform bundle size.

## Confirmed findings

### 1. Duplicate/stale version presentation — safe cleanup applied

The settings About tile contained hard-coded versions `Snote 0.7.0` and `1.0.0`, while the update center already uses `app/lib/core/config/app_version.dart`. The settings tile now reuses `snoteVersionName`, removing a duplicated source of version display strings.

### 2. Version metadata is inconsistent — unresolved release decision

At baseline:
- `app/pubspec.yaml`: `0.0.1+1`
- `app/lib/core/config/app_version.dart`: `1.1.0-beta.92` and build number `95`

The beta workflow derives its release tag from `app/pubspec.yaml`, while the update center reads `app_version.dart`. This is a release correctness issue, but changing either value without confirming the intended release channel could publish the wrong tag or show a misleading installed version. Resolve this in a separate, tested change once the intended version source is confirmed. Do not silently bump or downgrade release metadata.

### 3. Repeated generated Android setup — DRY candidate, not yet consolidated

CI, beta, and production release workflows each generate Flutter platform runners and then patch Android Gradle/manifest settings. There is overlapping setup logic, but the workflows have different requirements (beta app ID, screenshot capture, ML Kit, desugaring, and release packaging). Consolidation must preserve these differences and test all affected workflows; do not perform a blind text extraction.

### 4. Dependency overlap — audit required before removal

The application declares both `webview_flutter` and `flutter_inappwebview`, and both `pdf` and `pdfx`. These may serve distinct rendering, web, or export use cases. Do not remove either pair until imports, platform plugins, feature flows, and dependency-tree evidence establish that a dependency is unused and removable without losing functionality.

## Validation plan

Run from `app/`:
1. `flutter pub get`
2. `dart format --output=none --set-exit-if-changed .`
3. `flutter analyze --no-fatal-infos --no-fatal-warnings`
4. `flutter test`
5. `flutter build apk --release` and record exact artifact bytes; use split-per-ABI builds only as a separate comparison, never compare unlike artifact types.
6. Run the website typecheck/build if shared configuration or website files change.
7. Review CI results and the diff before merging.

For size comparisons, record commit SHA, Flutter version, build command, artifact path, byte count, and whether obfuscation/shrinking/symbol splitting was enabled. A reduction is accepted only when builds and tests pass and functionality is preserved.

## Status

- [x] Inspect repository metadata, current default branch, recent commits, Flutter manifest, version constants, settings page, and CI/beta/release workflow configuration.
- [x] Create an isolated refactor branch.
- [x] Remove duplicated hard-coded version labels from the settings About tile.
- [ ] Complete the file-by-file Dart/Flutter and website source audit.
- [ ] Establish release artifact-size baseline using actual builds.
- [ ] Audit dependency usage and generated platform configuration.
- [ ] Run formatter check, analyzer, tests, and all applicable release builds.
- [ ] Record before/after artifact metrics and verify CI before merge.

This document is a working audit log, not a claim that the full optimization or release validation has passed.
