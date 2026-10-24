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
