# Phase Five — Release Artifact Size Audit

## Status

**In progress — baseline archive inspected; same-configuration comparison pending.** No artifact has been optimized or reduced yet. This report separates measured facts from hypotheses.

## Baseline source and build

- Repository base: `main` snapshot `25d1277e3b0035a8ddf51591d2651ba72ad1a77e`.
- Baseline workflow run: [#40078790734](https://github.com/shinuXcode/Snote/actions/runs/40078790734), commit `881592e1865474f0346d9edf4d23bd80554e5c69`.
- Flutter version declared in workflow: `3.47.3`.
- Workflow builds a release APK, Flutter web release output and Linux desktop release. It does **not** currently build an Android App Bundle (AAB) or per-ABI APKs.
- Artifact downloaded and inspected: `snote-smoke-builds`, GitHub artifact ID `12554179251`, archive SHA-256 from GitHub metadata `3e5b419cd79e30ce4df15a5c5e2f1c114c607451f0a53915bf9d079e00dbdb2c`.

## Exact measured baseline

| Measure | Value | Method / caveat |
|---|---:|---|
| Actions artifact ZIP | 76,648,181 bytes | GitHub artifact metadata and downloaded ZIP size; **not** the APK size |
| Universal release APK | 129,841,617 bytes | APK entry inside artifact ZIP |
| APK SHA-256 | `3eb18fb2a4272bcfa380198f7a6df12f8e0a2b5e49e5b18d1de374bf89d0fa31` | Recorded by baseline CI |
| APK ZIP entries | 508 | Inspected APK archive |
| Native library payload across ABIs | 126,326,464 bytes | Sum of uncompressed `lib/<abi>/*` entries; these are contained in the universal APK |
| ML Kit OCR model assets | 5,404,582 bytes | Sum of uncompressed `assets/mlkit-google-ocr-models/**` entries |
| Barcode model assets | 880,888 bytes | `assets/mlkit_barcode_models/**` |
| DEX entries | 4,628,220 bytes | Sum of uncompressed `classes*.dex` entries |
| Web output (CI directory measure) | 46,511,458 bytes | CI uses `du -sb app/build/web`; directory total includes directory-entry overhead |
| Web archive file payload | 46,511,426 bytes | Sum of 43 `web/**` file entries in the artifact ZIP; 32 bytes below directory measure |
| AAB size | Not measured | No AAB build step in the baseline workflow |
| Per-ABI APK sizes | Not measured | No split-per-ABI build step in the baseline workflow |
| Windows/macOS/Linux/iOS release artifact sizes | Not measured | Workflow smoke builds are not uploaded as comparable size artifacts |
| Device runtime performance | Not measured | Not part of artifact inspection |

## Largest measured APK entries

| APK entry | Uncompressed bytes |
|---|---:|
| `lib/armeabi-v7a/libapp.so` | 14,303,816 |
| `lib/x86_64/libflutter.so` | 13,051,424 |
| `lib/x86_64/libapp.so` | 12,911,496 |
| `lib/arm64-v8a/libapp.so` | 12,518,280 |
| `lib/x86_64/libmlkit_google_ocr_pipeline.so` | 11,626,128 |
| `lib/arm64-v8a/libflutter.so` | 11,747,864 |
| `lib/arm64-v8a/libmlkit_google_ocr_pipeline.so` | 11,064,544 |
| `lib/armeabi-v7a/libflutter.so` | 8,615,900 |
| `lib/armeabi-v7a/libmlkit_google_ocr_pipeline.so` | 6,781,940 |
| `lib/x86_64/libbarhopper_v3.so` | 5,909,280 |

These are uncompressed archive entry sizes, not incremental downloadable size estimates. Compression and duplicate/native ABI behavior affect actual download size.

## Largest web output entries

| Web file | Bytes |
|---|---:|
| `canvaskit/canvaskit.wasm` | 7,284,602 |
| `main.dart.js` | 6,899,755 |
| `canvaskit/chromium/canvaskit.wasm` | 5,428,806 |
| `canvaskit/skwasm_heavy.wasm` | 5,216,217 |
| `canvaskit/webparagraph/canvaskit.wasm` | 3,729,129 |
| `canvaskit/skwasm.wasm` | 3,593,715 |
| `canvaskit/wimp.wasm` | 3,581,677 |
| `assets/NOTICES` | 1,496,251 |

The web archive also contains multiple CanvasKit JavaScript/WASM variants and symbol files. Do not delete or exclude them until the Flutter engine's runtime selection, deployment needs, and debugging workflow are verified.

## Findings and proposed investigations

### 1. Universal APK contains three ABIs
- **Category:** Binary size / release distribution.
- **Evidence:** APK archive includes native libraries for `arm64-v8a`, `armeabi-v7a`, and `x86_64`.
- **Interpretation:** This is expected for a universal APK. Separate ABI APKs can be smaller for individual users, but do not make the universal APK smaller. An AAB may let Play deliver matching native libraries.
- **Safe next step:** Add a separately measured AAB and/or split-APK CI experiment without replacing the current release artifact. Compare exact size and test install/runtime compatibility before changing distribution policy.

### 2. ML Kit OCR and barcode components are significant
- **Category:** Binary size / dependency review.
- **Evidence:** 5,404,582 bytes of OCR model assets, 880,888 bytes of barcode models, and ML Kit native libraries across all three ABIs.
- **Interpretation:** These are likely feature dependencies, not proven dead weight. Removing or replacing them could break OCR, scanning, or supported languages.
- **Safe next step:** Trace the actual OCR/barcode APIs, language/model configuration, and plugin/transitive dependency graph. Only consider optional/lazy delivery if the package and product requirements support it.

### 3. Flutter native runtime and app AOT code dominate APK contents
- **Category:** Binary size.
- **Evidence:** Large `libflutter.so` and `libapp.so` entries across three ABIs.
- **Interpretation:** These are expected runtime/AOT components; archive sizes alone do not justify stripping or replacing them.
- **Safe next step:** Keep release tree shaking enabled by Flutter's release build; measure an AAB/split APK and inspect generated Gradle release settings before proposing any additional shrinker configuration.

### 4. Web output includes several CanvasKit/WASM variants and symbol files
- **Category:** Binary size / web delivery.
- **Evidence:** Multiple large WASM and `.symbols` files are present in the generated web artifact.
- **Interpretation:** Some files may be conditionally selected by the Flutter engine or retained for debugging. Their presence in the output does not prove every file is fetched by every client.
- **Safe next step:** Inspect the Flutter 3.47.3 loader/runtime selection and hosting/cache configuration. Compare transfer size and smoke-test browser rendering before excluding anything.

### 5. Current website package is a separate Next.js application
- **Category:** Scope separation.
- **Evidence:** `website/package.json` declares Next.js, React, and React DOM; the Flutter web build is separately emitted under `app/build/web`.
- **Interpretation:** Do not mix Next.js showcase bundle size with Flutter app web-output size.
- **Safe next step:** Report them as separate products if the website's own production artifact size is later measured.

## Dependency cleanup currently under validation

Phase Four PR #35 removes direct `webview_flutter` from `app/pubspec.yaml` after repository-wide searches returned no import or `WebViewWidget` call sites. `flutter_inappwebview` remains and has a real call site. This audit does not yet prove any APK/web size reduction; compare only after the new workflow finishes.

## Next validation gates

1. Wait for the Phase Four workflow to complete and inspect all failed steps, if any.
2. Capture its release APK/web measurements from the same workflow/toolchain and calculate exact byte deltas against the baseline above.
3. Add an isolated CI experiment for AAB and split-per-ABI sizes; keep current artifacts unchanged until evidence supports a distribution change.
4. Review generated Android release shrink/minification configuration; the checked-in tree does not contain a tracked `app/android/**` runner, and CI generates platform runners.
5. Audit OCR/barcode feature call sites and web runtime asset selection before proposing further dependency/asset changes.
6. Do not mark Phase Five complete until measurements and regression checks are recorded.
