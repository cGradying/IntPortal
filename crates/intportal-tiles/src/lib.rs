//! The landing's tile portal (spec 010, ADR 0004): a pure scene in [`scene`],
//! and plain WebAssembly exports the landing calls once per frame.

pub mod dive;
pub mod scene;

/// u32s per portal in the buffer the landing fills: cols, rows, corner,
/// motif, five ramp tones, accent.
pub const STRIDE: usize = 10;

#[cfg(target_arch = "wasm32")]
mod wasm {
    use crate::dive::{launch_layout, Dive, Frame, Params};
    use crate::scene::{base, carousel, gap as spacing, rect, Corner, Input, Layout, Look, Motif, Scene, Shape, Stage, Theme, Tile};
    use crate::STRIDE;
    use std::cell::RefCell;

    #[derive(Default)]
    struct World {
        scenes: Vec<Scene>,
        size: (u32, u32),
        input: Vec<u32>,
        out: Vec<Tile>,
        /// Four i32 per tile: x, y, size, 0xRRGGBB.
        buf: Vec<i32>,
        events: u32,
    }

    thread_local! {
        static WORLD: RefCell<World> = RefCell::new(World { size: (1, 1), ..Default::default() });
    }

    /// Room for `n` portals; the landing writes them here, then calls `load`.
    #[no_mangle]
    pub extern "C" fn portals_buf(n: u32) -> *mut u32 {
        WORLD.with(|w| {
            let w = &mut *w.borrow_mut();
            w.input = vec![0; n as usize * STRIDE];
            w.input.as_mut_ptr()
        })
    }

    #[no_mangle]
    pub extern "C" fn load() {
        WORLD.with(|w| {
            let w = &mut *w.borrow_mut();
            w.scenes = w
                .input
                .chunks(STRIDE)
                .enumerate()
                .map(|(i, p)| {
                    let look = Look {
                        shape: Shape { cols: p[0] as i32, rows: p[1] as i32, corner: Corner::from_u32(p[2]) },
                        motif: Motif::from_u32(p[3]),
                        theme: Theme { ramp: [p[4], p[5], p[6], p[7], p[8]], accent: p[9] },
                    };
                    Scene::new(5 + i as u32, look)
                })
                .collect();
        });
    }

    /// The canvas size in device pixels.
    #[no_mangle]
    pub extern "C" fn resize(w: u32, h: u32) {
        WORLD.with(|w0| w0.borrow_mut().size = (w, h));
    }

    /// Draw the frame at `t` with the carousel at `pos` moving at `vel` portals/s; returns the tile
    /// count. `flags`: 1 returning, 2 reduce.
    #[no_mangle]
    pub extern "C" fn frame(t: f32, prev: f32, stage: u32, opened_at: f32, flags: u32, pos: f32, vel: f32) -> u32 {
        let inp = Input { t, prev, stage: Stage::from_u32(stage), opened_at, returning: flags & 1 != 0, reduce: flags & 2 != 0, vel };
        WORLD.with(|w| {
            let w = &mut *w.borrow_mut();
            w.events = carousel(&w.scenes, pos, &inp, w.size.0, w.size.1, &mut w.out);
            w.buf.clear();
            for t in &w.out {
                w.buf.extend_from_slice(&[t.x, t.y, t.size, t.rgb as i32]);
            }
            w.out.len() as u32
        })
    }

    #[no_mangle]
    pub extern "C" fn tiles() -> *const i32 {
        WORLD.with(|w| w.borrow().buf.as_ptr())
    }

    /// Device px between neighbouring portals at the current size.
    #[no_mangle]
    pub extern "C" fn gap() -> f32 {
        WORLD.with(|w| {
            let w = w.borrow();
            spacing(&w.scenes, w.size.0, w.size.1)
        })
    }

    /// Portal `p`'s frame box in device px, `[x, y, w, h]`, at the carousel's
    /// current position.
    #[no_mangle]
    pub extern "C" fn portal_rect(pos: f32, p: u32) -> *const i32 {
        thread_local! { static R: RefCell<[i32; 4]> = const { RefCell::new([0; 4]) }; }
        let r = WORLD.with(|w| {
            let w = w.borrow();
            rect(&w.scenes, pos, p as usize, w.size.0, w.size.1)
        });
        R.with(|b| {
            *b.borrow_mut() = r;
            b.as_ptr() as *const i32
        })
    }

