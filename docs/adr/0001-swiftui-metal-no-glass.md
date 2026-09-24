# Draw 3D with SwiftUI and Metal, and keep Liquid Glass out of app content

IntPortal ships its 3D (the portal swirl, the warp, the hub carousel, week turns, deck fans) with SwiftUI transforms and `[[stitchable]]` Metal shaders only, and keeps pixel sheets instead of Liquid Glass even on macOS 27. RealityKit would have given real meshes but needs macOS 15 and more memory; three.js in a WKWebView would have reused the web prototype but adds JS startup and a bridge per element; macOS 27's glass would have fought the pixel SIS identity the user approved. We take macOS 27's motion (fast interruptible springs) and depth (dark edge plus top highlight on floating layers) without its material.

## Consequences

- Every 3D element must be expressible as a SwiftUI transform or a fragment shader; anything needing real geometry is out of scope until this ADR is superseded.
- `GlassCompat` survives only while a system control requires it.
