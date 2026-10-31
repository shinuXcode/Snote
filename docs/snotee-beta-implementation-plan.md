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

## Progress checkpoint — 2026-10-31

Work is being committed incrementally to `feat/snotee-beta-polish-20261030`. The base beta branch remains untouched.

- Existing note/folder favorites are exposed in the desktop navigation rail; opening a folder from Favorites exits the favorites filter cleanly.
- Note and folder menus now expose encrypted file export and encrypted QR transfer entry points. The existing QR receiver ignores duplicate completed frame sequences and can be reset for another transfer.
- The generated cover catalog now exposes 400 variants in ten collections. These are generated vector/gradient designs, not 400 separately licensed image assets.
- Note settings include a persistent default page template and paper/line color palettes; new pages apply valid saved defaults without changing existing pages.
- Editor tabs include close controls and a five-mounted-editor cap to limit memory growth. Existing note routes are reused where registered.
- Ink changes include cached static stroke pictures, incremental live highlighter path updates, an optional highlighter overlay layer, decoded-stroke reuse, and lasso size +/- controls. Eraser hit testing uses cached stroke bounds as a broad phase.
- Portrait vertical page-turn direction was adjusted.
- Android launch resources are maintained in-repo and copied into the generated runner by CI; the Flutter startup surface is platform-aware so desktop retains its startup page.
- Website BrandLoader now fades after page readiness with a timeout fallback.
- Browser opening now selects the embedded browser panel rather than stacking a separate modal route.
- No SQLite schema migration or destructive note-data rewrite was made.

**Validation:** latest branch-head workflow [41161081889](https://github.com/shinuXcode/Snote/actions/runs/41161081889) is still running. At the last check, platform jobs were setting up Flutter and the website build had started. Do not treat earlier or superseded workflow results as proof for this branch head. No APK artifact from this head has been verified yet.

## Performance phase update — 2026-10-30

- The active editor is `EditorV2Page`, not the legacy `NoteEditorPage`. PDF pages are already represented lazily for saved source attachments, with a 48 MiB raster LRU and adjacent-page prefetch on page navigation.
- Root cause of slow note-tab switching: selecting another note used `pushReplacement`, disposing the current editor and its warm PDF document/raster caches. Switching back therefore repeated document loading and decoding.
- Implemented route reuse on the feature branch: editor tabs now push a named route when first opened and return to an already-open route when selected. Existing editor states and their warm PDF caches remain mounted while another note is active.
- Added post-first-frame prefetch of the current page's adjacent PDF pages so the initial visible page can paint before background warming starts.
- Standardized the PDF-import editor route name with the reusable editor-tab route registry.
- No database schema or persisted note format changed. This phase still needs CI verification and device-level frame-time / PDF timing measurements. It is not yet a quantified performance claim.

## Remaining work — do not mark complete yet

1. **Library/deck/map:** verify favorites persistence and add missing deck/map organization controls where existing models support them; verify full tab close/fallback behavior and page-preview actions (copy/cut/paste/delete/insert/search navigation).
2. **Settings/templates:** apply the saved page-template and color defaults through every new-page entry point; finish persistent note controls, settings grouping and live template preview. Expand cover collections only after confirming the library browsing UI and performance.
3. **Writing engine:** run focused lasso, resize, eraser, highlighter z-order and selection regression tests. The current painter/cache work is not a substitute for device profiling.
4. **Sharing/backup:** encrypted note/folder exports are exposed, but attachment/binary completeness and QR folder/page/deck round-trips are not yet proven. Implement a managed rotating local backup with safe restore separately; current “local backup” page is still encrypted file export/import.
5. **Browser/utilities:** validate browser collapse/resizing/ad-blocking limits, timer/alarm lifecycle across app background/restart, and screenshot capture consent flows. Do not claim silent cross-app capture.
6. **Release polish:** confirm native splash behavior on Android API levels and iOS, inspect responsive website transitions, and complete all CI jobs plus physical-device regression checks.

## Validation gates

- Latest branch-head workflow: [41161081889](https://github.com/shinuXcode/Snote/actions/runs/41161081889). It must complete for the exact final commit before a build is called verified.
- Required checks: Flutter format/analyze/tests; Android APK and web/Linux builds; Windows, iOS and macOS smoke builds; website typecheck/build.
- Then test actual Android stylus writing, PDF opening/scrolling, tab switching, note/folder export/import, backup recovery and launch transitions on-device.
- No merge, release, or beta APK announcement until the user explicitly requests it and all applicable checks pass.

## Risks and guardrails

- Do not rename SQLite tables, preference keys, Dart package name, application ID, or existing asset paths as part of branding.
- Do not destructively rewrite user notes, decks, mind maps, folders, or backup files.
- The current QR note protocol and encrypted notebook format are compatibility surfaces.
- Android MediaProjection requires explicit OS consent and cannot silently capture another app.
- Agonesa cannot be bundled until a licensed font file is supplied or found in the repository.
- A complete end-to-end implementation of all requested product areas requires focused phases and platform builds; do not mark unverified features complete.
