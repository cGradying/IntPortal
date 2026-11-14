/** Spec 040 C1: leave a page by any route, saving unsaved edits first; a failed save keeps the page open. */
export async function leave(dirty: boolean, save: () => Promise<boolean>, then: () => void): Promise<boolean> {
  if (dirty && !(await save())) return false;
  then();
  return true;
}
