# Phase Six — Performance and Memory Baseline

## Status

**Started — baseline protocol and code hotspots inventoried; runtime measurements not yet collected.**

This phase intentionally makes no renderer, cache, scheduling, or PDF-loading changes until a reproducible baseline exists. CI smoke-build success is not evidence of smooth handwriting, low memory use, or acceptable PDF performance.

## Scope

Measure and improve, in this order:

1. Live handwriting latency and dropped frames.
2. Stroke finalization and repaint cost as stroke count grows.
3. Memory growth during long writing sessions, undo/redo, page switching, and document reopen.
4. PDF open latency, page-scroll smoothness, zoom behavior, and memory with large documents.
5. Workspace/editor mount, tab switching, and disposal/reopen behavior.

## Source inventory and grounded candidates

| Area | Existing source/test evidence | What remains unknown |
|---|---|---|
| Shared ink rendering | `app/lib/canvas_engine/ink_renderer.dart` implements retained-mode ink rendering; fountain strokes use smoothing and ribbon geometry. | Per-stroke allocation count, render duration, and frame-time contribution on device. |
| Canvas painting | `app/lib/canvas_engine/painters/canvas_painter.dart` is a 46,660-byte tracked source file and is used by the legacy canvas path. | Repaint frequency, layer invalidation behavior, raster cost, and allocation profile under realistic documents. |
| Editor V2 | `app/lib/features/notes/editor_v2/editor_v2_page.dart` is a 416,334-byte tracked source file. Size alone is not a performance defect. | Build/rebuild costs, widget churn, state ownership and lifecycle costs; inspect callers before restructuring. |
| Live ink/input | `app/test/live_ink_widget_test.dart` (11,263 bytes) tests active-ink visibility and gesture behavior; `app/test/ink_pipeline_test.dart` (5,750 bytes) tests input pipeline behavior. | Physical stylus event-to-pixel latency, high-refresh behavior, palm rejection under real use, and dropped frames. |
| Rendering/geometry | `app/test/canvas_engine_test.dart`, `app/test/ink_renderer_test.dart`, and `app/test/rendering_geometry_test.dart` provide functional coverage. | Stable frame-time and memory baselines; performance thresholds are not currently recorded in these tests. |
| PDF annotation | `app/lib/features/pdf/pdf_annotation_page.dart` uses `pdfx` and the shared canvas. | Cold-open time, page raster/cache memory, large-document scrolling, zoom, and disposal behavior. |

## Measurement protocol

### Environment record

For each run, record:

- Device model, OS version, available RAM, display refresh rate, and stylus model where applicable.
- Exact Git commit, Flutter/Dart versions, build mode, renderer/backend, and app settings.
- Test document characteristics: page count, page dimensions, PDF file size, existing stroke count, and active-stroke sample count.
- Thermal/battery state, whether the run was cold or warmed, and whether background apps were controlled.

Do not compare numbers across different devices/build modes as if they were equivalent.

### Handwriting workload

Run a fixed sequence with the same stylus and canvas size:

1. Draw short, medium, and long strokes at slow/normal/fast speeds.
2. Repeat with ballpoint, fountain, and highlighter; include pressure variation where supported.
3. Write for 5 minutes, then for 20 minutes with a realistic mix of strokes, erasing, lasso selection, undo/redo, and page navigation.
4. Repeat with an empty page, hundreds of strokes, and a large existing note.
5. Capture Flutter frame timing and platform/system traces where available; use high-speed video or an external latency method if event-to-pixel latency is required.

Record p50/p95/p99 frame duration, frames over the display budget (16.7 ms at 60 Hz; 8.3 ms at 120 Hz), missed frames, and event-to-visible-ink latency if it can be measured reliably. Do not infer input latency from average FPS alone.

### Memory and lifecycle workload

- Capture a baseline after cold launch and after warm-up.
- Repeat the handwriting workload, undo/redo, switch notes/tabs, leave and reopen the editor, and dispose/reopen the same note.
- Record process RSS/PSS where available, Dart heap, native/external memory, peak memory, and post-GC/idle memory.
- Repeat at least three times and report median plus range. Look for monotonic growth and retained objects; do not treat a single noisy reading as proof of a leak.

### PDF workload

Use fixed, legally shareable test PDFs at small, medium, and large sizes. Record cold and warm open time, time to first rendered page, scroll frame timings, zoom/pinch behavior, page raster/cache memory, and memory after close/reopen. Test on supported platforms individually; a desktop run is not a substitute for a tablet run.

## Acceptance gates before code optimization

- Collect at least three repeatable baseline runs for each available target device.
- Keep raw measurements and environment metadata alongside the summary.
- Identify one measured bottleneck and link it to a concrete call path before changing code.
- Add or update a regression test where deterministic behavior can be asserted.
- For any optimization, compare the same workload and configuration before/after, and re-run handwriting visibility, stroke geometry, undo/redo, note persistence, PDF annotation, and lifecycle regression tests.
- Reject changes that improve one metric but regress visible ink, stylus fidelity, data integrity, or another supported platform.

## Current limitations / blockers

- No physical device profiling trace or hardware measurements are available from GitHub CI in this audit.
- Widget/unit tests are useful for correctness but cannot establish real stylus-to-pixel latency or device memory pressure.
- The current release-size workflow does not collect Flutter frame timing, Dart heap snapshots, native memory traces, or PDF scroll traces.
- No numeric performance baseline or performance improvement is claimed yet.

## Next work batch

1. Capture a profile-mode trace on the primary stylus tablet for live ink and long-stroke workloads.
2. Capture memory/lifecycle behavior for repeated note open/close and undo/redo.
3. Capture PDF first-page and scroll performance on a representative large PDF.
4. Map the highest-cost frames/allocations back to source and callers.
5. Propose one narrow change at a time; retain traces and test evidence in the ledger.

