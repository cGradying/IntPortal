// Hands a file to the phone's share sheet (Save to Files, Calendar, Mail…)
// through the Web Share API, which iOS and Android web views support.

export async function shareFile(name: string, type: string, text: string): Promise<"shared" | "cancelled"> {
  const file = new File([text], name, { type });
  if (!navigator.canShare?.({ files: [file] })) throw new Error("This phone can't share files from IntPortal yet.");
  try {
    await navigator.share({ files: [file], title: name });
    return "shared";
  } catch (e) {
    // Closing the sheet is not an error.
    if (e instanceof DOMException && e.name === "AbortError") return "cancelled";
    throw e;
  }
}
