// Design tokens: warm-gray canvas, black and white components, Geist only.
export const C = {
  canvas: "#E8E5E0",
  ink: "#0B0B0C",
  paper: "#FFFFFF",
  mute: "#6E6B66", // secondary text on paper
  faint: "#A9A59F", // tertiary text, disabled
  line: "rgba(11,11,12,0.08)", // hairlines
  line2: "rgba(11,11,12,0.14)",
  wash: "#F3F1EE", // quiet fills inside paper
  inkMute: "rgba(255,255,255,0.62)", // secondary text on ink
  inkLine: "rgba(255,255,255,0.14)",
};
export const FONT = "Geist, system-ui, sans-serif";
export const MONO = "Geist Mono, ui-monospace, monospace";

// Soft, neutral elevation (no glows): one contact shadow plus one ambient.
export const LIFT = "0 1px 2px rgba(11,11,12,0.06), 0 18px 40px -12px rgba(11,11,12,0.18)";
export const LIFT_SM = "0 1px 1px rgba(11,11,12,0.05), 0 6px 16px -6px rgba(11,11,12,0.14)";

// The phone at rest, in world px (world = 1920 x 1080 at zoom 1).
export const PH = { cx: 960, cy: 540, w: 420, h: 880, r: 56 };
export const PX0 = PH.cx - PH.w / 2;
export const PY0 = PH.cy - PH.h / 2;
/** Phone-local point -> world point. */
export const P = (x: number, y: number): [number, number] => [PX0 + x, PY0 + y];

export const C0: [number, number] = [1180, 640]; // cursor rest, screen px
export const CAM0 = { cx: 960, cy: 540, z: 1.9 }; // first (= last) camera
/** C0 in world px under CAM0: where the cursor rests on frame 0 and the last frame. */
export const C0W: [number, number] = [CAM0.cx + (C0[0] - 960) / CAM0.z, CAM0.cy + (C0[1] - 540) / CAM0.z];
