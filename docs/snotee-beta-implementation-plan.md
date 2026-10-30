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
