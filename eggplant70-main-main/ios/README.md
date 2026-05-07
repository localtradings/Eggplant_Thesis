# iOS Eggplant Detector

This is the native iOS build of the field-pilot eggplant disease classifier.

It uses:

- `AVFoundation` for the live camera
- `TensorFlowLiteSwift` for inference
- your bundled `model.tflite`
- your `labels.txt`

## Files you care about

- `EggplantDetector/MainViewController.swift`
- `EggplantDetector/TFLiteClassifier.swift`
- `EggplantDetector/CameraService.swift`

## Open on a Mac

This project was scaffolded on Windows, so it was not built here. To run it on iPhone or the iOS Simulator:

1. Install `xcodegen` if you do not already have it.
2. From the `ios` folder, run:

```bash
xcodegen generate
pod install
open EggplantDetector.xcworkspace
```

3. In Xcode, pick an iPhone or iOS simulator and run.

## Notes

- The iOS app now mirrors Android's trust-first flow with `Live Scan` and `Photo Diagnosis` modes.
- Shared preprocessing and diagnosis thresholds are documented in `../MODEL_CONTRACT.md`.
- Keep `EggplantDetector/Resources/model.tflite` and `EggplantDetector/Resources/labels.txt` in sync with the repo-root assets by running:

```bash
python3 ../scripts/sync_model_assets.py
```
