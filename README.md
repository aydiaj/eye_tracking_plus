## Eye Tracking Proctor for Flutter (community fork)

> A maintained fork of [`eye_tracking`](https://github.com/Piyushhhhh/eye_tracking) (MIT-licensed)
> adapted for **anti-cheating / remote-proctoring** use cases.  
> This fork adds attention/screen state signals, stable gaze confidence, real calibration accuracy,
> warm-up gating, and ready-to-use signals for remote proctoring.

### ✨ What’s new 

- 📡 **Lifecycle & state stream**
  - New getStateStream()
  - emits initializing → ready → warmingUp → tracking / paused / calibrating / error
  - flips to tracking only after the first valid gaze sample.
- 👁️ **Attention-aware confidence**
  - Computes confidence per frame using page Attention gate + focus, Viewport bounds, and frame freshness.
  - Let you build per-tick metrics (off-screen time, face-missing time, look-away time, copy/paste events)
    and compute a proctoring score for anti-cheating scenarios.
- 🎯 **Real calibration accuracy**
  - Train + eval around each point
  - Calibration Accuracy is normalized by viewport diagonal.
- ⚙️ **Config & extensibility**
  - New setTracker, setRegression, addTrackerModule, and addRegressionModule.
- ⚡ **Startup polish**
  - Simplified auto-calibration (center point) for quicker boot.
  - Silent pre-warm so first “Start” is smooth (no UI jank)