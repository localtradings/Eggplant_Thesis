# Evaluation Set

This folder is the fixed regression scaffold for field-pilot validation.

## Expected contents

- `manifest.csv`: the canonical list of evaluation images and expected outcomes
- image files captured under realistic conditions:
  - one clear healthy leaf
  - one clear example per disease class
  - ambiguous or cluttered frames
  - low-light and glare cases

## How to use it

1. Add captured test images to this folder.
2. Update `manifest.csv` with the expected label or non-diagnosis state.
3. Run the same images through Android and iOS before changing preprocessing thresholds.
4. Keep at least one example for each of:
   - `confirmed`
   - `uncertain`
   - `needsRetake`

No field images are committed yet in this repository, but the manifest format is fixed so pilot samples can be added without redefining the workflow.
