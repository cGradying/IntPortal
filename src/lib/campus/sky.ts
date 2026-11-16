// The sky by the real hour, shared by the shader (as uniforms) and the
// Canvas 2D fallback. Pure, so the keyframes are tested.

export type RGB = [number, number, number];

export const W = 192;
export const H = 80;

export const hex = (h: string): RGB => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16)) as RGB;
export const mix = (a: RGB, b: RGB, t: number): RGB => a.map((v, i) => Math.round(v + (b[i] - v) * t)) as RGB;

/** Ordered dither threshold in [0, 1): the 4x4 Bayer matrix, the same formula as the shader's. */
export function bayer(x: number, y: number): number {
  const b2 = (a: number, b: number) => {
    const v = a * 0.5 + b * b * 0.75;
    return v - Math.floor(v);
  };
  return b2(Math.floor(x / 2), Math.floor(y / 2)) * 0.25 + b2(x & 1, y & 1);
}

/** Sky top and horizon through the day, eased between keyframes. */
export const SKY: [number, string, string][] = [
  [0, "#0a0f2c", "#1d2757"],
  [4.5, "#0d1233", "#2a2d5c"],
  [5.75, "#2b2f5e", "#e39a7a"],
  [7, "#4a86cc", "#f3d2a2"],
  [9, "#4b92d6", "#bfe0f2"],
  [16, "#4a8ccf", "#cfe4ef"],
  [17.25, "#466aa8", "#f2a45e"],
  [18.3, "#2a2c64", "#b8587a"],
  [19.5, "#0e1336", "#26285a"],
  [24, "#0a0f2c", "#1d2757"],
];

/** 0 at night, 1 by day, ramping over dawn (5:30–7) and dusk (17:30–19). */
export const lightAt = (h: number) => Math.max(0, Math.min(1, h < 5.5 || h > 19 ? 0 : h < 7 ? (h - 5.5) / 1.5 : h > 17.5 ? (19 - h) / 1.5 : 1));

export function skyAt(h: number): { top: RGB; bottom: RGB; light: number } {
  let i = 0;
  while (i < SKY.length - 2 && SKY[i + 1][0] <= h) i++;
  const [h0, t0, b0] = SKY[i];
  const [h1, t1, b1] = SKY[i + 1];
  const t = Math.min(1, Math.max(0, (h - h0) / (h1 - h0)));
  const e = t * t * (3 - 2 * t);
  return { top: mix(hex(t0), hex(t1), e), bottom: mix(hex(b0), hex(b1), e), light: lightAt(h) };
}

/** Rainy season (June to October) hazes the far layer a little. */
export const hazeFor = (month: number) => (month >= 5 && month <= 9 ? 0.35 : 0);

/** The window a class lights: the same sum of character codes as before, so a class keeps its window. */
export function litWindow(key: string, windows: number): number {
  if (!key || !windows) return -1;
  let s = 0;
  for (const ch of key) s += ch.charCodeAt(0);
  return s % windows;
}
