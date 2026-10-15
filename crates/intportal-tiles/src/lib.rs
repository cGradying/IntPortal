//! The landing's tile portal (spec 010, ADR 0004): a pure scene in [`scene`],
//! and plain WebAssembly exports the landing calls once per frame.

pub mod scene;

/// u32s per portal in the buffer the landing fills: cols, rows, corner,
/// motif, five ramp tones, accent.
pub const STRIDE: usize = 10;

#[cfg(target_arch = "wasm32")]
mod wasm {
    use crate::scene::{carousel, gap as spacing, rect, Corner, Input, Look, Motif, Scene, Shape, Stage, Theme, Tile};
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

    /// Draw the frame at `t` with the carousel at `pos`; returns the tile
    /// count. `flags`: 1 returning, 2 reduce.
    #[no_mangle]
    pub extern "C" fn frame(t: f32, prev: f32, stage: u32, opened_at: f32, flags: u32, pos: f32) -> u32 {
        let inp = Input { t, prev, stage: Stage::from_u32(stage), opened_at, returning: flags & 1 != 0, reduce: flags & 2 != 0 };
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

    /// The selected portal's frame box in device px, `[x, y, w, h]`, at the
    /// carousel's current position.
    #[no_mangle]
    pub extern "C" fn portal_rect(pos: f32) -> *const i32 {
        thread_local! { static R: RefCell<[i32; 4]> = const { RefCell::new([0; 4]) }; }
        let r = WORLD.with(|w| {
            let w = w.borrow();
            rect(&w.scenes, pos, w.size.0, w.size.1)
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
}
