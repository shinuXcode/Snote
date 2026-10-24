# Phase Three — DRY Refactor Log

## Change 001: deduplicate ink-radius pressure scaling

- **File:** `app/lib/canvas_engine/ink_renderer.dart`
- **Method:** `InkRenderer._radiusFor`
- **Before:** The same pressure-width multiplication appeared in the `index > 0` and `else` branches.
- **Change:** Keep the velocity adjustment conditional on `index > 0`, then apply the shared pressure-width multiplication once for the non-fountain path.
- **Behavior contract:** First points still receive pressure scaling only. Later points still receive velocity scaling first and pressure scaling second. The fountain-specific branch is unchanged.
- **Scope:** One method; no public API, stored note format, dependencies, editor routing, or painter lifecycle changes.
- **Validation:** The Phase Two baseline CI passed on commit `881592e1865474f0346d9edf4d23bd80554e5c69`. The refactor commit must pass its own formatting, analyzer, test, and platform smoke-build workflow before acceptance.
- **Status:** Implemented on `refactor/phase3-ink-radius-dry`; awaiting branch CI. This is an initial low-risk cleanup, not completion of the full DRY audit.

## Remaining audit work

- Trace routes and callers for legacy editor and Editor V2 before considering shared abstractions.
- Compare the two ink painters by behavior and coordinate/lifecycle assumptions.
- Audit persistence/serialization with round-trip and backward-compatibility fixtures.
- Map PDF and webview package use before considering dependency changes.
- Compare CI setup scripts and generated platform configuration before consolidating them.
- Scan website CSS and asset references separately from Dart refactoring.
- Record tests and measured outcomes for each accepted change; avoid broad extractions without evidence.
