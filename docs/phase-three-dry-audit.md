# Snote Phase Three — DRY Audit Register

## Audit rules

This is a behavior-first audit. A repeated pattern is only a refactor candidate until call sites, lifecycle, data format, and platform behavior are compared. Do not merge code paths simply because they share names or similar-looking drawing code. No broad code extraction or dependency removal is authorized by this register alone.

For each candidate, trace:
1. definitions and all call sites/imports;
2. state ownership, initialization/disposal, and asynchronous boundaries;
3. data formats and backwards compatibility;
4. platform-specific behavior;
5. tests and a before/after behavior check;
6. runtime impact if it lies on the ink/PDF hot path.

## Confirmed initial candidates

| Area | Evidence in current source | Potential duplication | Risk | Next action |
|---|---|---|---|---|
| Note editors | `app/lib/features/notes/editor_v2/editor_v2_page.dart` (416,334 bytes) and `app/lib/features/notes/note_editor_page.dart` (296,631 bytes) | Similar user-facing note workflows and shared features exist, but EditorV2 explicitly says pointer handling, selection, drawing and painting are independent of legacy SnoteCanvas. | Critical: different input/render lifecycle and compatibility paths may be intentional. | Build a feature/call-site matrix first; do not merge editor classes. Identify which routes create each editor and which formats/features each supports. |
| Ink painters | `app/lib/features/notes/editor_v2/editor_v2_ink_painter.dart` and `app/lib/canvas_engine/painters/canvas_painter.dart` both iterate strokes, draw selection/eraser overlays and implement pen rendering. | Some low-level paint calculations and shape/stroke rendering may overlap. | Critical: different live-stroke models, pressure behavior, shape support, repaint mechanics, and visual behavior. | Compare drawing helpers branch-by-branch; extract only a pure helper with parity tests if semantics truly match. Benchmark before/after frame timing. |
| Stroke and pen model | `app/lib/canvas_engine/models/stroke.dart`, `pen_config.dart`, `stroke_codec.dart` are shared by both editor families. | Possible repeated validation/serialization conversions around the shared model. | High: note format is persisted and must remain backwards-compatible. | Trace codecs and all read/write call sites before modifying formats; add round-trip/legacy fixtures. |
| PDF generation/viewing | Editor V2 imports both `pdf` and `pdfx`; app manifest declares both. `pdf_annotation_page.dart` is a separate PDF annotation feature. | Export generation and PDF viewing are different concerns despite both containing “PDF”. | Critical: removing either dependency could break export, viewing, annotation, or web/native support. | Map imports and feature flows for each package; inspect transitive/native assets and platform support. No removal yet. |
| Web views | `webview_flutter` and `flutter_inappwebview` are both declared. | May duplicate embedded-web functionality, or may serve different browser and feature use cases. | High: plugin registrations and platform implementations affect builds and behavior. | Search all imports/call sites, map required capabilities/platforms, then decide whether one is truly unused. |
| CI runner setup | `.github/workflows/ci.yml`, `beta.yml`, `release.yml` generate platform runners and patch generated configuration. | Repeated runner-generation and Android setup logic. | High: app IDs, ML Kit, camera permissions, desugaring, sharing intents, signing/release packaging, and screenshot capture differ by workflow. | Compare scripts and generated output. Prefer a parameterized shared script only after proving workflow-specific requirements are represented and idempotent. |
| Theme and dimensions | Theme/controller files, editor toolbars, canvas backgrounds and painters contain visual constants. | Possible duplicated colors, paddings, stroke widths, radii and typography. | Medium to critical depending on whether values affect pen rendering or persisted note appearance. | Search exact constants and context; centralize design tokens only when visual semantics match. Avoid moving per-frame paint values through indirection without profiling. |
| Data repositories | `app/lib/data/local/folder_repository.dart`, `note_repository.dart`, and `file_document_repository.dart` own persistence concerns. | Potential repeated database initialization, serialization, path handling, and error reporting. | High: data loss, migration, offline-first guarantees, and file/database consistency. | Trace repository call graph and transactions; add fixture-based persistence/import/export tests before extraction. |
| Website styling | `website/app/globals.css` is 46,312 bytes; `website/public/snote-logo.png` is 1,298,678 bytes. | Possible repeated CSS declarations; image size is a separate asset optimization candidate, not DRY logic. | Medium for CSS; low-to-medium for asset replacement if visual references are updated. | Run a duplicate CSS declaration scan and inspect actual asset imports/routes. Preserve the logo and its visual dimensions; measure production output after any image change. |

## Source-search findings (main snapshot)

