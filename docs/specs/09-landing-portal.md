# 09 — Portal landing (launch screen, sign-in, hub, warp)

Status: approved design (prototype v2). Replaces `CredentialsView.swift` and the home launcher.

## Reference
Prototype `docs/specs/prototypes/intportal-v2.html`: the `.landing` layer, `drawScene()`,
`frame()`, `platform()`, `figure()`, the WebGL `fs` shader, `tick()` state machine, `warp()`.

## Current behaviour inventory (must keep)
From `Views/CredentialsView.swift` and `AppState`:
- Fields: Student Number, Date of birth (month / day / year), Password. Return submits.
- Copy: title "PUPSIS IntPortal", button **"Login now"**, reassurance **"Locked in your Mac's
  Keychain. This portal only ever talks to PUP SIS."**
- Credentials saved to Keychain on success; failure shows the SIS message or the generic
  "Sign-in didn't go through — check your student number, birthdate, and password."
- "Signing in…" state; "Edit credentials" and "Try again" after failure.
- Settings reachable before sign-in (gear).

## Behaviour

### Phases (pure, testable)
`Core/LandingSequence.swift`:

```swift
enum LandingPhase: Equatable { case void, forming(Double), ignite(Double), signIn, hub, warp(Double), done }

struct LandingSequence {
    var signedIn: Bool
    var reduceMotion: Bool
    /// elapsed since the landing appeared, or since warp began when warping
    func phase(elapsed: TimeInterval, warpStartedAt: TimeInterval?) -> LandingPhase
}
```
Timing (full motion): void 0–0.4s · forming 0.4–1.6s (24 blocks) · ignite 1.7–2.2s · then `hub`
if signed in, else `signIn`. Warp 0–0.95s, flash at 82%, `done` at 1.08s. Reduce Motion: straight
to `hub`/`signIn`; warp → `done` after 0.22s. Return or a click during void/forming/ignite skips
to the rest phase.

### Launch
- Signed in (Keychain has credentials): land, portal already humming, **"Signed in as {name}
  · Switch account"** top-right, hint "Step through ⏎". Click the portal or press Return → warp.
  Background refresh starts immediately; it does not wait for the warp.
- Signed out: sign-in panel slides in on the right; the portal shifts left 16% of the width.
- Settings ▸ General ▸ **"Play portal intro"** (default on). Off = land directly in `hub` with the
  frame already built (no forming/ignite).

### Sign-in panel
Same fields and copy as today, plus a live **campus line** under Student Number (spec 10):
"MN · Sta. Mesa — campus found", or a "Pick your campus" menu for an unknown code. Validation
before submit: `^\d{4}-\d{5}-[A-Za-z]{2}-\d{1,2}$`, message "Student number looks like
2026-00000-MN-0." Submit → `appState.signIn(credentials)`; while signing in the swirl speeds up
(×2) and the button reads "Signing in…". Success → `hub`. Failure → message under the button, swirl
back to ×1.

### Hub
- Center: PUP SIS portal, lit, tag "PUP SIS / {campus} · via {host}" (host from `currentHost`).
- Left and right, smaller and dark: obsidian frames tagged "Not connected yet". Click = shake and
  hint "That portal is not connected yet. Only PUP SIS is live." They are placeholders for future
  systems; they never do anything else.
- ⌘0 from the app opens the hub directly (quick path, no forming).
- Sign out (sidebar / Account / menu) → landing in `signIn` with the full intro.

### Warp
Zoom the whole scene about the portal interior center (1 → 12, ease-in ^2.6), swirl speed ×9,
pixel cell ×4, gold-white radial flash at 82%, then remove the landing and fade the flash out
over the app (650ms). The app opens on **Today**.

## Layout & components (native)

`Views/Landing/PortalLanding.swift`
```swift
struct PortalLanding: View {
    @EnvironmentObject var app: AppState
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var start = Date.now
    @State private var warpStart: Date?
    var body: some View {
        TimelineView(.animation(paused: phaseIsRest && reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSince(start)
            let phase = LandingSequence(signedIn: app.hasCredentials, reduceMotion: reduceMotion)
                .phase(elapsed: t, warpStartedAt: warpStart.map { $0.timeIntervalSince(start) })
            GeometryReader { geo in
                let g = PortalGeometry(size: geo.size, formShift: phase == .signIn ? 0.16 : 0)
                ZStack {
                    VoidScene(geometry: g, phase: phase, time: t)          // Canvas: gradient, motes, platform, frame blocks, figure, side frames
                    SwirlView(time: t, speed: phase.swirlSpeed, lit: phase.lit, cell: phase.pixelCell)
                        .frame(width: g.interior.width, height: g.interior.height)
                        .position(g.interior.center)
                    HubTags(geometry: g, phase: phase)                     // buttons over the frames
                    if phase == .signIn { SignInPanel().transition(.move(edge: .trailing).combined(with: .opacity)) }
                }
                .scaleEffect(phase.zoom, anchor: g.interiorAnchor)
                .layerEffect(ShaderLibrary.bundle(.module).pixelate(.float(phase.pixelCell)),
                             maxSampleOffset: CGSize(width: 16, height: 16), isEnabled: phase.isWarp)
                .overlay(FlashOverlay(opacity: phase.flash))
            }
        }
        .background(Color.void)
    }
}
```
- `VoidScene` is one `Canvas`: port `drawScene`, `platform`, `frame`, `block`, `figure` from the
  prototype 1:1 (integer block size `B = round(min(w/24, h/17))`, 6×8 frame, 5×5 isometric
  platform, 8×12 figure sprite facing the portal, 70 motes). Deterministic seeds (no `random()`
  per frame).
