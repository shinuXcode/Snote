# Phase Seven — Dependency and Architecture Audit

## Status

**Started — repository tree and selected high-impact dependency call sites checked.** This is a scoped audit, not a claim that every Dart import or module boundary has been reviewed. No dependency replacement or bulk upgrade is proposed without evidence.

## Snapshot

- Repository: `shinuXcode/Snote`
- Base `main` commit: `730e5ee488f59dca305794ea8f9a1eda0f53c79c`
- Tracked blobs: **155** (recursive tree was not truncated)
- Dart files: **102** total, including tests; `app/lib/**` contains 83 files.
- Website files: **34**; test-path files: **19**.
- Largest tracked files: `editor_v2_page.dart` (416,334 bytes), `note_editor_page.dart` (296,631 bytes), and `website/public/snote-logo.png` (1,298,678 bytes). Source size alone is not proof of runtime cost.

## Confirmed dependency findings

| Dependency/capability | Evidence in tracked source | Decision |
|---|---|---|
| `webview_flutter` | Repository code search for `package:webview_flutter/` returned zero matches; it is absent from the current `app/pubspec.yaml`. | Already removed in the prior Phase Four change. Do not repeat or claim additional savings. |
| `flutter_inappwebview` | Imported by `app/lib/features/tools/web_search_panel.dart`. | Retain; there is a concrete feature call site. |
| `pdf` | Imported in `app/lib/features/notes/note_editor_page.dart`. | Retain pending feature-level review; PDF generation/export is distinct from viewing. |
| `pdfx` | Imported in `app/lib/features/pdf/pdf_annotation_page.dart` and `app/lib/features/notes/note_editor_page.dart`. | Retain; it serves PDF viewing/annotation paths. Do not infer duplication with `pdf` from both names. |

## Architecture hotspots and risk

| Area | Evidence | Safe next action |
|---|---|---|
| Editor V2 | `app/lib/features/notes/editor_v2/editor_v2_page.dart` is 416,334 bytes and imports note, rendering, archive, PDF, clipboard, sharing, and wakelock capabilities. | Map responsibilities and callers before extracting cohesive units. Do not split or rewrite as a size-only exercise. |
| Legacy editor | `app/lib/features/notes/note_editor_page.dart` is 296,631 bytes and contains PDF-related imports. | Trace active routes and shared behavior before considering removal or consolidation. |
| Canvas engine | `snote_canvas.dart`, `canvas_painter.dart`, input pipeline, and renderer have cross-file responsibilities. | Build a caller/import graph and preserve live ink, pressure, palm rejection, undo/redo, and persistence tests. |
| PDF annotation | `pdf_annotation_page.dart` combines `pdfx` with the shared canvas. | Keep PDF rendering and annotation as a critical regression gate; no cache or concurrency changes without runtime traces. |
| Workflow setup | CI, beta, and release workflows generate platform runners with workflow-specific configuration. | Compare exact steps and conditions before extracting shared scripts; beta IDs, ML Kit, permissions, signing and artifact outputs must remain intact. |

## Dependency review rules

For each remaining direct dependency, record:
1. Source import and call sites, including conditional imports and generated/platform registration.
2. Transitive native/plugin contribution and platform support.
3. Feature coverage, maintenance activity, license, compatibility, migration cost, and binary-size impact of any alternative.
4. Relevant tests and release builds before and after a proposed change.

Do not update all packages together. Keep lockfile changes scoped to a proven dependency change. Never remove generated registration, permissions, licenses, stored-data compatibility, or signing configuration as generic cleanup.

## Cross-phase status at this snapshot

- **Phase Five — release size:** baseline and one follow-up measured; no material saving established. AAB and per-ABI experiments exist, but distribution policy remains unchanged.
- **Phase Six — performance/memory:** measurement protocol committed; physical-device traces and repeatable latency, frame-time, memory, and PDF measurements remain uncollected.
- **Phase Seven — dependency/architecture:** selected package call sites confirmed; full dependency graph and full module-by-module audit remain open.
- **Phase Eight — regression prevention:** CI smoke workflow has passed for the Phase Six documentation PR; critical real-device handwriting/PDF behavior is not proven by compilation.
- **Phase Nine — safe cleanup:** only proven, small changes should be applied. No asset/module deletion is authorized by size alone.

## Validation and completion criteria

This document-only update must pass repository CI. A phase is not complete until the relevant source inventory is reviewed, code changes are small and evidence-backed, relevant tests/builds pass, and exact measurements or explicit blockers are recorded. Device-only behavior must be reported as untested when no device/emulator trace is available.
