"""Download the Daphnet Freezing of Gait dataset (UCI #245) into research/data/."""

from __future__ import annotations

import io
import urllib.request
import zipfile
from pathlib import Path

URL = "https://archive.ics.uci.edu/static/public/245/daphnet+freezing+of+gait.zip"
DEST = Path(__file__).resolve().parent / "data"


def main() -> None:
    DEST.mkdir(exist_ok=True)
    if (DEST / "dataset_fog_release" / "dataset").exists():
        print("Daphnet already present.")
        return
    print(f"Downloading {URL}")
    with urllib.request.urlopen(URL) as r:
        zipfile.ZipFile(io.BytesIO(r.read())).extractall(DEST)
    print(f"Extracted to {DEST}")


if __name__ == "__main__":
    main()
