"""python3 qa/tile.py out.png a.jpg b.jpg ... → 3-column sheet at 640px, labelled."""
import sys
from PIL import Image, ImageDraw
out, files = sys.argv[1], sys.argv[2:]
cols, w = 3, 640
h = int(w * 9 / 16)
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * h), "#222")
d = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB").resize((w, h), Image.LANCZOS)
    x, y = (i % cols) * w, (i // cols) * h
    sheet.paste(im, (x, y))
    d.rectangle([x, y, x + 110, y + 22], fill="#000")
    d.text((x + 4, y + 4), f.split("f-")[-1].replace(".jpg", ""), fill="#ff0")
sheet.save(out)
