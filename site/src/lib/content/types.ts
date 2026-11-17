// Spec 057: the shapes the website's pages read. Content lives beside this file.
export type Group = "signin" | "today" | "schedule" | "grades" | "study" | "lar" | "you" | "outside" | "everywhere";
export type Media = { src: string; alt: string; poster?: string; video?: boolean };
export type Feature = {
  slug: string;
  name: string;
  group: Group;
  /** One line for the directory card. */
  line: string;
  /** Short paragraphs for the feature's page. */
  body: string[];
  /** How to use it, one step each. */
  steps: string[];
  media?: Media;
  /** The version it arrived in, e.g. "0.4.0". */
  since?: string;
  /** Its spec file, e.g. "055-study-game". */
  spec?: string;
};
export type Release = { version: string; date: string; intro: string; items: string[]; gaps: string[] };
export type Lane = "shipped" | "building" | "next" | "later";
export type RoadItem = { title: string; line: string; lane: Lane; href: string; kind: "spec" | "issue" | "release"; date?: string };
