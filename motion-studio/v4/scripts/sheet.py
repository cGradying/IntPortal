# python3 scripts/sheet.py out/sheet.png FROM TO [cols]  -> contact sheet of out/stills with beats in [FROM, TO)
import sys, glob, os
from PIL import Image, ImageDraw
out, a, b = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
cols = int(sys.argv[4]) if len(sys.argv) > 4 else 4
files = sorted((float(os.path.basename(f)[1:-4]), f) for f in glob.glob("out/stills/b*.png"))
files = [f for k, f in files if a <= k < b]
W, H = 640, 360
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * W, rows * (H + 24)), (30, 30, 30))
d = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB").resize((W, H), Image.LANCZOS)
    x, y = (i % cols) * W, (i // cols) * (H + 24)
    sheet.paste(im, (x, y + 24))
    d.text((x + 8, y + 6), os.path.basename(f)[1:-4], fill=(240, 240, 240))
sheet.save(out)
print(out, len(files))
