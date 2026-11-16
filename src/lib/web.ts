// The browser demo (spec 052). The app's screens call Tauri's `invoke`; here,
// with no Tauri, every call goes to the core compiled to WebAssembly
// (crates/intportal-web), which answers from an in-memory demo account.
// Plugins that need a phone answer quietly; nothing leaves the page.
import { base } from "$app/paths";
import { mockIPC } from "@tauri-apps/api/mocks";

interface Exports {
  memory: WebAssembly.Memory;
  alloc(len: number): number;
  dealloc(ptr: number, len: number): void;
  call(cmd: number, cmdLen: number, args: number, argsLen: number, nowMs: number): number;
  out_ptr(): number;
  out_len(): number;
}

const enc = new TextEncoder();
const dec = new TextDecoder();

/** What a plugin answers in the browser. Anything not listed answers null. */
function plugin(cmd: string, args: Record<string, unknown>): unknown {
  if (cmd === "plugin:opener|open_url") return void window.open(String(args.url), "_blank", "noopener");
  if (cmd === "plugin:notification|is_permission_granted") return false;
  if (cmd === "plugin:notification|request_permission") return "denied";
  if (cmd === "plugin:biometric|status") return { isAvailable: false, biometryType: 0 };
  if (cmd === "plugin:camera|capture") throw "That works in the app. Get it on the download page.";
  return null;
}

export async function install(url = `${base}/intportal_web.wasm`): Promise<void> {
  const { instance } = await WebAssembly.instantiateStreaming(fetch(url), {});
  const x = instance.exports as unknown as Exports;
  const put = (s: string): [number, number] => {
    const bytes = enc.encode(s);
    const ptr = x.alloc(bytes.length);
    new Uint8Array(x.memory.buffer, ptr, bytes.length).set(bytes);
    return [ptr, bytes.length];
  };
  const call = (cmd: string, args: unknown): unknown => {
    const [c, cl] = put(cmd);
    const [a, al] = put(JSON.stringify(args ?? {}));
    const code = x.call(c, cl, a, al, Date.now());
    x.dealloc(c, cl);
    x.dealloc(a, al);
    const text = dec.decode(new Uint8Array(x.memory.buffer, x.out_ptr(), x.out_len()));
    if (code !== 0) throw text;
    return JSON.parse(text);
  };
  mockIPC((cmd, args) => (cmd.startsWith("plugin:") ? plugin(cmd, (args ?? {}) as Record<string, unknown>) : call(cmd, args)), { shouldMockEvents: true });
}
