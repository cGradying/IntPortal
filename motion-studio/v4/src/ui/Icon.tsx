// One icon set: 24px grid, 1.75px stroke, round caps and joins, no fills.
import React from "react";

const PATHS: Record<string, string> = {
  alert: "M12 3.5a8.5 8.5 0 1 0 0 17 8.5 8.5 0 0 0 0-17zM12 8v4.6M12 16h.01",
  today: "M4 10.5 12 4l8 6.5V19a1 1 0 0 1-1 1h-4.5v-5.5h-5V20H5a1 1 0 0 1-1-1z",
  calendar: "M5 6h14a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1zM4 10.5h16M8.5 3.5v4M15.5 3.5v4",
  grades: "M5 19.5V13M10 19.5V8.5M15 19.5v-8M20 19.5V5",
  note: "M7 3.5h7.5L19 8v11.5a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1v-15a1 1 0 0 1 1-1zM14 3.5V8h4.5M9 12.5h6M9 16h4",
  wifi: "M3.5 9.5a12 12 0 0 1 17 0M6.5 12.8a7.6 7.6 0 0 1 11 0M9.5 16a3.2 3.2 0 0 1 5 0M12 19.2h.01",
  wifiOff: "M3.5 9.5a12 12 0 0 1 4.3-2.7M12 6.5a12 12 0 0 1 8.5 3M6.5 12.8a7.6 7.6 0 0 1 3.1-1.9M9.5 16a3.2 3.2 0 0 1 5 0M12 19.2h.01M4 4l16 16",
  book: "M5 4.5h5a2 2 0 0 1 2 2V20a1.6 1.6 0 0 0-1.6-1.6H5zM19 4.5h-5a2 2 0 0 0-2 2V20a1.6 1.6 0 0 1 1.6-1.6H19z",
  pin: "M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0c0 5.4-6.5 11-6.5 11zM12 12.2a2.2 2.2 0 1 0 0-4.4 2.2 2.2 0 0 0 0 4.4z",
  clock: "M12 3.5a8.5 8.5 0 1 0 0 17 8.5 8.5 0 0 0 0-17zM12 7.5V12l3 2",
  check: "M5 12.5 10 17.5 19.5 7",
  arrowR: "M5 12h14M13.5 6.5 19 12l-5.5 5.5",
  arrowUp: "M12 19V5M6.5 10.5 12 5l5.5 5.5",
  x: "M6 6l12 12M18 6 6 18",
  cards: "M8 7.5h11a1 1 0 0 1 1 1V18a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V8.5a1 1 0 0 1 1-1zM4 15V5.5a1 1 0 0 1 1-1h10",
  quiz: "M9.2 9.2a2.8 2.8 0 1 1 3.8 2.6c-.6.3-1 .9-1 1.6v.6M12 17h.01M12 3.5a8.5 8.5 0 1 0 0 17 8.5 8.5 0 0 0 0-17z",
  plan: "M5 6h14a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1zM4 10.5h16M8.5 3.5v4M15.5 3.5v4M9 15l2 2 4-4",
  sun: "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8zM12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4",
  moon: "M19.5 14.5A7.5 7.5 0 0 1 9.5 4.5a7.5 7.5 0 1 0 10 10z",
  phone: "M8 3h8a1.5 1.5 0 0 1 1.5 1.5v15A1.5 1.5 0 0 1 16 21H8a1.5 1.5 0 0 1-1.5-1.5v-15A1.5 1.5 0 0 1 8 3zM11 18h2",
  laptop: "M5 5.5h14a1 1 0 0 1 1 1V16H4V6.5a1 1 0 0 1 1-1zM2.5 18.5h19",
  monitor: "M3.5 4.5h17a1 1 0 0 1 1 1V15a1 1 0 0 1-1 1h-17a1 1 0 0 1-1-1V5.5a1 1 0 0 1 1-1zM9 20h6M12 16v4",
  link: "M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1",
  mail: "M4.5 6h15a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1zM4 7l8 6 8-6",
  lock: "M7 10.5h10a1 1 0 0 1 1 1V19a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1v-7.5a1 1 0 0 1 1-1zM8.5 10.5V8a3.5 3.5 0 0 1 7 0v2.5",
  search: "M10.5 4a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13zM15.3 15.3 20 20",
  spark: "M12 3.5c.7 4.4 2.6 6.3 7 7-4.4.7-6.3 2.6-7 7-.7-4.4-2.6-6.3-7-7 4.4-.7 6.3-2.6 7-7z",
  chevD: "M6.5 9.5 12 15l5.5-5.5",
  chevR: "M9.5 6.5 15 12l-5.5 5.5",
  plus: "M12 5v14M5 12h14",
  user: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4.5 20a7.5 7.5 0 0 1 15 0",
  layers: "M12 4 3.5 8.5 12 13l8.5-4.5zM3.5 12.5 12 17l8.5-4.5M3.5 16.5 12 21l8.5-4.5",
  refresh: "M19.5 12a7.5 7.5 0 1 1-2.2-5.3M19.5 4.5v4h-4",
  globe: "M12 3.5a8.5 8.5 0 1 0 0 17 8.5 8.5 0 0 0 0-17zM3.5 12h17M12 3.5c2.4 2.3 3.5 5.2 3.5 8.5s-1.1 6.2-3.5 8.5c-2.4-2.3-3.5-5.2-3.5-8.5s1.1-6.2 3.5-8.5z",
  stairs: "M4 19.5h4.5V15H13v-4.5h4.5V6H20",
  door: "M6 20.5V4.5a1 1 0 0 1 1-1h10a1 1 0 0 1 1 1v16M3.5 20.5h17M14.5 12.5h.01",
};

export const Icon: React.FC<{ name: keyof typeof PATHS | string; size?: number; c?: string; style?: React.CSSProperties; draw?: number }> = ({ name, size = 24, c = "currentColor", style, draw }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" style={{ display: "block", overflow: "visible", ...style }}>
    <path d={PATHS[name]} stroke={c} strokeWidth={1.75 * (24 / size) * (size / 24)} strokeLinecap="round" strokeLinejoin="round"
      vectorEffect="non-scaling-stroke"
      pathLength={draw !== undefined ? 1 : undefined}
      strokeDasharray={draw !== undefined ? `${draw} 1` : undefined} />
  </svg>
);
