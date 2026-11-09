// Share codes (spec 047 C16, C17): `IPT1.` plus base64url of
// [version 2, flags, flags2, hue2, lar, accent rgb, ground rgb, card rgb, ink rgb, name length, name utf-8, checksum].
// A code holds only a look and a name: nothing that runs or links. Decoding is strict.
import { hex, toHex } from "./rooms";
import { AURA, CARDS, CORNERS, PATTERNS, TITLES, hueOf, type Theme } from "./theme";

const VERSION = 2;
const FIXED = 19; // every byte but the name's
const MAX_NAME = 24; // characters

/** Control and direction-changing characters: never in a name. */
const HIDDEN = /[\p{Cc}\u200e\u200f\u202a-\u202e\u2066-\u2069]/gu;
const chars = (s: string) => [...s.replace(HIDDEN, "")].slice(0, MAX_NAME).join("");

export function encodeTheme(t: Theme): string {
  const name = new TextEncoder().encode(chars(t.name));
  const flags = PATTERNS.indexOf(t.pattern) | (AURA.indexOf(t.aura) << 4) | (CORNERS.indexOf(t.corners) << 6);
  const flags2 = CARDS.indexOf(t.cards) | (TITLES.indexOf(t.titles) << 2);
  const h2 = Math.round(((t.hue2 ?? hueOf(t.accent)) / 360) * 255);
  const lar = t.lar == null ? 255 : Math.round((t.lar / 360) * 254);
  const body = [VERSION, flags, flags2, h2, lar, ...hex(t.accent), ...hex(t.ground), ...hex(t.card), ...hex(t.ink), name.length, ...name];
  body.push(body.reduce((a, b) => (a + b) & 255, 0));
  return "IPT1." + btoa(String.fromCharCode(...body)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** The theme in a code, or null when anything about it is off. */
export function decodeTheme(code: string): Theme | null {
  const m = /^IPT1\.([A-Za-z0-9_-]+)$/.exec(code.trim());
  if (!m || m[1].length % 4 === 1) return null;
  let b: number[];
  try {
    b = [...atob(m[1].replace(/-/g, "+").replace(/_/g, "/"))].map((c) => c.charCodeAt(0));
  } catch {
    return null;
  }
  if (b.length < FIXED || b[0] !== VERSION || b[17] !== b.length - FIXED) return null;
  if (b.slice(0, -1).reduce((a, v) => (a + v) & 255, 0) !== b[b.length - 1]) return null;
  const pattern = PATTERNS[b[1] & 15];
  const aura = AURA[(b[1] >> 4) & 3];
  const corners = CORNERS[(b[1] >> 6) & 3];
  const cards = CARDS[b[2] & 3];
  const titles = TITLES[(b[2] >> 2) & 3];
  if (!pattern || !aura || !cards || !titles || b[2] >> 4) return null;
  let name: string;
  try {
    name = new TextDecoder("utf-8", { fatal: true }).decode(new Uint8Array(b.slice(18, -1)));
  } catch {
    return null;
  }
  if ([...name].length > MAX_NAME || name.replace(HIDDEN, "") !== name) return null;
  const c = (i: number) => toHex(b.slice(i, i + 3) as [number, number, number]);
  return {
    name: name.trim() || "Shared theme",
    pattern,
    aura,
    corners,
    cards,
    titles,
    hue2: Math.round((b[3] / 255) * 360) % 360,
    lar: b[4] === 255 ? null : Math.round((b[4] / 254) * 360) % 360,
    accent: c(5),
    ground: c(8),
    card: c(11),
    ink: c(14),
  };
}

/**
 * Reads a share code from one photo of its QR (C18). Null until the camera plugin (#219) lands:
 * then it is `plugin:camera|capture` with `{ source: "camera", read: { qr: true } }`, keeping nothing.
 * Until then paste works alone, and the maker hides the photo button.
 */
// ponytail: stub until #219 merges; wire the camera call here and the button appears.
export const scanQr = null as null | (() => Promise<string | null>);
