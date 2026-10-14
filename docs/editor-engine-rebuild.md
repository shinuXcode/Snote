# Snote Editor Engine Rebuild

## Goal
Replace the existing editor/canvas implementation on this branch with a new, independently structured editor engine while preserving the app shell, local note repository, account scope, and unrelated home-screen features. Do not modify `main`.

## Non-negotiable migration rule
Do not delete the current editor/canvas implementation until the replacement is wired in, compiles, and passes its automated acceptance tests. Keep the old implementation available on the parent branch for comparison and recovery. The final cleanup must remove the legacy engine only after all consumers (New Note, existing-note open, PDF annotation, import/export) have migrated.

## Proposed module boundaries
- `features/notes/editor_v2/`: route, editor shell, document/session state, loading/error states, autosave orchestration.
- `canvas_engine_v2/model/`: document/page/stroke/tool data models and serialization.
- `canvas_engine_v2/input/`: pointer/stylus normalization, palm rejection, gesture arbitration, pressure/velocity processing.
- `canvas_engine_v2/render/`: live-ink layer, committed-stroke layer, page/background renderer, invalidation and repaint policy.
- `canvas_engine_v2/tools/`: pens, erasers, lasso, shapes, rulers, diagrams, educational tools, stickers.
- `features/pdf/editor_v2/`: PDF loading, page navigation/thumbnails, annotation overlay, inserted blank pages, persistence, export.
- `features/notes/editor_v2/persistence/`: repository adapter, save queue, retry/error reporting, recovery.
- `features/notes/editor_v2/toolbar/`: dockable/floating toolbar, favourite-pen showcase, tool settings and responsive placement.

## Delivery phases
1. **Baseline and contracts** — map every consumer of the current editor/canvas, document serialization format, repository APIs, route entry points, and CI workflows. Add explicit tests for new-note creation/open/close and PDF load/error paths.
2. **New Note + editor shell** — implement a dedicated full-screen route with per-note identity, loading/error states, lifecycle diagnostics, and repository-backed document session. Verify the route renders a visible canvas in Android and web smoke tests.
3. **Document/page model and persistence** — pages, templates/backgrounds, content migration, serialized strokes/text/stickers, save queue, autosave/retry and reopen recovery.
4. **Input and ink pipeline** — normalized stylus/finger events, pressure/velocity curves, palm rejection, live ink, committed ink, stroke smoothing, stable viewport transforms and undo/redo.
5. **Editing tools** — pen variants, erasers, lasso, selection transforms, all listed shapes, rulers/compass/protractor/divider, graphs/charts/flowcharts and science/education diagrams.
6. **Rich text and mixed content** — Quill/text boxes, title editing, stickers, images, handwritten + typed content on the same page.
7. **PDF workspace** — import/load, continuous scrolling, zoom, thumbnails, text search where supported, page restore/bookmarks, annotation tools, inserted blank pages, save/reopen and PDF export.
8. **Toolbar and platform polish** — docked/floating toolbar, edge attachment/orientation, movable favourite-tool/pen showcase, theme/settings integration, tablet/desktop layouts, file/image picker, lock and wakelock integration.
9. **Migration and deletion** — switch every caller to the new implementation, remove legacy editor/canvas code and obsolete imports only after reference search and tests show no consumers remain.
10. **Release gate** — one complete non-cancelled workflow for format/analyze/tests and Android APK build; full CI for supported platforms; verify New Note, existing note, PDF annotation, save/reopen, tool interactions, and export before publishing a beta.

## Acceptance gates
- New Note creates a repository-backed note, opens a non-blank full-screen editor, closes to home, and reopens with saved content.
- A render/load failure shows an actionable error state instead of a blank screen; diagnostics include the exception and stack trace.
- Ink appears immediately, commits without disappearing, survives save/reopen, and remains aligned through zoom/pan/scroll.
- Undo/redo, eraser, lasso selection, shape tools, and page changes have automated tests for their core state transitions.
- PDF import, page navigation, annotation, save/reopen, blank-page insertion, and export are tested as a single workflow.
- CI is allowed to finish; do not push a new commit that cancels the active required workflow.
- No changes to `main` until the rebuilt beta is verified and explicitly approved.

## Scope honesty
A tool enum or UI control is not considered implemented merely because it exists. Each listed tool must have model/geometry behavior, rendering, input/edit behavior, persistence, and test coverage appropriate to that tool. Hardware-specific latency and palm rejection still require physical-device testing.