- `SwirlView` = `Rectangle().colorEffect(ShaderLibrary.bundle(.module).portalSwirl(...))`.

### `Resources/Shaders/Portal.metal` (compiled by SwiftPM into the module's metallib)
```metal
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float h(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
static float n(float2 p) {
    float2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(h(i), h(i + float2(1, 0)), f.x), mix(h(i + float2(0, 1)), h(i + float2(1, 1)), f.x), f.y);
}
static float fbm(float2 p) { float v = 0, a = 0.5; for (int k = 0; k < 4; k++) { v += a * n(p); p *= 2.03; a *= 0.5; } return v; }
static float b2(float2 a) { a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
static float bayer(float2 a) { return b2(0.5 * a) * 0.25 + b2(a); }

// size: view size in points; cell: pixel size in points (3 at rest, up to 12 in warp)
[[ stitchable ]] half4 portalSwirl(float2 pos, half4 color, float2 size, float time, float speed,
                                   float lit, float cell,
                                   half4 c0, half4 c1, half4 c2, half4 c3, half4 c4) {
    float2 q0 = floor(pos / cell);
    float2 uv = ((q0 + 0.5) * cell - 0.5 * size) / size.y;
    uv.y = -uv.y;
    float d = length(uv * float2(1.25, 0.8));
    float a = atan2(uv.y, uv.x) + time * 0.28 * speed + d * 3.2;
    float2 q = float2(cos(a), sin(a)) * d * 2.4;
    float v = fbm(q * 2.2 + float2(0, -time * 0.5 * speed));
    v += 0.22 * sin(uv.x * 16.0 + fbm(uv * 3.0 + time * 0.25 * speed) * 7.0 + time * 1.6 * speed);
    v = clamp(v * 0.95 + (0.55 - d) * 0.55, 0.0, 1.0) * lit;
    float k = clamp(floor(v * 4.0 + bayer(q0) - 0.5), 0.0, 4.0);
    return k < 0.5 ? c0 : k < 1.5 ? c1 : k < 2.5 ? c2 : k < 3.5 ? c3 : c4;
}

[[ stitchable ]] half4 pixelate(float2 pos, SwiftUI::Layer layer, float cell) {
    return layer.sample((floor(pos / cell) + 0.5) * cell);
}
```
Colors passed as `.color(palette.swirl0…4)`. `Package.swift`: add `.process("Resources/Shaders")`.
Needs a working Metal toolchain (the same fix that unblocks `swift build`; see
`.claude/plans/backend-fixes.md`).

### Cost budget
Swirl is one fragment pass over ~4B×6B points at ≤ 60fps; pause the `TimelineView` when the window
is not key or occluded. Canvas redraw is ~200 rects per frame. Target < 5% CPU on an M1 at rest.

## States
- **No credentials / signed out:** `signIn`.
- **Signing in:** faster swirl, disabled button.
- **Sign-in failed:** message under the button; "Edit credentials" focuses the first field.
- **Offline at launch with a cache:** hub still works; tag reads "PUP SIS / offline · cached
  2:04 PM"; warp enters the app on cached data.
- **Metal unavailable:** `SwirlView` falls back to a `Canvas` ramp (prototype `swirl()` 2D path).

## Accessibility & motion
- Portal tags are real buttons: "Enter the PUP SIS portal", "Locked portal, not connected yet".
- Return triggers the primary action in every phase; Esc does nothing (there is nowhere to go back).
- VoiceOver users land with focus on the student-number field (signed out) or the PUP SIS portal
  (signed in). The void, motes and figure are hidden from accessibility.
- Reduce Motion: see Phases. Increased contrast: tag borders go 2pt → 3pt.

## 3D
The hub is an `OrbitRing` (token `orbit`): portal frames on a ring, ← / → orbit, Return warps into the centered frame. PUP SIS is lit and labelled with the campus; locked frames are dark and read "Not connected yet".

## Acceptance criteria
- [ ] ← / → orbit the hub ring; locked frames can be focused but not entered. Evidence: `LandingSequenceTests` + screenshots.
- [ ] `LandingSequence` unit test covers every phase boundary, skip, Reduce Motion, signed in/out.
- [ ] Signed-in launch reaches the app in ≤ 2 interactions (land, Return). Evidence: manual.
- [ ] Sign-in errors, Keychain save and credential copy match today's behaviour. Evidence: manual +
      existing tests.
- [ ] Campus line resolves MN live and offers the picker for unknown codes. Evidence: test in spec 10.
- [ ] Warp runs ≥ 55fps on an M1 (Instruments). Evidence: trace screenshot.
- [ ] Reduce Motion: no zoom, static swirl, 200ms crossfade. Evidence: manual.
- [ ] `CredentialsView.swift` and the home launcher are deleted.

## Seams
`AppState.signIn(_:)`, `hasCredentials`, `signOut()`, `PortalController.currentHost`,
`Campus` (spec 10). No change to sign-in logic itself (host failover is spec 00).

## Out of scope
Other schools' or systems' portals (the dark frames are placeholders only). Sound.
