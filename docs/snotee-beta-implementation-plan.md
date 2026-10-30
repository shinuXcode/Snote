# Snotee Beta implementation plan

Baseline: `beta/snote-0.1.2` (kept unchanged). Work branch: `feat/snotee-beta-polish-20261030`.

## Initial repository audit

- Flutter application under `app/`; Next.js showcase under `website/`.
- Local persistence: SQLite schema version 8 plus local file storage. Existing folder, note, cover, flashcard, mind-map, transfer, and settings implementations are present.
- Drawing: custom canvas/ink pipeline, renderer, lasso geometry and editor implementations.
- Transfer: encrypted notebook export/import exists; QR transfer currently serializes a single note.
- Backups: the current “local backup” page invokes encrypted file export/import. It does not maintain a managed rotating local backup store.
- Android sharing: `receive_sharing_intent` is wired in the home page but accepts images only. The maintained manifest declares image-only SEND/SEND_MULTIPLE filters.
- Website: Snotee branding and a BrandLoader already exist; the logo file is still named `snote-logo.png`.
- Agonesa font is not present in the inspected asset tree or Flutter font configuration.
- Android runner/resources are generated in CI by `flutter create`; the repository maintains its own manifest and Kotlin integration in `app/native_android/`.

## Progress checkpoint — 2026-10-30

- **Phase 1 — Branding foundation:** implemented on the feature branch.
- Website: `npm install`, `npm run typecheck`, design guard and `npm run build` passed.
- Flutter: `dart format` check, `flutter analyze`, and the existing `flutter test` suite passed in GitHub Actions.
- Android APK, Windows, iOS and macOS smoke builds are still running in workflow [41039014112](https://github.com/shinuXcode/Snote/actions/runs/41039014112).
- No database schema, preference-key, package identifier, or user-data migration was performed.
- **Phases 2–8 are not yet implemented.** They remain planned and must be handled in separate, tested changes.

## Performance phase update — 2026-10-30

- The active editor is `EditorV2Page`, not the legacy `NoteEditorPage`. PDF pages are already represented lazily for saved source attachments, with a 48 MiB raster LRU and adjacent-page prefetch on page navigation.
- Root cause of slow note-tab switching: selecting another note used `pushReplacement`, disposing the current editor and its warm PDF document/raster caches. Switching back therefore repeated document loading and decoding.
- Implemented route reuse on the feature branch: editor tabs now push a named route when first opened and return to an already-open route when selected. Existing editor states and their warm PDF caches remain mounted while another note is active.
- Added post-first-frame prefetch of the current page's adjacent PDF pages so the initial visible page can paint before background warming starts.
- Standardized the PDF-import editor route name with the reusable editor-tab route registry.
- No database schema or persisted note format changed. This phase still needs CI verification and device-level frame-time / PDF timing measurements. It is not yet a quantified performance claim.

## Phased plan

1. **Brand foundation:** unify visible app/website naming, remove duplicate sidebar branding, improve logo fit/filtering, preserve existing asset paths and package identifiers. Verify Flutter formatting/analyzer and website typecheck/build.
2. **Home/library:** inspect existing folder/deck/map persistence, add favorites and organization without changing existing note/deck/map records; improve tab state/close behavior. Verify repository/widget tests.
3. **Pages/settings/templates:** map editor page state and settings persistence; implement page actions/navigation and live template controls. Verify editor/document/settings tests and old-note compatibility.
4. **Writing engine:** trace lasso dispatch, selection transforms, eraser and highlighter hot paths; implement focused changes only after regression coverage. Verify lasso, ink, renderer and performance tests.
5. **Sharing/transfer:** build a shared export/import pipeline for supported content and preserve local privacy; extend QR transfer only after validating archive/content model. Verify round-trip and compatibility.
6. **Android intents:** extend MIME filters and URI handling for PDF/documents, validate permissions and deduplicate imports; reuse shared import pipeline. Verify generated Android manifest, Kotlin/Flutter build and import tests.
7. **Utilities/reliability:** inspect browser lifecycle, MediaProjection restrictions, timer/notification lifecycle and backup recovery before changes. Verify platform-specific behavior and avoid claiming unsupported cross-app capture.
8. **Website/release:** align logo/loading state, responsive behavior and transition; run website build and relevant CI.

## Risks and guardrails

- Do not rename SQLite tables, preference keys, Dart package name, application ID, or existing asset paths as part of branding.
- Do not destructively rewrite user notes, decks, mind maps, folders, or backup files.
- The current QR note protocol and encrypted notebook format are compatibility surfaces.
- Android MediaProjection requires explicit OS consent and cannot silently capture another app.
- Agonesa cannot be bundled until a licensed font file is supplied or found in the repository.
- A complete end-to-end implementation of all requested product areas requires focused phases and platform builds; do not mark unverified features complete.
