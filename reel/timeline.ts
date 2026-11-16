// The reel's timeline (spec 054): one list of acts, read by the film and the captions.
export const FPS = 30;
export const DUR = 46;

/** A stretch of app footage: which clip, where it starts in the film, and where in the clip. */
export interface Shot {
  clip: "dive" | "today" | "schedule" | "grades" | "study";
  at: number;
  len: number;
  from: number;
  frames: number;
}

export const SHOTS: Shot[] = [
  { clip: "dive", at: 5, len: 7.5, from: 0.8, frames: 271 },
  { clip: "today", at: 12.5, len: 6, from: 0.2, frames: 186 },
  { clip: "schedule", at: 18.5, len: 5, from: 0.3, frames: 162 },
  { clip: "grades", at: 23.5, len: 4, from: 0.1, frames: 124 },
  { clip: "study", at: 27.5, len: 7, from: 1.4, frames: 258 },
];

/** Words on screen. Each line is also a caption in the published WebVTT. */
export interface Line {
  at: number;
  end: number;
  text: string;
  small?: boolean;
}

export const LINES: Line[] = [
  { at: 0.4, end: 4.9, text: "Saan ang next class ko?" },
  { at: 1.5, end: 4.9, text: "Na-post na ba ang grades ko?" },
  { at: 2.6, end: 4.9, text: "Ano'ng due this week?" },
  { at: 7.0, end: 12.4, text: "IntPortal" },
  { at: 7.6, end: 12.4, text: "Your PUP day, on your phone.", small: true },
  { at: 12.8, end: 15.2, text: "Your next class, counting down." },
  { at: 15.3, end: 18.4, text: "Tick it Done. Undo if you slip." },
  { at: 18.8, end: 23.4, text: "Your day and your week." },
  { at: 23.57, end: 27.4, text: "Every term. Your GPA. The trend." },
  { at: 27.8, end: 34.4, text: "Cards that come back right before you forget." },
  { at: 35.0, end: 40.4, text: "Works offline." },
  { at: 36.4, end: 40.4, text: "Stays on your phone." },
  { at: 37.8, end: 40.4, text: "Unofficial. Free." },
  { at: 41.2, end: 46, text: "IntPortal" },
  { at: 41.9, end: 46, text: "Para sa Iskolar ng Bayan.", small: true },
  { at: 42.8, end: 46, text: "Android · iPhone · any browser", small: true },
];

/** The acts: questions, the dive, the app, the promise, the end card. */
export const ACTS = { questions: [0, 5], app: [5, 34.5], promise: [34.5, 40.6], end: [40.6, 46] } as const;
