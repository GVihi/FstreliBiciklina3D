"""Draws the FB3D app icon: assets/icon/icon.png (256 px, the project icon) and assets/icon/icon.ico (the Windows
export icon, 16 to 256 px). Run it again after changing the colours or the letters:
    python3 tools/make_icon.py
Needs Pillow. The letters are drawn from blocks by this script, no font is used, so the icon has no third-party part.
Style: chunky bevelled blocks, dark panel, orange accent and a hazard stripe (docs/ART_DIRECTION.md)."""

from pathlib import Path
from PIL import Image, ImageDraw

SIZE = 512
PANEL = (33, 36, 41)  # dark panel, the menu button colour
PANEL_EDGE = (74, 79, 84)
ACCENT = (255, 107, 43)  # the UI accent orange
ACCENT_LIGHT = (255, 176, 71)  # bevel highlight, the gold
ACCENT_DARK = (168, 58, 14)  # bevel shadow
STRIPE_A = (240, 181, 48)  # hazard yellow
STRIPE_B = (28, 30, 34)

GLYPHS = {
    "F": ["1111", "1000", "1110", "1000", "1000"],
    "B": ["1110", "1001", "1110", "1001", "1110"],
    "3": ["1110", "0001", "0110", "0001", "1110"],
    "D": ["1110", "1001", "1001", "1001", "1110"],
}
ROWS = ["FB", "3D"]
CELL = 34  # one block of a letter, in pixels at 512
BEVEL = 5  # the thickness of the light edge and of the shadow


def letter_cells(ch: str, ox: int, oy: int) -> set:
    """The grid cells (x, y in blocks, relative to the whole icon text) a letter fills."""
    cells = set()
    for gy, line in enumerate(GLYPHS[ch]):
        for gx, bit in enumerate(line):
            if bit == "1":
                cells.add((ox + gx, oy + gy))
    return cells


def draw_cells(d: ImageDraw.ImageDraw, cells: set, left: int, top: int) -> None:
    """Joined blocks with one bevel for the whole letter: a shadow under it, the face, a light edge on the sides
    that face up and left."""
    for cx, cy in cells:
        x, y = left + cx * CELL, top + cy * CELL
        d.rectangle([x + BEVEL, y + BEVEL, x + CELL - 1 + BEVEL, y + CELL - 1 + BEVEL], fill=ACCENT_DARK)
    for cx, cy in cells:
        x, y = left + cx * CELL, top + cy * CELL
        d.rectangle([x, y, x + CELL - 1, y + CELL - 1], fill=ACCENT)
    for cx, cy in cells:
        x, y = left + cx * CELL, top + cy * CELL
        if (cx, cy - 1) not in cells:
            d.rectangle([x, y, x + CELL - 1, y + BEVEL - 1], fill=ACCENT_LIGHT)
        if (cx - 1, cy) not in cells:
            d.rectangle([x, y, x + BEVEL - 1, y + CELL - 1], fill=ACCENT_LIGHT)


def draw_icon() -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # the rounded dark panel with a light edge
    d.rounded_rectangle([8, 8, SIZE - 9, SIZE - 9], radius=72, fill=PANEL_EDGE)
    d.rounded_rectangle([16, 16, SIZE - 17, SIZE - 17], radius=64, fill=PANEL)
    # the hazard stripe along the bottom, clipped to the panel
    stripe = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(stripe)
    top, bottom = 420, 496
    sd.rectangle([0, top, SIZE, bottom], fill=STRIPE_B)
    x = -SIZE
    while x < SIZE * 2:
        sd.polygon([(x, bottom), (x + 40, bottom), (x + 40 + (bottom - top), top), (x + (bottom - top), top)], fill=STRIPE_A)
        x += 80
    mask = Image.new("L", (SIZE, SIZE), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([16, 16, SIZE - 17, SIZE - 17], radius=64, fill=255)
    md.rectangle([0, 0, SIZE, top], fill=0)
    img.paste(stripe, (0, 0), Image.composite(stripe.split()[3], Image.new("L", (SIZE, SIZE), 0), mask))
    # the letters, two rows of two, one block of space between them
    cells = set()
    for r, row in enumerate(ROWS):
        for c, ch in enumerate(row):
            cells |= letter_cells(ch, c * 5, r * 6)
    total_w = 9 * CELL
    total_h = 11 * CELL
    left = (SIZE - total_w - BEVEL) // 2
    top_y = 30 + (top - 30 - 14 - total_h - BEVEL) // 2
    draw_cells(d, cells, left, top_y)
    return img


def main() -> None:
    out = Path(__file__).resolve().parent.parent / "assets" / "icon"
    out.mkdir(parents=True, exist_ok=True)
    big = draw_icon()
    big.resize((256, 256), Image.LANCZOS).save(out / "icon.png")
    big.save(out / "icon.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("wrote", out / "icon.png", "and", out / "icon.ico")


if __name__ == "__main__":
    main()
