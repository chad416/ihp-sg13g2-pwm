"""Shrink the committed PNGs: palette quantisation (128 colours, no dithering).

Layout renders and plots use few distinct colours, so this keeps them legible
at a fraction of the size. Images that are already palette-based are skipped.
Usage: python3 scripts/compress_png.py <png> [<png> ...]
"""

import sys
from pathlib import Path

from PIL import Image

for arg in sys.argv[1:]:
    path = Path(arg)
    with Image.open(path) as im:
        if im.mode == "P":
            continue
        before = path.stat().st_size
        q = im.convert("RGB").quantize(colors=128, method=Image.Quantize.MEDIANCUT,
                                       dither=Image.Dither.NONE)
    q.save(path, optimize=True)
    print(f"{path.name}: {before // 1024} KB -> {path.stat().st_size // 1024} KB")
