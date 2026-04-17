#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import shutil
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE_FILES = {
    "model.tflite": ROOT / "model.tflite",
    "labels.txt": ROOT / "labels.txt",
}
TARGETS = {
    "android": ROOT / "app" / "src" / "main" / "assets",
    "ios": ROOT / "ios" / "EggplantDetector" / "Resources",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_sources_exist() -> None:
    missing = [str(path) for path in SOURCE_FILES.values() if not path.exists()]
    if missing:
        raise FileNotFoundError(f"Missing source assets: {', '.join(missing)}")


def sync(write: bool) -> int:
    ensure_sources_exist()
    mismatches: list[str] = []

    for name, source in SOURCE_FILES.items():
        source_hash = sha256(source)
        for target_name, target_dir in TARGETS.items():
            target_path = target_dir / name
            if not target_path.exists():
                mismatches.append(f"{target_name}:{name} missing")
                if write:
                    target_dir.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target_path)
                continue

            target_hash = sha256(target_path)
            if target_hash != source_hash:
                mismatches.append(f"{target_name}:{name} hash mismatch")
                if write:
                    shutil.copy2(source, target_path)

    if mismatches and not write:
        print("Asset drift detected:")
        for mismatch in mismatches:
            print(f" - {mismatch}")
        return 1

    if mismatches and write:
        print("Synchronized model assets:")
        for mismatch in mismatches:
            print(f" - {mismatch}")
        return 0

    print("Model assets are in sync.")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate or sync model assets across Android and iOS.")
    parser.add_argument(
        "--write",
        action="store_true",
        help="Overwrite platform copies with the repo-root source assets.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    return sync(write=args.write)


if __name__ == "__main__":
    sys.exit(main())
