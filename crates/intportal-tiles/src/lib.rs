//! The landing's tile portal (spec 010, ADR 0004): a pure scene in [`scene`],
//! and plain WebAssembly exports the landing calls once per frame.

pub mod scene;

#[cfg(target_arch = "wasm32")]
mod wasm {
    use crate::scene::{layout, Input, Layout, Scene, Stage, Theme, Tile};
    use std::cell::RefCell;

    struct World {
        scene: Scene,
        layout: Layout,
        out: Vec<Tile>,
        /// Four i32 per tile: x, y, size, 0xRRGGBB.
        buf: Vec<i32>,
        events: u32,
    }

    thread_local! {
        static WORLD: RefCell<World> = RefCell::new(World {
            scene: Scene::new(5),
            layout: layout(1, 1),
            out: Vec::new(),
            buf: Vec::new(),
            events: 0,
        });
        /// The selected portal's ramp (5) then accent, written by the landing.
        static THEME: RefCell<[u32; 6]> = const { RefCell::new([0; 6]) };
    }

    /// Where the landing writes the theme: six 0xRRGGBB values.
    #[no_mangle]
    pub extern "C" fn theme_buf() -> *mut u32 {
        THEME.with(|t| t.as_ptr() as *mut u32)
    }

    /// The canvas size in device pixels.
    #[no_mangle]
    pub extern "C" fn resize(w: u32, h: u32) {
        WORLD.with(|w0| w0.borrow_mut().layout = layout(w, h));
    }

    /// Draw the frame at `t`; returns the tile count. `flags`: 1 returning, 2 reduce.
    #[no_mangle]
    pub extern "C" fn frame(t: f32, prev: f32, stage: u32, opened_at: f32, flags: u32) -> u32 {
        let th = THEME.with(|t| *t.borrow());
        let theme = Theme { ramp: [th[0], th[1], th[2], th[3], th[4]], accent: th[5] };
        let inp = Input { t, prev, stage: Stage::from_u32(stage), opened_at, returning: flags & 1 != 0, reduce: flags & 2 != 0 };
        WORLD.with(|w| {
            let w = &mut *w.borrow_mut();
            w.events = w.scene.frame(&inp, &theme, &w.layout, &mut w.out);
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

    /// Haptic events from the last frame, as bits (1 = tick).
    #[no_mangle]
    pub extern "C" fn events() -> u32 {
        WORLD.with(|w| w.borrow().events)
    }
}