    /// Haptic events from the last frame, as bits (1 = tick).
    #[no_mangle]
    pub extern "C" fn events() -> u32 {
        WORLD.with(|w| w.borrow().events)
    }

    /// The landing's portal pitch and tile in device px at the current size, as `pitch << 16 | tile`.
    #[no_mangle]
    pub extern "C" fn metrics() -> u32 {
        WORLD.with(|w| {
            let w = w.borrow();
            let l = base(&w.scenes, w.size.0, w.size.1);
            ((l.pitch as u32) << 16) | l.tile as u32
        })
    }

    #[derive(Default)]
    struct DiveWorld {
        dive: Option<Dive>,
        frame: Frame,
        /// Twelve f32: LAR's x, y, scale, opacity; done; the fill (or -1); the back's x, y, w, h, colour (or -1); pools.
        info: [f32; 12],
    }

    thread_local! {
        static DIVE: RefCell<DiveWorld> = RefCell::new(DiveWorld::default());
    }

    /// Start a dive of the portal in `portals_buf(1)`. `pitch` 0: a launch, which
    /// picks its own place on Today's grid.
    #[no_mangle]
    #[allow(clippy::too_many_arguments)]
    pub extern "C" fn dive_start(w: u32, h: u32, q: i32, void_rgb: u32, ground: u32, dot: u32, seed: u32, ox: i32, oy: i32, pitch: i32, tile: i32, lar_x: f32, lar_y: f32, dpr: f32) {
        let p = WORLD.with(|w| w.borrow().input.clone());
        let look = Look {
            shape: Shape { cols: p[0] as i32, rows: p[1] as i32, corner: Corner::from_u32(p[2]) },
            motif: Motif::from_u32(p[3]),
            theme: Theme { ramp: [p[4], p[5], p[6], p[7], p[8]], accent: p[9] },
        };
        let first = pitch > 0;
        let lay = if first { Layout { pitch, tile, ox, oy } } else { launch_layout(w, h, q, look.shape.cols * 2, look.shape.rows * 2) };
        let params = Params { w, h, q, void_rgb, ground, dot, first, seed, lay, lar_from: (lar_x, lar_y), dpr };
        DIVE.with(|d| d.borrow_mut().dive = Some(Dive::new(seed, look, params)));
    }

    /// Draw the dive at `t`; returns the tile count. `ready_at` < 0: data isn't ready yet.
    #[no_mangle]
    pub extern "C" fn dive_frame(t: f32, ready_at: f32) -> u32 {
        DIVE.with(|d| {
            let d = &mut *d.borrow_mut();
            let Some(dive) = &d.dive else { return 0 };
            dive.frame(t, if ready_at < 0.0 { f32::INFINITY } else { ready_at }, &mut d.frame);
            let f = &d.frame;
            let back = f.back.unwrap_or([0, 0, 0, 0, -1]);
            d.info = [f.lar[0], f.lar[1], f.lar[2], f.lar[3], f.done as u32 as f32, f.fill.map_or(-1.0, |c| c as f32), back[0] as f32, back[1] as f32, back[2] as f32, back[3] as f32, back[4] as f32, f.pools.len() as f32];
            f.tiles.len() as u32
        })
    }

    #[no_mangle]
    pub extern "C" fn dive_tiles() -> *const [i32; 4] {
        DIVE.with(|d| d.borrow().frame.tiles.as_ptr())
    }

    #[no_mangle]
    pub extern "C" fn dive_pools() -> *const [i32; 4] {
        DIVE.with(|d| d.borrow().frame.pools.as_ptr())
    }

    #[no_mangle]
    pub extern "C" fn dive_info() -> *const f32 {
        DIVE.with(|d| d.borrow().info.as_ptr())
    }

    /// When the dive's field starts landing, for the reveal's haptic. `ready_at` < 0: data isn't ready yet.
    #[no_mangle]
    pub extern "C" fn dive_arrive(ready_at: f32) -> f32 {
        DIVE.with(|d| d.borrow().dive.as_ref().map_or(0.0, |x| x.timeline(if ready_at < 0.0 { f32::INFINITY } else { ready_at }).arrive))
    }
}
