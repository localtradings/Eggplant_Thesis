# Eggplant Model Contract

This repository treats the bundled `model.tflite` and `labels.txt` in the repo root as the source of truth. Platform copies under Android and iOS must stay byte-for-byte identical to those root assets.

## Preprocessing

- Camera frames are center-cropped to a square before inference.
- The square crop is resized to the model's declared tensor size at runtime.
- Inputs are encoded as RGB.
- Float models receive normalized `0..1` channel values.
- Byte outputs are decoded into scores before trust rules run.

## Output Interpretation

- The model is treated as one score per class in `labels.txt`.
- The app only returns a confirmed disease when:
  - brightness is within the allowed range
  - the top score is at least `0.72`
  - the gap between the top two classes is at least `0.12`
- Otherwise the app shows either:
  - `needsRetake`
  - `uncertain`

## Shared Trust Rules

- Too dark: `needsRetake(increaseLight)`
- Too bright / glare: `needsRetake(reduceGlare)`
- Weak live score: `needsRetake(frameSingleLeaf)`
- Weak photo score: `uncertain(lowConfidence)`
- Close top scores: `uncertain(ambiguous)`

These values are implemented in `DiagnosisModels.kt` on Android and `DiagnosisModels.swift` on iOS and should be changed together.
