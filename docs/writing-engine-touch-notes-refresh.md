# Snote Writing Engine + TouchNotes-Inspired UI Refresh

Status: implementation contract for `feat/writing-engine-touch-notes-refresh`.

## Objective
Rework stylus input, pressure response, stroke rendering, selection accuracy, tool controls, and the tablet-first note workspace while preserving Snote's identity and every existing feature. This is not permission to remove tools, change note formats incompatibly, discard PDF annotations, or replace the editor with a visual mockup.

## Safety rules
1. Work on this feature branch; do not commit directly to `main`.
2. Inventory every CanvasTool, pen type, selection action, gesture, toolbar action, and persisted field before changing behavior.
3. Preserve serialization compatibility; add migrations only when required and test old notes.
4. Keep the current editor available until the replacement compiles and passes regression tests.
5. Measure performance on the same device/configuration before and after. Do not claim improvement from code inspection alone.
6. Render actionable error states instead of blank pages.
7. Make small, reviewable changes and run format, analysis, focused tests, then broader CI.

## UX direction
- Tablet-first, distraction-free paper workspace with responsive portrait/landscape layouts.
- Compact title/header row with navigation, editable title, save state, undo/redo, search, page navigation, and overflow actions where supported.
- Dockable/floating toolbar that can collapse/expand, attach to an edge, move, and adapt to orientation.
- Categorized tool palette, favourite/recent tools, and compact pen showcase.
- Contextual selection toolbar positioned near the selection, clamped to viewport bounds.
- Page thumbnail rail with existing add/reorder/duplicate/cut/copy/paste/delete/share/bookmark actions where supported.
- Direct-manipulation controls with immediate preview; no unnecessary Apply buttons.
- Preserve themes, note lock, tabs, folders, import/export, screenshot/capture, settings, wakelock, and keyboard/gesture behavior.

## Engine boundaries
1. Pointer/stylus normalization and platform metadata.
2. Gesture arbitration and palm rejection.
3. Sample buffering, monotonic timestamps, pressure normalization, velocity, and prediction.
4. Stroke geometry and smoothing.
5. Immediate live-ink layer and committed-stroke layer.
6. Shared selection/spatial hit testing and edit transforms.
7. Commit queue, autosave, serialization, and recovery.

Keep pointer-move work off widget-tree rebuild paths. Share coordinate transforms across drawing, lasso, erasing, selection, zoom, pan, and export.

## Pressure and pens
- Preserve all current pen types/configurations.
- Provide soft/linear/firm pressure presets and custom curves only if safely supported by the current model.
- Show a live pressure sample stroke; clearly distinguish pressure-sensitive width/opacity.
- Handle absent, zero, and out-of-range device pressure without producing invisible ink.
- Keep pressure/velocity replay deterministic and avoid changing old strokes on load.
- Preserve width, color, opacity, smoothing/stabilization, fountain/brush/highlighter behavior, and saved preferences.

## Selection accuracy
- Use one document-to-screen transform and spatial index for selection, eraser, lasso, and shape hit testing.
- Robustly close lasso paths and handle near-duplicate points/self-intersections.
- Define consistent intersection/containment rules.
- Preserve multi-stroke select, bounds/handles, move/resize/rotate where supported, deselect, clipboard, delete, undo/redo.
- Respect zoom, pan, scroll, high DPI, hidden/locked content, and viewport edges.
- Test thin strokes, dense handwriting, crossing strokes, small targets, transformed viewports, and page edges.

## Feature preservation inventory
Verify each item against actual enum, UI, dispatch, renderer, persistence, and tests; mark implemented/partial/unsupported/blocked rather than assuming parity:
- Ballpoint, fountain, pencil, highlighter, marker, brush, pointer, eraser and pixel eraser.
- Lasso, fill, line, arrow, geometry, custom polygons, 3D solids, arcs/sectors and diagram primitives.
- Ruler, compass, protractor, divider and measurement helpers.
- Graphs, axes, curves, vectors, charts, tables, checklists, flowcharts, timelines, mind maps and diagram helpers.
- Science/education illustrations, stickers, images, text boxes, rich text, mixed handwritten/typed content.
- Undo/redo, clipboard, selection transforms, backgrounds/templates, page management, screenshots, search/OCR, import/export and existing shortcuts.
- PDF import/reader/annotation, continuous pages, zoom, thumbnails, search where supported, bookmarks, reading-position restore, inserted blank pages, annotation save/reopen and export.

## Phases
### 0 — Inventory and baseline
Map routes and consumers of SnoteCanvas/controller, NoteEditorPage, tool dispatch, serialization, and PDF flows. Run focused tests and clean Android build. Record latency/frame metrics, memory and APK size on a fixed device/configuration; capture current portrait/landscape screenshots.

### 1 — Workspace shell
Refresh editor chrome and toolbar while keeping existing canvas/dispatch wired. Add tests for New Note, existing-note open, title editing, tool visibility, collapse/expand, and viewport constraints.

### 2 — Input and pressure
Refactor behind stable interfaces without losing pointer kind/timestamps. Test finger/stylus transitions, palm rejection, pressure extremes/missing pressure, timestamp ordering, stylus lock and cancellation. Verify live ink and committed persistence.

### 3 — Geometry/rendering
Separate live and committed layers; limit invalidation where practical. Validate mapping across pan/zoom/scroll, refresh rates and pixel ratios. Compare performance to Phase 0.

### 4 — Selection
Unify lasso, eraser and hit-test geometry. Test move/resize/rotate, clipboard, delete, undo/redo and save/reopen.

### 5 — Full tool palette
Reconnect every inventoried tool and settings control. Test each tool family, shortcuts, tablet sizes, orientation, keyboard/mouse/stylus input.

### 6 — Migration/release
Switch callers only after parity. Remove old modules only after repository-wide reference checks. Require non-cancelled CI, Android APK build and smoke tests for New Note, reopen, handwriting, selection, PDF annotation, import/export and recovery.

## Acceptance gates
- New Note opens a visible, non-blank canvas with correct note identity.
- Existing notes and PDFs load/save without content loss.
- Ink appears immediately, tracks naturally, commits once and survives reopen.
- Pressure presets visibly differ; invalid/missing pressure never hides ink.
- Selection stays aligned through zoom/pan and selects intended strokes in regression fixtures.
- Every existing tool remains reachable and functional; none silently disappears from UI or dispatch.
- Toolbar, pen showcase, page previews, title, undo/redo and settings work in tablet portrait/landscape.
- Formatting, analysis, tests, Android release build and relevant CI pass.
- Attach reproducible before/after measurements and APK sizes to the PR.
- Explicitly report failed/unaudited checks; do not call the work complete while a release gate is blocked.

## Per-phase report
List changed files and rationale, behavior changed, exact tests/results, device and measurement method, regressions/blocked checks, and evidence of compatibility for existing notes, tools and PDF annotations.
