// What photos change in note lists (spec 046 C15a, C17b, C17d). Pure.
import type { NoteItem } from "./api";

export const MAX_PHOTOS = 20;

const count = (n: number) => `${n} ${n === 1 ? "photo" : "photos"}`;

/** A list's one-line preview: the words, else "3 photos" for a note of only photos (C17d). */
export const previewOf = (n: Pick<NoteItem, "preview" | "photos">) => n.preview || (n.photos ? count(n.photos) : "");

/** Has a note's own words: what the after-class prompt, Ask AI and Make cards need (C17d). */
export const hasText = (n: Pick<NoteItem, "text">) => !!n.text.trim();

/** Counts as notes for the class sheet and Schedule dot: words or photos (C17d). */
export const hasNotes = (n: Pick<NoteItem, "text" | "photos">) => hasText(n) || !!n.photos;

/** The one line when a photo can't be taken or saved (C17b). */
export function photoProblem(kind: "camera_denied" | "no_camera" | "no_space" | "other"): string {
  switch (kind) {
    case "camera_denied":
      return "IntPortal can't use the camera. Turn it on in Settings, or add a photo from your library.";
    case "no_camera":
      return "This phone has no camera. Add a photo from your library instead.";
    case "no_space":
      return "There isn't room on this phone for the photo. Free some space and try again.";
    default:
      return "The photo couldn't be added. Try again.";
  }
}

export const tooMany = `A note holds up to ${MAX_PHOTOS} photos. Remove one to add another.`;

/** What Share and Export say when a note has photos (C17). */
export const photosInShare = "Photos go with it, in a .zip with the text.";

/** A ~256 px JPEG of `jpeg` for the strip, made in the webview, as bytes for `setPhotoThumb`. */
export async function thumbOf(jpeg: ArrayBuffer, side = 256): Promise<number[]> {
  const bmp = await createImageBitmap(new Blob([jpeg], { type: "image/jpeg" }));
  const k = Math.min(1, side / Math.max(bmp.width, bmp.height));
  const c = document.createElement("canvas");
  c.width = Math.max(1, Math.round(bmp.width * k));
  c.height = Math.max(1, Math.round(bmp.height * k));
  c.getContext("2d")!.drawImage(bmp, 0, 0, c.width, c.height);
  bmp.close();
  const blob = await new Promise<Blob | null>((ok) => c.toBlob(ok, "image/jpeg", 0.8));
  if (!blob) throw new Error("no thumbnail");
  return Array.from(new Uint8Array(await blob.arrayBuffer()));
}
