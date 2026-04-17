# Eggplant Disease App

This repository contains matching Android and iOS apps for field-pilot-style eggplant leaf disease classification with TensorFlow Lite.

## Current product workflow

- `Live Scan`: throttled live inference with guidance when the frame is weak
- `Photo Diagnosis`: deliberate capture, frozen-frame review, and a stable result card
- Trust-first diagnosis states:
  - `confirmed`
  - `uncertain`
  - `needsRetake`

The apps do not force a disease label when the frame is too dark, too bright, low-confidence, or ambiguous.

## Source-of-truth assets

The repo-root files are canonical:

- `model.tflite`
- `labels.txt`

Platform copies must match the root assets:

- Android: `app/src/main/assets/`
- iOS: `ios/EggplantDetector/Resources/`

Check for drift:

```bash
python3 scripts/sync_model_assets.py
```

Overwrite platform copies from the repo root:

```bash
python3 scripts/sync_model_assets.py --write
```

## Model contract

The preprocessing and diagnosis rules are documented in [MODEL_CONTRACT.md](MODEL_CONTRACT.md).

At a high level:

- center crop to a square
- resize to the model tensor size
- RGB channels
- normalized `0..1` floats for float models
- confidence threshold `0.72`
- ambiguity margin `0.12`

## Android setup

- Open the repository in Android Studio.
- The project expects Android Gradle Plugin `8.5.2` and Kotlin `1.9.24`.
- The repository does not currently include a Gradle wrapper, so Android Studio or a matching local Gradle installation is required.

## iOS setup

From `ios/`:

```bash
xcodegen generate
pod install
open EggplantDetector.xcworkspace
```

The iOS app targets iOS 15.0 and uses `TensorFlowLiteSwift`.

## Regression scaffold

The evaluation manifest lives in [evaluation/manifest.csv](evaluation/manifest.csv). Add real field images under `evaluation/` and keep the manifest updated before changing thresholds or preprocessing.

## Legacy conversion

The original Keras model is still present as `eggplant_model.h5`. If you need to regenerate `model.tflite`:

```bash
python3 convert_to_tflite.py
```