Exact repository-wide code-search queries were run against the current main snapshot. Search hits are leads, not proof that every occurrence has identical semantics.

| Search pattern | Hits | Files / interpretation |
|---|---:|---|
| `withValues(alpha: .55)` | 6 | Onboarding, notes home, legacy editor, SnoteCanvas, legacy painter, Editor V2 painter. Likely visual constants in several contexts; compare intended colors/opacity before centralizing. |
| `Rect.fromCenter` | 3 | SnoteCanvas, legacy painter, Editor V2 painter. Includes eraser/overlay geometry; review dimensions and coordinate spaces before extraction. |
| `clamp(.5, 60)` | 6 | Stroke codec, ink renderer, SnoteCanvas, legacy editor, legacy painter, Editor V2 painter. Similar range is reused for persisted input validation, tool editing, and rendering; do not automatically force all call sites through one helper. |
| `catch (e)` | 2 | QR import page and settings page. The query is narrow and does not establish that error handling elsewhere is consistent. |
| `getDefaultProguardFile` | 4 | CI, beta, release workflows and beta Android setup script. This confirms overlapping Android build configuration that should be compared for idempotence and workflow-specific differences. |

Additional repository-wide search results (main snapshot):

| Search pattern | Hits | Candidate review |
|---|---:|---|
| `kIsWeb` | 3 | QR import, notes home, legacy editor. Compare whether platform-specific branches encode the same capability check or different fallback behavior. |
| `defaultTargetPlatform` | 4 | QR import, PDF annotation, notes home, legacy editor. Review the feature-level capability matrix; do not replace with a single global flag without preserving desktop/mobile differences. |
| `jsonEncode(` | 9 | QR transfer, note lock, web search, legacy editor, timer, file-document repository, note repository, Editor V2 document codec, tests. Most encode different schemas; focus on shared note/document serialization boundaries rather than generic JSON wrappers. |
| `jsonDecode(` | 14 | Note/editor, lock, QR import/transfer, notebook transfer, repositories, tools, updates. Different schemas and trust boundaries mean generic extraction is risky; identify schema-specific duplicates and error-handling consistency first. |
| `SnoteSettings.instance` | 8 | Main, settings, notes home/editor, split workspace, PDF annotation and tools. The singleton itself may be intentional; review repeated initialization, reads/writes, and lifecycle rather than introducing another dependency layer. |
| `catch (error)` | 11 | Screenshot import, selection OCR, editor/document, timer, notes home, alarms, update center, PDF, folder covers, website feedback. This query misses other catch variable names. Compare error recovery/logging per feature; avoid swallowing errors or changing user-visible messages. |
| `Platform.isAndroid` | 1 | Editor V2 selection OCR IO implementation. This is not proof platform branching is centralized; search all platform APIs and conditional imports before changing. |

These counts are exact-pattern search results on the snapshot, not counts of all semantically equivalent operations. Each result must be read in context before classifying as duplicate behavior.

### Exact low-risk-looking repetition requiring tests

In `app/lib/canvas_engine/ink_renderer.dart`, the pressure-width multiplication

```dart
width *= .82 + pressure * (.18 + pen.pressureSensitivity * .34);
```

appears in both the `index > 0` and `else` branches of `_radiusFor` (currently around lines 258 and 260 in main). The branches differ because the first also applies a velocity factor. Moving the identical pressure-width expression after the conditional may remove duplication without changing its order relative to the velocity factor, but this is **not changed in the baseline PR**. Before accepting it, add or use focused tests for first-point, non-first-point, and fountain strokes and compare renderer output for representative stroke fixtures.

## Initial audit status

- [x] Identify large source files and architecture boundaries from the tracked-file inventory.
- [x] Record confirmed overlapping dependency pairs and workflow setup areas as candidates.
- [ ] Trace editor routing and all callers for both editor implementations.
- [ ] Compare the two ink painters and test whether any pure calculations are behavior-identical.
- [ ] Search all Dart files for repeated constants, validation, error handling, serialization, platform checks, and initialization patterns.
- [ ] Inspect repository/query call graphs and database lifecycle.
- [ ] Audit website CSS duplication and asset references.
- [ ] Add or improve focused regression tests before any behavior-changing extraction.
- [ ] Record every accepted extraction with the source locations, behavior contract, tests, and measured outcome.

## Explicit non-goals

- No giant catch-all utility file.
- No abstraction for a one-off operation.
- No speculative removal of `pdf`, `pdfx`, `webview_flutter`, or `flutter_inappwebview`.
- No forced unification of legacy and Editor V2 canvas lifecycles.
- No changes to saved note formats, stroke data, PDF annotations, input latency, or user-facing behavior without regression tests.
