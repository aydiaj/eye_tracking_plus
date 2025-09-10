# Changelog

> This fork is based on the upstream `eye_tracking` package (MIT). See README for attribution.

## [0.1.0] - 2025-09-10 — Init forked release
## [0.1.1] - 2025-09-10 — First forked release

### Added
- **Lifecycle & state stream**: `getStateStream()` now emits `initializing → ready → warmingUp → tracking / paused / calibrating / error`. `warmingUp` flips to `tracking` only after the **first valid gaze sample**.
- **Attention-aware confidence (Web)**: per-frame confidence blends **page visibility & focus**, **viewport in-bounds**, and **frame freshness**; smoothed with two-rate EMA and capped (~0.90).
- **Real calibration accuracy**: train+eval around each calibration point; returns a true **0–1** score normalized by **viewport diagonal**, cached for fast reads.
- **Extensibility**: `setTracker`, `setRegression`, `addTrackerModule`, `addRegressionModule`.
- **Robust timestamps**: DOM High-Res → epoch via page-start offset; ~30 FPS throttling.

### Changed
- `setAccuracyMode('fast')` now maps to **`threadedRidge`** (instead of `linear`).
- Auto-calibration simplified (center point) to reduce boot time.
- Replaced fixed 0.8/0.3 confidence stub with the attention-aware model.

### Fixed
- **“Ready before ready”** glitch: tracking no longer reports ready until real samples arrive.
- Reduced UI jank on start by gating state & throttling emits.

### Migration notes
- Handle the **`warmingUp`** state before assuming live tracking.
- Confidence scale is more conservative (max ~0.90). Review any thresholds (e.g. treat **>0.6** as “usable”).
- `getCalibrationAccuracy()` now returns **measured** values; remove any hardcoded defaults.
