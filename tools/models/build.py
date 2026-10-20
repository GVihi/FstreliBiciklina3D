#!/usr/bin/env python3
"""Build models with Blender as a Python module (bpy).

    python tools/models/build.py test_crate        build one model
    python tools/models/build.py all               build every model in tools/models/models/
    python tools/models/build.py test_crate --no-preview
    python tools/models/build.py palette           write the palette swatch image

Each model is a file in tools/models/models/ that defines
    INFO = {"category": "prop"}      (budget category, see kit/palette.py BUDGETS)
    def build(): ...                 (builds the geometry with the kit; leaves it in the scene)
Output: assets/models/<name>.glb and docs/model_previews/<name>.png
"""
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from kit import geo, output, palette  # noqa: E402


def load_model(name: str):
    path = HERE / "models" / (name + ".py")
    if not path.exists():
        raise SystemExit("no model '%s' (looked for %s)" % (name, path))
    spec = importlib.util.spec_from_file_location("model_" + name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build_one(name: str, preview: bool) -> bool:
    mod = load_model(name)
    geo.reset()
    mod.build()
    return output.finish(name, mod.INFO, preview=preview)


def palette_swatch() -> None:
    from PIL import Image, ImageDraw

    names = list(palette.PALETTE)
    cols = 6
    rows = (len(names) + cols - 1) // cols
    cw, ch = 170, 110
    img = Image.new("RGB", (cols * cw, rows * ch), (24, 26, 30))
    d = ImageDraw.Draw(img)
    for i, n in enumerate(names):
        hexc, rough, metal, glows = palette.PALETTE[n]
        x, y = (i % cols) * cw, (i // cols) * ch
        d.rectangle([x + 8, y + 8, x + cw - 8, y + 68], fill=hexc)
        d.text((x + 10, y + 74), n + (" (glows)" if glows else ""), fill=(235, 235, 230))
        d.text((x + 10, y + 90), "%s  r%.2f m%.1f" % (hexc, rough, metal), fill=(150, 154, 160))
    out = output.PREVIEW_DIR / "palette.png"
    output.PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    img.save(out)
    print("wrote", out)


def main(argv) -> int:
    args = [a for a in argv if not a.startswith("--")]
    preview = "--no-preview" not in argv
    if not args:
        print(__doc__)
        return 1
    if args[0] == "palette":
        palette_swatch()
        return 0
    names = sorted(p.stem for p in (HERE / "models").glob("*.py") if not p.stem.startswith("_")) if args[0] == "all" else args
    results = {n: build_one(n, preview) for n in names}
    bad = [n for n, ok in results.items() if not ok]
    print("\n%d model(s) built, %d with problems%s" % (len(results), len(bad), (": " + ", ".join(bad)) if bad else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
