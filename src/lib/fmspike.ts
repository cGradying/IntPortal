// SPIKE ONLY (spike/apple-fm, #168): drives plugin:foundation with fixed
// prompts at launch of a review build and prints the results on screen,
// because a simulator has no console. Never merge.
import { Channel, invoke } from "@tauri-apps/api/core";

type Out = { text: string; cancelled: boolean; snapshots: number; firstSnapshotMs?: number; totalMs: number };

export async function runFmSpike() {
  const box = document.createElement("pre");
  box.style.cssText = "position:fixed;inset:40px 6px auto;z-index:100;max-height:80vh;overflow:hidden;padding:6px;background:#000d;color:#9f9;white-space:pre-wrap;font-size:10px;pointer-events:none";
  document.body.append(box);
  const log = (s: string) => {
    box.textContent += s + "\n";
    console.log("[fm]", s);
  };
  const call = async (label: string, args: Record<string, unknown>, cancelAfterMs?: number) => {
    const deltas: string[] = [];
    const onToken = new Channel<string>();
    onToken.onmessage = (d) => deltas.push(d);
    const p = invoke<Out>("plugin:foundation|generate", { ...args, onToken });
    if (cancelAfterMs) setTimeout(() => invoke("plugin:foundation|cancel"), cancelAfterMs);
    try {
      const r = await p;
      const joined = deltas.join("");
      const same = args.schema ? "n/a" : String(joined === r.text);
      log(`${label}: ${deltas.length} deltas, deltas==text ${same}, first ${Math.round(r.firstSnapshotMs ?? -1)} ms, total ${Math.round(r.totalMs)} ms, cancelled ${r.cancelled}\n  ${r.text.slice(0, 160).replace(/\n/g, " ")}`);
    } catch (e) {
      log(`${label}: ERROR ${(e as { message?: string })?.message ?? JSON.stringify(e)}`);
    }
  };
  try {
    log("availability " + JSON.stringify(await invoke("plugin:foundation|availability")));
  } catch (e) {
    log("availability ERROR " + ((e as { message?: string })?.message ?? JSON.stringify(e)));
    return;
  }
  const ins = "You are LAR, a short, friendly study helper. Keep replies under 50 words.";
  await call("plain", { prompt: "Explain inorder traversal in 40 words.", instructions: ins, maxTokens: 120 });
  await call("schema{reply}", { prompt: "Explain inorder traversal in 40 words.", instructions: ins, maxTokens: 120, schema: JSON.stringify({ type: "object", properties: { reply: { type: "string" } }, required: ["reply"] }) });
  await call("fil", { prompt: "ano ang due ko bukas?", instructions: ins, maxTokens: 120 });
  await call("cancel@600ms", { prompt: "Write a 300 word essay on sorting algorithms.", instructions: ins, maxTokens: 500 }, 600);
  log("done");
}
