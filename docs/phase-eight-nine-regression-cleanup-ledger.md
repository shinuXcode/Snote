# Phases Eight and Nine — Regression Prevention and Safe Cleanup Ledger

## Status

- Phase Eight: **CI-backed checks exist and recently passed**, but the current Phase Seven PR is awaiting CI. Physical-device handwriting and PDF behavior remain unverified.
- Phase Nine: **guardrails established; file-by-file safe cleanup is not complete**. No file or asset should be removed based on size, naming, or an apparently unused import alone.

## Current verification evidence

| Check | Latest known evidence | Status / limitation |
|---|---|---|
| Dart format | Phase Six PR #37 CI completed successfully; Flutter smoke job ran the formatter check. | CI pass on documentation-only commit; not a claim that every source file was newly changed or reformatted. |
| Flutter analyzer | Phase Six PR #37 CI completed successfully; analyzer step passed. | CI pass; no device runtime guarantee. |
| Flutter tests | Phase Six PR #37 CI completed successfully; test step passed. | Existing automated tests only; does not replace stylus/PDF manual validation. |
| Android APK release build | Phase Six PR #37 CI completed successfully. | Build success only. |
| Android split-per-ABI APK and AAB experiments | Phase Six PR #37 CI completed successfully. | Measurements are documented in Phase Five; no change to release distribution policy. |
| Web production build | Phase Six PR #37 CI completed successfully, including website typecheck/build and Flutter web build. | Hosted browser runtime and transfer-cache behavior still require verification. |
| Linux desktop build | Phase Six PR #37 CI completed successfully. | Runtime coverage on actual Linux desktop not separately documented. |
| Windows build | Phase Six PR #37 CI completed successfully. | CI smoke build; interactive runtime behavior not proven. |
| iOS unsigned build and macOS build | Phase Six PR #37 CI completed successfully. | Unsigned iOS build is not a signed/released iOS artifact; Apple device runtime not verified. |
| Stylus event-to-pixel latency, palm rejection, pressure, page stability | Functional tests exist for live ink and input pipeline. | Device trace/physical test outstanding; do not claim latency or frame-time improvements. |
| PDF open/scroll/zoom/cache/disposal on large documents | PDF annotation source and automated test/build coverage exist. | Real-device/emulator workload measurements outstanding. |
| Before/after release artifact sizes | Phase Five audit has exact universal APK and web output figures plus follow-up measurements. | Repeated controlled builds are required before attributing small changes. |

## Regression matrix before any runtime refactor

| Critical behavior | Required check |
|---|---|
| Immediate live strokes | Live-ink widget test plus physical stylus run |
| Pressure-sensitive ink and smooth curves | Ink pipeline/renderer/geometry tests plus ballpoint/fountain/highlighter run |
| Palm rejection and finger behavior | Input policy/widget tests plus physical device test |
| Undo/redo and persisted strokes | Stroke codec, undo/redo, reopen and data round-trip tests |
| Canvas lock, zoom, pan, page stability | Widget/integration checks on touch and stylus input |
| Offline-first storage and migration compatibility | Repository tests, migration fixtures, import/export round-trip |
| PDF render, annotation, scroll, zoom and navigation | PDF tests plus fixed-document device/emulator workload |
| Cross-platform startup/navigation | Platform smoke builds plus runtime checks where an emulator/device is available |

## Safe cleanup checklist

Before removing a file, asset, dependency, class, or module, record all of the following:

- [ ] Recursive tracked-file inventory and current base commit.
- [ ] Exact import/call-site search, including test files and feature routes.
- [ ] Conditional imports, platform plugin registration, manifests, generated references, reflection and runtime asset paths checked.
- [ ] Feature behavior and supported platforms confirmed.
- [ ] Stored-data formats, migrations, licenses, signing credentials and compatibility resources preserved.
- [ ] One small change isolated on a dedicated branch.
- [ ] Relevant formatter/analyzer/tests and affected platform builds passed.
- [ ] Artifact size or performance impact measured with same build mode/toolchain when applicable.
- [ ] Diff reviewed for unrelated user changes and accidental lockfile churn.

## Open blockers

1. No repeatable physical-device performance trace is recorded for stylus latency, frame timing, or long-session memory.
2. No controlled repeated-build experiment attributes a material APK/web size reduction to a specific optimization.
3. The file-by-file ledger contains unaudited files; source-tree inventory is not a semantic audit.
4. Device/emulator PDF workload and handwriting behavior must remain marked untested until actual evidence is recorded.

## Completion rule

Phases Eight and Nine remain open until changed behavior has regression coverage, supported-platform checks are recorded, the full tracked-source audit has explicit audited/blocked statuses, and each cleanup has evidence and a measured impact where measurable. A green CI run is necessary but not sufficient.
