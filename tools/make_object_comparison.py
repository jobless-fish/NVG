"""Builds side-by-side comparison sheets: 2D source PNG (left) vs Godot 3D render (right).

Usage (from asset-modeling/):
    python tools/make_object_comparison.py [--only OBJ01,OBJ02] [--out path.png]
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)  # godot_project/
SRC_DIR = os.path.join(ROOT, "reference", "objects")
RENDER_DIR = os.path.join(ROOT, "renders")

CELL = 300
PAD = 14
LABEL_H = 34
COLS = 4  # pairs per row


def load_font(size):
    for p in ("C:/Windows/Fonts/malgunbd.ttf", "C:/Windows/Fonts/malgun.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def fit(img, bg):
    img = img.convert("RGBA")
    img.thumbnail((CELL, CELL))
    canvas = Image.new("RGBA", (CELL, CELL), bg)
    canvas.alpha_composite(img, ((CELL - img.width) // 2, (CELL - img.height) // 2))
    return canvas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=os.path.join(RENDER_DIR, "comparison_sheet_objects.png"))
    args = ap.parse_args()

    ids = sorted(f[:-4] for f in os.listdir(SRC_DIR) if f.lower().endswith(".png"))
    if args.only:
        keys = args.only.split(",")
        ids = [i for i in ids if any(i.startswith(k) for k in keys)]
    if not ids:
        sys.exit("no matching ids")

    rows = (len(ids) + COLS - 1) // COLS
    pair_w = CELL * 2 + PAD
    W = COLS * pair_w + (COLS + 1) * PAD * 2
    H = rows * (CELL + LABEL_H + PAD * 2) + PAD * 2 + 50
    sheet = Image.new("RGBA", (W, H), (34, 40, 48, 255))
    draw = ImageDraw.Draw(sheet)
    title_font = load_font(26)
    font = load_font(18)
    draw.text((PAD * 2, PAD), "NODEVERSE objects  -  2D 원본 (왼쪽)  vs  Godot 3D 모델 렌더 (오른쪽)", font=title_font, fill=(235, 240, 245))

    for n, aid in enumerate(ids):
        r, c = divmod(n, COLS)
        x = PAD * 2 + c * (pair_w + PAD * 2)
        y = 50 + PAD + r * (CELL + LABEL_H + PAD * 2)
        src = fit(Image.open(os.path.join(SRC_DIR, aid + ".png")), (250, 250, 250, 255))
        sheet.alpha_composite(src, (x, y + LABEL_H))
        rp = os.path.join(RENDER_DIR, aid + ".png")
        if os.path.exists(rp):
            sheet.alpha_composite(fit(Image.open(rp), (38, 48, 61, 255)), (x + CELL + PAD, y + LABEL_H))
        else:
            draw.rectangle([x + CELL + PAD, y + LABEL_H, x + 2 * CELL + PAD, y + LABEL_H + CELL], outline=(200, 80, 80))
        draw.text((x, y + 4), aid, font=font, fill=(220, 228, 236))

    sheet.convert("RGB").save(args.out)
    print("saved", args.out)


if __name__ == "__main__":
    main()
