# A0 spike: llama-cpp-2 0.1.159 (llama.cpp bundled), `default-features = false`

Model: Qwen3-0.6B Q4_K_M (unsloth build, 396,705,472 bytes, sha256 `ac2d9771…524a`). Prompt: 16 tokens, greedy, 128 tokens out, ctx 2048.
Run: `cargo build --release -p s1-llama [--target …]`, then `s1-llama <model.gguf> [n]`; `NGL=0` forces CPU.

| Target | Build (cold, M-series) | Binary | Result |
|---|---|---|---|
| macOS arm64 (Metal on by default) | 36 s | 5.99 MB | 213.6 tok/s, load 0.10 s, peak footprint 365 MB (RSS 758 MB) |
| iOS simulator arm64, Metal | 31 s | 5.98 MB | 6.0 tok/s (simulated GPU, not meaningful) |
| iOS simulator arm64, `NGL=0` (CPU) | – | – | 158.7 tok/s on the Mac's cores. Not a phone number. |
| Android arm64-v8a, `cargo ndk --platform 24` | 41 s (after fix below) | 4.10 MB | builds; needs `libc++_shared.so` (the `android-shared-stdcxx` feature is off by default here, so the app must ship it or enable the feature). Not run: no emulator was connected. |

Size delta: about 4 to 6 MB of binary per ABI, before the model. The model (397 MB) is the real weight and stays an opt-in download.

## Questions settled
- **openmp:** not needed. With `default-features = false` there is no OpenMP, and iOS and Android build. The default `openmp` feature was not tried.
- **Metal:** the sys crate compiles Metal on Apple targets even with default features off, and it embeds the shaders. `with_n_gpu_layers(0)` gives CPU. Real-phone Metal speed and the iOS jetsam footprint are still the user's to measure with `scripts/phone.sh`.
- **Android build:** at the NDK's default API level llama.cpp fails: `use of undeclared identifier 'posix_madvise'` (bionic declares it from API 31; the app's minSdk is 24). Fix, no source change: delete the cached cmake build, then
  `CXXFLAGS_aarch64_linux_android="-Dposix_madvise=madvise -DPOSIX_MADV_RANDOM=MADV_RANDOM -DPOSIX_MADV_WILLNEED=MADV_WILLNEED -DPOSIX_MADV_SEQUENTIAL=MADV_SEQUENTIAL -DPOSIX_MADV_DONTNEED=MADV_DONTNEED"`.
  cmake keeps its configure step, so a changed flag needs `rm -rf ~/.cargo/build/intportal/<target>/release/build/llama-cpp-sys-2-*`. This must go in `.cargo/config.toml` `[env]` or `scripts/emu.sh` when the shell links the crate.
- Needs `ANDROID_NDK_ROOT` (not just `ANDROID_NDK_HOME`) for the sys crate's build script.

## Not measured yet
- Qwen3 1.7B speed and memory.
- `os_proc_available_memory` on iOS.
- Android `app_data_dir` location, and whether the Android WebView opens a file picker (needs the emulator and app code, so it waits for A5).
- Android run on an emulator or device, and any phone numbers.
