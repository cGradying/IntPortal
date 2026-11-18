import type { Group } from "./content/types";
import type { SpriteName } from "$app_lib/PixelIcon.svelte";

/** The app's own 12x12 pixel icon for each directory group (057 C9). */
export const GROUP_ICON: Record<Group, SpriteName> = {
  signin: "lock",
  today: "today",
  schedule: "schedule",
  grades: "grades",
  study: "study",
  lar: "ai",
  you: "you",
  outside: "bell",
  everywhere: "sync",
};
