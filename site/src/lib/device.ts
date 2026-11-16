// Which download to put first (spec 051 C8), from the user agent alone.
export type Device = "android" | "ios" | "mac" | "windows" | "linux" | "other";

export function device(ua: string, touchPoints = 0): Device {
  if (/Android/i.test(ua)) return "android";
  if (/iPhone|iPad|iPod/i.test(ua)) return "ios";
  // iPadOS asks for the desktop site and says "Macintosh"; only touch tells it apart.
  if (/Macintosh/i.test(ua)) return touchPoints > 1 ? "ios" : "mac";
  if (/Windows/i.test(ua)) return "windows";
  if (/Linux|X11|CrOS/i.test(ua)) return "linux";
  return "other";
}
