import type React from "react";

export type Box = { cx: number; cy: number; w: number; h: number; r: number };
export type Cam = { cx: number; cy: number; z: number };

/** One phrase (7 bars) of the film: its key data plus what it draws. */
export type Phrase = {
  name: string;
  from: number; // first beat
  to: number; // last beat + 1
  shape: [number, Partial<Box>][];
  fill?: [number, string][];
  /** hairline/elevation amount 0..1 (paper states get a hairline + soft lift) */
  lift?: [number, number][];
  cam: [number, Partial<Cam>][];
  /** cursor: [beat a move starts, world x, world y] */
  cur: [number, number, number][];
  clicks: number[];
  /** drags: [press beat, release beat] */
  holds?: [number, number][];
  /** every beat lists what happens on it (also the SFX cue list) */
  events: [number, string][];
  Inside?: React.FC<{ t: number; box: Box }>;
  Over?: React.FC<{ t: number; box: Box }>;
  Under?: React.FC<{ t: number; box: Box }>;
};
