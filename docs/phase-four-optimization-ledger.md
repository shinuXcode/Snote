# Phase Four — File-by-File Optimization Ledger

## Scope and rules

- Base branch: `main`
- Base commit: `25d1277e3b0035a8ddf51591d2651ba72ad1a77e`
- Working branch: `refactor/phase4-file-by-file-optimization`
- Inventory method: recursive Git tree API; complete response (`truncated=false`).
- Tracked blobs inventoried: **152**.
- Status meanings: **Not audited** = not yet read with callers; **Audited** = reviewed, no change yet; **Changed** = edited, validation pending; **Validated** = reviewed in context and relevant checks passed; **Blocked** = evidence/tool/device unavailable.
- A successful compile alone does not validate runtime behavior. No handwriting/PDF runtime performance is claimed without device measurements.
- Do not remove dependencies/assets until references, conditional imports, generated/runtime paths, manifests and platform usage are checked.
- Keep edits on this branch and submit for review; do not write directly to `main`.

## Baseline snapshot

| Measure | Recorded value | Evidence / caveat |
|---|---:|---|
| Git tree commit | `25d1277e3b0035a8ddf51591d2651ba72ad1a77e` | Main branch at inventory time |
| Tracked files (blobs) | 152 | Recursive tree, not truncated |
| Dart files | 102 | All tracked paths |
| App library files | 83 | `app/lib/**` |
| Test-path files | 19 | Path-based count; inspect test types separately |
| Website files | 34 | `website/**` |
| Largest tracked file | `website/public/snote-logo.png` — 1298678 bytes | Source-tree file size, not release size |
| APK baseline | 129,841,617 bytes (universal APK) | Phase Two CI run #40078790734; SHA-256 `3eb18fb2a4272bcfa380198f7a6df12f8e0a2b5e49e5b18d1de374bf89d0fa31`; compare only against same build type/toolchain |
| Web output baseline | 46,511,458 bytes uncompressed | Phase Two CI run #40078790734; exact build/toolchain parity required |
| Device performance baseline | Not measured | Startup, memory, stylus latency/frame timing, PDF open/scroll require repeatable device/emulator measurements |
| AAB/per-ABI/native entry breakdown | Pending extraction | Do not infer from compressed Actions artifact ZIP sizes |

## Initial audit order (high-impact, low-risk first)

1. Renderer and input path: `app/lib/canvas_engine/ink_renderer.dart`, `app/lib/canvas_engine/input/**`, `app/lib/canvas_engine/algorithms/**`, `app/lib/canvas_engine/widgets/snote_canvas.dart`.
2. Editor routing/lifecycle: `app/lib/features/notes/editor_v2/**`, `app/lib/features/notes/note_editor_page.dart`, callers/navigation/state providers.
3. Stroke persistence and compatibility: `app/lib/canvas_engine/models/stroke.dart`, `stroke_codec.dart`, persistence/repository callers and migration/tests.
4. PDF pipeline: `app/lib/features/pdf/**`, PDF rendering/cache/thumbnail call sites, tests.
5. Dependency and release configuration: `app/pubspec.yaml`, lockfile, Android Gradle/manifests, web and desktop build config, CI/release workflows.
6. Website source/assets/CSS after app behavior-sensitive paths have targeted coverage.

For every proposed change, record category (correctness, duplication, performance, memory, binary size, maintainability), evidence, caller review, tests, platform checks, before/after measurements, and remaining risks in this ledger or a linked audit note.

## File-by-file inventory

