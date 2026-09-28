"""Draws the IntPortal app icon: a 32x32 pixel portal, scaled to 1024x1024.
Stdlib only. Run: python3 design/make_icon.py && pnpm tauri icon design/icon.png"""
import math, struct, zlib

N, S = 32, 32  # grid cells, pixels per cell
BG, BG2 = (22, 8, 12), (52, 16, 26)
FRAME, HI, SHADOW, SPECK = (52, 32, 63), (74, 44, 88), (23, 11, 26), (90, 58, 108)
RAMP = [(23, 5, 9), (84, 10, 28), (148, 28, 48), (204, 161, 40), (250, 235, 179)]
GOLD = (242, 193, 78)
BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]

grid = [[BG for _ in range(N)] for _ in range(N)]
# A soft dithered glow behind the portal.
for y in range(N):
    for x in range(N):
        d = math.hypot(x - 15.5, y - 15) / 15
        if (1 - d) * 20 > BAYER[y % 4][x % 4] + 7:
            grid[y][x] = BG2

X0, X1, Y0, Y1, T = 7, 24, 3, 26, 3  # the prototype's 6x8-block frame
for y in range(Y0, Y1 + 1):
    for x in range(X0, X1 + 1):
        inside = X0 + T <= x <= X1 - T and Y0 + T <= y <= Y1 - T
        if inside:
            u, v = (x - 15.5) / 6, (y - 14.5) / 9
            a, r = math.atan2(v, u), math.hypot(u * 1.1, v * 0.9)
            val = 0.62 + 0.3 * math.sin(a * 3 + r * 6) + (0.62 - r) * 0.85
            k = int(max(0, min(4, math.floor(val * 4 + BAYER[y % 4][x % 4] / 16 - 0.5))))
            grid[y][x] = RAMP[k]
        else:
            bx, by = (x - X0) % T, (y - Y0) % T
            c = FRAME
            if bx == 0 or by == 0:
                c = HI
            if bx == T - 1 or by == T - 1:
                c = SHADOW
            if (x * 7 + y * 13) % 17 == 0:
                c = SPECK
            grid[y][x] = c
for x, y in [(4, 9), (27, 6), (5, 22), (26, 20), (29, 13), (2, 15)]:
    grid[y][x] = GOLD
for x in range(8, 24):  # a lit threshold under the portal
    grid[27][x] = (120, 60, 30) if x in (8, 23) else (170, 110, 40)
    grid[28][x] = (70, 34, 26)

W = N * S
raw = b"".join(b"\x00" + b"".join(bytes(grid[y // S][x // S]) for x in range(W)) for y in range(W))
png = b"\x89PNG\r\n\x1a\n"
for tag, data in [(b"IHDR", struct.pack(">IIBBBBB", W, W, 8, 2, 0, 0, 0)), (b"IDAT", zlib.compress(raw, 9)), (b"IEND", b"")]:
    png += struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
open("design/icon.png", "wb").write(png)
print("wrote design/icon.png", W)
