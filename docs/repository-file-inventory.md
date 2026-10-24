# Repository File Inventory — Snote

> Snapshot of tracked blobs at `a844947da813be55f1b1609966711f7c7e97150c` on `refactor/repository-dry-size-optimization`. Sizes are Git blob byte counts. Responsibilities/risk are path-based triage, not proof of complete semantic review. Callers and imported dependencies require source-level tracing before refactoring.

- Tracked files inventoried: **151** (recursive Git tree reported not truncated).
- Dart application files: **83**.
- Test files: **19**.
- Website files: **34**.
- Generated/vendor files must be identified separately; no generated-file matches were found by the initial filename-pattern scan. Lockfiles are retained as dependency resolution inputs, not treated as duplicated application source.

## Prioritized large files

| File | Bytes | Responsibility | Risk / validation |
|---|---:|---|---|
| `website/public/snote-logo.png` | 1,298,678 | Website/showcase | Medium; Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `app/lib/features/notes/editor_v2/editor_v2_page.dart` | 416,334 | Note editor and navigation | High; Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/note_editor_page.dart` | 296,631 | Note editor and navigation | High; Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/notes_home_page.dart` | 90,578 | Note editor and navigation | High; Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/editor_v2/editor_v2_ink_painter.dart` | 83,313 | Note editor and navigation | High; Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/canvas_engine/widgets/snote_canvas.dart` | 57,807 | Canvas/input/rendering engine | High; Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/painters/canvas_painter.dart` | 46,660 | Canvas/input/rendering engine | High; Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `website/app/globals.css` | 46,312 | Website/showcase | Medium; Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `app/lib/features/tools/floating_timer_panel.dart` | 30,760 | Documentation/project metadata | Low; Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/settings/settings_page.dart` | 26,605 | Documentation/project metadata | Low; Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/pdf/pdf_annotation_page.dart` | 22,979 | PDF viewing and annotation | High; Check PDF loading/search/annotation/page state; run PDF tests and platform builds. |
| `app/lib/data/local/folder_repository.dart` | 18,388 | Data persistence and repositories | High; Trace call sites and migration/import/export compatibility; run data tests. |
| `.github/workflows/beta.yml` | 17,139 | CI/release workflow | High; Compare workflow-specific requirements; run each affected workflow and inspect artifacts. |
| `app/lib/features/tools/mind_map_page.dart` | 16,836 | Documentation/project metadata | Low; Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/canvas_engine/models/pen_config.dart` | 16,753 | Canvas/input/rendering engine | High; Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `.github/scripts/configure_beta_android.py` | 15,269 | Build automation script | High; Check all workflow callers, idempotence, and generated Android configuration. |
| `app/lib/features/tools/web_search_panel.dart` | 15,206 | Documentation/project metadata | Low; Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/updates/update_center_page.dart` | 13,197 | Documentation/project metadata | Low; Check links and claims against actual code; update only when related behavior changes. |
| `.github/workflows/ci.yml` | 13,140 | CI/release workflow | High; Compare workflow-specific requirements; run each affected workflow and inspect artifacts. |
| `.github/workflows/release.yml` | 12,777 | CI/release workflow | High; Compare workflow-specific requirements; run each affected workflow and inspect artifacts. |

## Complete tracked-file register

| Path | Bytes | Responsibility (triage) | Risk | Required validation |
|---|---:|---|---|---|
| `.github/scripts/configure_beta_android.py` | 15,269 | Build automation script | High | Check all workflow callers, idempotence, and generated Android configuration. |
| `.github/workflows/beta.yml` | 17,139 | CI/release workflow | High | Compare workflow-specific requirements; run each affected workflow and inspect artifacts. |
| `.github/workflows/ci.yml` | 13,140 | CI/release workflow | High | Compare workflow-specific requirements; run each affected workflow and inspect artifacts. |
| `.github/workflows/release.yml` | 12,777 | CI/release workflow | High | Compare workflow-specific requirements; run each affected workflow and inspect artifacts. |
| `app/assets/branding/snote-logo.png` | 2,171 | Application asset | Medium | Check references, dimensions, compression, and runtime appearance before changing. |
| `app/lib/app/app_entry.dart` | 241 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/app/theme_controller.dart` | 3,287 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/canvas_engine/algorithms/adaptive_stabilizer.dart` | 1,713 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/algorithms/bezier_smoother.dart` | 741 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/algorithms/ink_dynamics.dart` | 800 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/algorithms/lasso_geometry.dart` | 4,568 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/algorithms/shape_recognizer.dart` | 3,555 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/algorithms/stroke_geometry.dart` | 4,235 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/algorithms/velocity_calculator.dart` | 1,149 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/ink_renderer.dart` | 9,808 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/input/ink_gesture_policy.dart` | 790 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/input/ink_input_pipeline.dart` | 5,041 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/input/ink_prediction.dart` | 1,781 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/input/ink_sample.dart` | 1,775 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/input/palm_rejection.dart` | 412 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/input/stroke_sample_buffer.dart` | 1,494 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/input/stylus_gesture_lock.dart` | 850 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/input/viewport_transform.dart` | 597 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/models/pen_config.dart` | 16,753 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/models/stroke_codec.dart` | 4,819 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/models/stroke.dart` | 1,858 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/painters/canvas_painter.dart` | 46,660 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/performance/ink_engine_metrics.dart` | 819 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/performance/stroke_spatial_index.dart` | 1,831 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/performance/writing_performance.dart` | 5,015 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/persistence/ink_commit_queue.dart` | 667 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/widgets/notebook_viewport.dart` | 4,586 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/widgets/page_background.dart` | 4,831 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/widgets/snote_canvas_controller.dart` | 3,845 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/canvas_engine/widgets/snote_canvas.dart` | 57,807 | Canvas/input/rendering engine | High | Review hot paths, allocations, pointer event processing, repaint boundaries; run ink/stroke regression tests. |
| `app/lib/core/config/account_scope.dart` | 254 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/core/config/app_version.dart` | 212 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/core/security/note_lock_service.dart` | 2,329 | Build/dependency configuration | High | Check dependency graph, platform constraints, lockfile consistency and reproducible builds. |
| `app/lib/core/settings/app_settings.dart` | 6,080 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/data/local/database.dart` | 4,656 | Data persistence and repositories | High | Trace call sites and migration/import/export compatibility; run data tests. |
| `app/lib/data/local/file_document_repository.dart` | 3,972 | Data persistence and repositories | High | Trace call sites and migration/import/export compatibility; run data tests. |
| `app/lib/data/local/folder_repository.dart` | 18,388 | Data persistence and repositories | High | Trace call sites and migration/import/export compatibility; run data tests. |
| `app/lib/data/local/local_file_store_native.dart` | 1,381 | Data persistence and repositories | High | Trace call sites and migration/import/export compatibility; run data tests. |
| `app/lib/data/local/local_file_store_stub.dart` | 724 | Data persistence and repositories | High | Trace call sites and migration/import/export compatibility; run data tests. |
| `app/lib/data/local/local_file_store.dart` | 93 | Data persistence and repositories | High | Trace call sites and migration/import/export compatibility; run data tests. |
| `app/lib/data/local/note_repository.dart` | 12,592 | Data persistence and repositories | High | Trace call sites and migration/import/export compatibility; run data tests. |
| `app/lib/data/local/notebook_transfer_service.dart` | 7,119 | Data persistence and repositories | High | Trace call sites and migration/import/export compatibility; run data tests. |
| `app/lib/data/local/notification_repository.dart` | 2,944 | Data persistence and repositories | High | Trace call sites and migration/import/export compatibility; run data tests. |
| `app/lib/data/local/schema.dart` | 2,113 | Data persistence and repositories | High | Trace call sites and migration/import/export compatibility; run data tests. |
| `app/lib/data/local/shared_media_path_reader_io.dart` | 168 | Data persistence and repositories | High | Trace call sites and migration/import/export compatibility; run data tests. |
| `app/lib/data/local/shared_media_path_reader_stub.dart` | 194 | Data persistence and repositories | High | Trace call sites and migration/import/export compatibility; run data tests. |
| `app/lib/data/local/shared_media_path_reader.dart` | 105 | Data persistence and repositories | High | Trace call sites and migration/import/export compatibility; run data tests. |
| `app/lib/features/folders/folder_cover_art.dart` | 5,827 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/folders/folder_cover_library_page.dart` | 10,298 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/folders/folder_cover_repository.dart` | 2,764 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/folders/folder_tree_view.dart` | 11,862 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/folders/folders_page.dart` | 7,626 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/notes/editor_v2/editor_v2_document.dart` | 4,715 | Note editor and navigation | High | Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/editor_v2/editor_v2_ink_painter.dart` | 83,313 | Note editor and navigation | High | Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/editor_v2/editor_v2_page.dart` | 416,334 | Note editor and navigation | High | Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/editor_v2/multi_split_workspace.dart` | 3,909 | Note editor and navigation | High | Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/editor_v2/selection_text_recognizer_io.dart` | 1,287 | Note editor and navigation | High | Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/editor_v2/selection_text_recognizer_stub.dart` | 197 | Note editor and navigation | High | Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/editor_v2/selection_text_recognizer.dart` | 333 | Note editor and navigation | High | Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/editor_v2/smart_pages_catalog.dart` | 9,550 | Note editor and navigation | High | Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/new_note_route.dart` | 772 | Note editor and navigation | High | Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/nextgen_editor_route.dart` | 3,024 | Note editor and navigation | High | Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/note_content_compatibility.dart` | 11,850 | Note editor and navigation | High | Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/note_editor_page.dart` | 296,631 | Note editor and navigation | High | Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/notes_home_page.dart` | 90,578 | Note editor and navigation | High | Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/notes/workspace_layout.dart` | 584 | Note editor and navigation | High | Trace callers/state flow; run editor, note persistence, navigation and live-ink tests. |
| `app/lib/features/onboarding/welcome_guide_page.dart` | 8,770 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/pdf/pdf_annotation_page.dart` | 22,979 | PDF viewing and annotation | High | Check PDF loading/search/annotation/page state; run PDF tests and platform builds. |
| `app/lib/features/settings/settings_page.dart` | 26,605 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/share/qr_import_page.dart` | 5,351 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/share/qr_transfer_page.dart` | 3,928 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/tools/alarm_notification_service.dart` | 6,116 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/tools/flashcard_page.dart` | 12,741 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/tools/floating_timer_panel.dart` | 30,760 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/tools/mind_map_page.dart` | 16,836 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/tools/screen_capture.dart` | 280 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/tools/screenshot_import_page.dart` | 5,783 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/tools/web_search_panel.dart` | 15,206 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/trash/trash_page.dart` | 2,226 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/features/updates/update_center_page.dart` | 13,197 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/main.dart` | 9,769 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/ui/snote_logo.dart` | 811 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/lib/ui/snote_theme.dart` | 8,622 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/native_android/AndroidManifest.xml` | 2,998 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/native_android/MainActivity.kt` | 4,874 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/native_android/ScreenCaptureBridge.kt` | 900 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/native_android/ScreenCaptureService.kt` | 8,190 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/pubspec.yaml` | 1,175 | Build/dependency configuration | High | Check dependency graph, platform constraints, lockfile consistency and reproducible builds. |
| `app/README.md` | 648 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `app/test/account_scope_test.dart` | 316 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/app_color_themes_test.dart` | 741 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/canvas_engine_test.dart` | 6,090 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/editor_surface_layout_test.dart` | 2,674 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/editor_v2_document_test.dart` | 7,471 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/editor_v2_ink_painter_test.dart` | 2,657 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/editor_v2_workspace_tools_test.dart` | 4,874 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/flashcard_page_test.dart` | 3,237 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/folder_cover_art_test.dart` | 1,788 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/fountain_ink_dynamics_test.dart` | 1,438 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/ink_pipeline_test.dart` | 5,750 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/ink_renderer_test.dart` | 1,045 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/lasso_geometry_test.dart` | 1,495 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/live_ink_widget_test.dart` | 11,263 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/new_note_route_test.dart` | 1,128 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/note_content_compatibility_test.dart` | 8,775 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/rendering_geometry_test.dart` | 4,618 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/sticker_transparency_test.dart` | 799 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `app/test/workspace_layout_test.dart` | 1,113 | Test/fixture | Low | Verify coverage and determinism; keep tests that protect existing behavior. |
| `docs/editor-engine-rebuild.md` | 4,937 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `docs/IN_APP_SCREENSHOT_TO_CANVAS.md` | 2,913 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `docs/repository-dry-size-optimization.md` | 4,615 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `README.md` | 899 | Documentation/project metadata | Low | Check links and claims against actual code; update only when related behavior changes. |
| `website/.env.example` | 31 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/.env.example` | 0 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/api/docs/[filename]/route.ts` | 1,517 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/api/download/[assetId]/route.ts` | 1,757 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/api/feedback/route.ts` | 3,316 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/api/notifications/route.ts` | 1,131 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/api/releases/latest/route.ts` | 1,547 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/docs/page.tsx` | 3,973 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/download/page.tsx` | 1,060 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/faqs/page.tsx` | 6,571 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/features/page.tsx` | 2,147 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/founder/page.tsx` | 2,231 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/globals.css` | 46,312 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/how-it-works/page.tsx` | 4,623 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/layout.tsx` | 4,432 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/page.tsx` | 628 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/robots.ts` | 280 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/app/sitemap.ts` | 454 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/components/BrandLoader.tsx` | 672 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/components/FeedbackCenter.tsx` | 4,534 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/components/Icon.tsx` | 3,835 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/components/MobileNav.tsx` | 849 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/components/MotionHero.tsx` | 8,942 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/components/NotificationCenter.tsx` | 2,706 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/components/ReleaseCenter.tsx` | 4,066 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/components/Reveal.tsx` | 192 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/components/SectionIndex.tsx` | 855 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/components/ThemeToggle.tsx` | 2,053 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/FEEDBACK_SETUP.md` | 1,207 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/package.json` | 572 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/public/googled7a4d739c13c2090.html` | 54 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/public/snote-logo.png` | 1,298,678 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/scripts/guard-design.mjs` | 1,276 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |
| `website/tsconfig.json` | 299 | Website/showcase | Medium | Inspect imports/assets/routes and production bundle; run lint/typecheck/build. |

## Required next pass

1. For each Dart source file, record imports, public declarations, callers, duplicated logic, and candidate change in a source-reviewed ledger; do not infer callers from path names.
2. Separate handwritten source from generated platform runners, generated files, lockfiles, bundled assets, and vendored code before any deduplication.
3. Audit editor/canvas hot paths first, then PDF/data flows, platform setup, website assets, and dependency/configuration files.
4. Establish baseline test/build outcomes and artifact bytes from a completed workflow before accepting size/performance changes.
5. Mark an item optimized only after tests and platform validation pass. This register is a starting inventory, not a claim every file has been semantically reviewed.