| File | Bytes | Status | Category | Evidence / responsibility and callers | Change / validation / risks |
|---|---:|---|---|---|---|
| `.github/scripts/configure_beta_android.py` | 15269 | Not audited | Pending | — | — |
| `.github/workflows/beta.yml` | 17139 | Not audited | Pending | — | — |
| `.github/workflows/ci.yml` | 13140 | Not audited | Pending | — | — |
| `.github/workflows/release.yml` | 12777 | Not audited | Pending | — | — |
| `app/assets/branding/snote-logo.png` | 2171 | Not audited | Pending | — | — |
| `app/lib/app/app_entry.dart` | 241 | Not audited | Pending | — | — |
| `app/lib/app/theme_controller.dart` | 3287 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/algorithms/adaptive_stabilizer.dart` | 1713 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/algorithms/bezier_smoother.dart` | 741 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/algorithms/ink_dynamics.dart` | 800 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/algorithms/lasso_geometry.dart` | 4568 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/algorithms/shape_recognizer.dart` | 3555 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/algorithms/stroke_geometry.dart` | 4235 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/algorithms/velocity_calculator.dart` | 1149 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/ink_renderer.dart` | 9808 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/input/ink_gesture_policy.dart` | 790 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/input/ink_input_pipeline.dart` | 5041 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/input/ink_prediction.dart` | 1781 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/input/ink_sample.dart` | 1775 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/input/palm_rejection.dart` | 412 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/input/stroke_sample_buffer.dart` | 1494 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/input/stylus_gesture_lock.dart` | 850 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/input/viewport_transform.dart` | 597 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/models/pen_config.dart` | 16753 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/models/stroke_codec.dart` | 4819 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/models/stroke.dart` | 1858 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/painters/canvas_painter.dart` | 46660 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/performance/ink_engine_metrics.dart` | 819 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/performance/stroke_spatial_index.dart` | 1831 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/performance/writing_performance.dart` | 5015 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/persistence/ink_commit_queue.dart` | 667 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/widgets/notebook_viewport.dart` | 4586 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/widgets/page_background.dart` | 4831 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/widgets/snote_canvas_controller.dart` | 3845 | Not audited | Pending | — | — |
| `app/lib/canvas_engine/widgets/snote_canvas.dart` | 57807 | Not audited | Pending | — | — |
| `app/lib/core/config/account_scope.dart` | 254 | Not audited | Pending | — | — |
| `app/lib/core/config/app_version.dart` | 212 | Not audited | Pending | — | — |
| `app/lib/core/security/note_lock_service.dart` | 2329 | Not audited | Pending | — | — |
| `app/lib/core/settings/app_settings.dart` | 6080 | Not audited | Pending | — | — |
| `app/lib/data/local/database.dart` | 4656 | Not audited | Pending | — | — |
| `app/lib/data/local/file_document_repository.dart` | 3972 | Not audited | Pending | — | — |
| `app/lib/data/local/folder_repository.dart` | 18388 | Not audited | Pending | — | — |
| `app/lib/data/local/local_file_store_native.dart` | 1381 | Not audited | Pending | — | — |
| `app/lib/data/local/local_file_store_stub.dart` | 724 | Not audited | Pending | — | — |
| `app/lib/data/local/local_file_store.dart` | 93 | Not audited | Pending | — | — |
| `app/lib/data/local/note_repository.dart` | 12592 | Not audited | Pending | — | — |
| `app/lib/data/local/notebook_transfer_service.dart` | 7119 | Not audited | Pending | — | — |
| `app/lib/data/local/notification_repository.dart` | 2944 | Not audited | Pending | — | — |
| `app/lib/data/local/schema.dart` | 2113 | Not audited | Pending | — | — |
| `app/lib/data/local/shared_media_path_reader_io.dart` | 168 | Not audited | Pending | — | — |
| `app/lib/data/local/shared_media_path_reader_stub.dart` | 194 | Not audited | Pending | — | — |
| `app/lib/data/local/shared_media_path_reader.dart` | 105 | Not audited | Pending | — | — |
| `app/lib/features/folders/folder_cover_art.dart` | 5827 | Not audited | Pending | — | — |
| `app/lib/features/folders/folder_cover_library_page.dart` | 10298 | Not audited | Pending | — | — |
| `app/lib/features/folders/folder_cover_repository.dart` | 2764 | Not audited | Pending | — | — |
| `app/lib/features/folders/folder_tree_view.dart` | 11862 | Not audited | Pending | — | — |
| `app/lib/features/folders/folders_page.dart` | 7626 | Not audited | Pending | — | — |
| `app/lib/features/notes/editor_v2/editor_v2_document.dart` | 4715 | Not audited | Pending | — | — |
| `app/lib/features/notes/editor_v2/editor_v2_ink_painter.dart` | 83313 | Not audited | Pending | — | — |
| `app/lib/features/notes/editor_v2/editor_v2_page.dart` | 416334 | Not audited | Pending | — | — |
| `app/lib/features/notes/editor_v2/multi_split_workspace.dart` | 3909 | Not audited | Pending | — | — |
| `app/lib/features/notes/editor_v2/selection_text_recognizer_io.dart` | 1287 | Not audited | Pending | — | — |
| `app/lib/features/notes/editor_v2/selection_text_recognizer_stub.dart` | 197 | Not audited | Pending | — | — |
| `app/lib/features/notes/editor_v2/selection_text_recognizer.dart` | 333 | Not audited | Pending | — | — |
| `app/lib/features/notes/editor_v2/smart_pages_catalog.dart` | 9550 | Not audited | Pending | — | — |
| `app/lib/features/notes/new_note_route.dart` | 772 | Not audited | Pending | — | — |
| `app/lib/features/notes/nextgen_editor_route.dart` | 3024 | Not audited | Pending | — | — |
| `app/lib/features/notes/note_content_compatibility.dart` | 11850 | Not audited | Pending | — | — |
| `app/lib/features/notes/note_editor_page.dart` | 296631 | Not audited | Pending | — | — |
| `app/lib/features/notes/notes_home_page.dart` | 90578 | Not audited | Pending | — | — |
| `app/lib/features/notes/workspace_layout.dart` | 584 | Not audited | Pending | — | — |
| `app/lib/features/onboarding/welcome_guide_page.dart` | 8770 | Not audited | Pending | — | — |
| `app/lib/features/pdf/pdf_annotation_page.dart` | 22979 | Not audited | Pending | — | — |
| `app/lib/features/settings/settings_page.dart` | 26605 | Not audited | Pending | — | — |
| `app/lib/features/share/qr_import_page.dart` | 5351 | Not audited | Pending | — | — |
| `app/lib/features/share/qr_transfer_page.dart` | 3928 | Not audited | Pending | — | — |
| `app/lib/features/tools/alarm_notification_service.dart` | 6116 | Not audited | Pending | — | — |
| `app/lib/features/tools/flashcard_page.dart` | 12741 | Not audited | Pending | — | — |
| `app/lib/features/tools/floating_timer_panel.dart` | 30760 | Not audited | Pending | — | — |
| `app/lib/features/tools/mind_map_page.dart` | 16836 | Not audited | Pending | — | — |
| `app/lib/features/tools/screen_capture.dart` | 280 | Not audited | Pending | — | — |
| `app/lib/features/tools/screenshot_import_page.dart` | 5783 | Not audited | Pending | — | — |
| `app/lib/features/tools/web_search_panel.dart` | 15206 | Not audited | Pending | — | — |
| `app/lib/features/trash/trash_page.dart` | 2226 | Not audited | Pending | — | — |
| `app/lib/features/updates/update_center_page.dart` | 13197 | Not audited | Pending | — | — |
| `app/lib/main.dart` | 9769 | Not audited | Pending | — | — |
| `app/lib/ui/snote_logo.dart` | 811 | Not audited | Pending | — | — |
| `app/lib/ui/snote_theme.dart` | 8622 | Not audited | Pending | — | — |
| `app/native_android/AndroidManifest.xml` | 2998 | Not audited | Pending | — | — |
| `app/native_android/MainActivity.kt` | 4874 | Not audited | Pending | — | — |
| `app/native_android/ScreenCaptureBridge.kt` | 900 | Not audited | Pending | — | — |
| `app/native_android/ScreenCaptureService.kt` | 8190 | Not audited | Pending | — | — |
| `app/pubspec.yaml` | 1175 | Not audited | Pending | — | — |
| `app/README.md` | 648 | Not audited | Pending | — | — |
| `app/test/account_scope_test.dart` | 316 | Not audited | Pending | — | — |
| `app/test/app_color_themes_test.dart` | 741 | Not audited | Pending | — | — |
| `app/test/canvas_engine_test.dart` | 6090 | Not audited | Pending | — | — |
| `app/test/editor_surface_layout_test.dart` | 2674 | Not audited | Pending | — | — |
| `app/test/editor_v2_document_test.dart` | 7471 | Not audited | Pending | — | — |
| `app/test/editor_v2_ink_painter_test.dart` | 2657 | Not audited | Pending | — | — |
| `app/test/editor_v2_workspace_tools_test.dart` | 4874 | Not audited | Pending | — | — |
| `app/test/flashcard_page_test.dart` | 3237 | Not audited | Pending | — | — |
| `app/test/folder_cover_art_test.dart` | 1788 | Not audited | Pending | — | — |
| `app/test/fountain_ink_dynamics_test.dart` | 1438 | Not audited | Pending | — | — |
| `app/test/ink_pipeline_test.dart` | 5750 | Not audited | Pending | — | — |
| `app/test/ink_renderer_test.dart` | 1045 | Not audited | Pending | — | — |
| `app/test/lasso_geometry_test.dart` | 1495 | Not audited | Pending | — | — |
| `app/test/live_ink_widget_test.dart` | 11263 | Not audited | Pending | — | — |
| `app/test/new_note_route_test.dart` | 1128 | Not audited | Pending | — | — |
| `app/test/note_content_compatibility_test.dart` | 8775 | Not audited | Pending | — | — |
| `app/test/rendering_geometry_test.dart` | 4618 | Not audited | Pending | — | — |
| `app/test/sticker_transparency_test.dart` | 799 | Not audited | Pending | — | — |
| `app/test/workspace_layout_test.dart` | 1113 | Not audited | Pending | — | — |
| `docs/editor-engine-rebuild.md` | 4937 | Not audited | Pending | — | — |
| `docs/IN_APP_SCREENSHOT_TO_CANVAS.md` | 2913 | Not audited | Pending | — | — |
| `docs/repository-dry-size-optimization.md` | 4615 | Not audited | Pending | — | — |
| `docs/repository-file-inventory.md` | 32309 | Not audited | Pending | — | — |
| `README.md` | 899 | Not audited | Pending | — | — |
| `website/.env.example` | 31 | Not audited | Pending | — | — |
| `website/app/.env.example` | 0 | Not audited | Pending | — | — |
| `website/app/api/docs/[filename]/route.ts` | 1517 | Not audited | Pending | — | — |
| `website/app/api/download/[assetId]/route.ts` | 1757 | Not audited | Pending | — | — |
| `website/app/api/feedback/route.ts` | 3316 | Not audited | Pending | — | — |
| `website/app/api/notifications/route.ts` | 1131 | Not audited | Pending | — | — |
| `website/app/api/releases/latest/route.ts` | 1547 | Not audited | Pending | — | — |
| `website/app/docs/page.tsx` | 3973 | Not audited | Pending | — | — |
| `website/app/download/page.tsx` | 1060 | Not audited | Pending | — | — |
| `website/app/faqs/page.tsx` | 6571 | Not audited | Pending | — | — |
| `website/app/features/page.tsx` | 2147 | Not audited | Pending | — | — |
| `website/app/founder/page.tsx` | 2231 | Not audited | Pending | — | — |
| `website/app/globals.css` | 46312 | Not audited | Pending | — | — |
| `website/app/how-it-works/page.tsx` | 4623 | Not audited | Pending | — | — |
| `website/app/layout.tsx` | 4432 | Not audited | Pending | — | — |
| `website/app/page.tsx` | 628 | Not audited | Pending | — | — |
| `website/app/robots.ts` | 280 | Not audited | Pending | — | — |
| `website/app/sitemap.ts` | 454 | Not audited | Pending | — | — |
| `website/components/BrandLoader.tsx` | 672 | Not audited | Pending | — | — |
| `website/components/FeedbackCenter.tsx` | 4534 | Not audited | Pending | — | — |
| `website/components/Icon.tsx` | 3835 | Not audited | Pending | — | — |
| `website/components/MobileNav.tsx` | 849 | Not audited | Pending | — | — |
| `website/components/MotionHero.tsx` | 8942 | Not audited | Pending | — | — |
| `website/components/NotificationCenter.tsx` | 2706 | Not audited | Pending | — | — |
| `website/components/ReleaseCenter.tsx` | 4066 | Not audited | Pending | — | — |
| `website/components/Reveal.tsx` | 192 | Not audited | Pending | — | — |
| `website/components/SectionIndex.tsx` | 855 | Not audited | Pending | — | — |
| `website/components/ThemeToggle.tsx` | 2053 | Not audited | Pending | — | — |
| `website/FEEDBACK_SETUP.md` | 1207 | Not audited | Pending | — | — |
| `website/package.json` | 572 | Not audited | Pending | — | — |
| `website/public/googled7a4d739c13c2090.html` | 54 | Not audited | Pending | — | — |
| `website/public/snote-logo.png` | 1298678 | Not audited | Pending | — | — |
| `website/scripts/guard-design.mjs` | 1276 | Not audited | Pending | — | — |
| `website/tsconfig.json` | 299 | Not audited | Pending | — | — |

## First observations (not yet changes)

- `app/lib/features/notes/editor_v2/editor_v2_page.dart` is the largest Dart source file in the tree (416334 bytes). Size alone is not evidence that splitting it is safe; inspect responsibilities and callers first.
- `app/lib/features/notes/note_editor_page.dart` and `app/lib/features/notes/editor_v2/editor_v2_page.dart` both appear to be editor entry points by path. Trace navigation and feature flags before any consolidation.
- `app/lib/features/notes/editor_v2/editor_v2_ink_painter.dart` and `app/lib/canvas_engine/painters/canvas_painter.dart` are candidates for comparison only; no shared implementation should be extracted until geometry, lifecycle, repaint invalidation and tests are compared.
- `app/pubspec.yaml` contains both `pdf` and `pdfx`, plus both `webview_flutter` and `flutter_inappwebview`. This is not proof of redundancy; trace each platform-specific call site and plugin requirements before changing them.
- `website/public/snote-logo.png` is 1298678 bytes. Asset compression is a possible binary/transfer-size investigation, but preserve the exact branding and all references.
- No code has been changed by this initial inventory commit. These are hypotheses to validate, not findings of dead code or proven bottlenecks.
