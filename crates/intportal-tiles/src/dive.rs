//! The dive (spec 010 C26–C30): one field of tiles from the void to Today, as
//! a pure function of time. The camera zooms into the portal's mouth, which
//! holds the field at a finer pitch, until the mouth's tiles are the screen's
//! tiles. Those tiles sit on Today's dot grid, so landing is each one shrinking
//! to a dot and lifting off.
//!
//! Everything is in device pixels. `Frame` is what to draw, in order: an opaque
//! fill, the void's colour pools, then tiles as `[x, y, size, 0xRRGGBBAA]`.

use crate::scene::{mix, Input, Layout, Look, Scene, Stage, FORM};
use std::f32::consts::{PI, TAU};

/// A first sign-in's dive: LAR flies to the mouth, then three changes of form.
const FLY: f32 = 0.42;
const FIRST_ZOOM: f32 = 1.5;
const FIRST_FORMS: u32 = 3;
const FIRST_ARRIVE: f32 = 0.5;
/// A launch: the frame builds, then two changes of form, about 1.8 s (C26).
const BUILD: f32 = 0.45;
const LAUNCH_ZOOM: f32 = 0.95;
const LAUNCH_FORMS: u32 = 2;
const LAUNCH_ARRIVE: f32 = 0.4;
/// Seconds per form once the camera has landed and data is still loading.
const HOLD_FORM: f32 = 0.7;
/// The dark eye's radius, in cells, and how far out its ring of light sits.
const EYE: f32 = 1.7;
const HALO: f32 = 2.7;
/// The arrival front's width, in cells.
const FRONT: f32 = 3.2;
const GLINT_LIFE: f32 = 0.18;
/// A whole number of bands in an angle, so no form has a seam.
const FORMS: u32 = 6;
const BAYER: [f32; 16] = [0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0];

fn clamp01(x: f32) -> f32 {
    x.clamp(0.0, 1.0)
}
fn smooth(x: f32) -> f32 {
    let k = clamp01(x);
    k * k * (3.0 - 2.0 * k)
}
fn ease(x: f32) -> f32 {
    1.0 - (1.0 - clamp01(x)).powi(3)
}
/// 0.5 + 0.5 cos(2 pi x): a form's stripes.
fn wave(x: f32) -> f32 {
    0.5 + 0.5 * (TAU * x).cos()
}
fn rgba(rgb: u32, a: f32) -> i32 {
    ((rgb << 8) | (a.clamp(0.0, 1.0) * 255.0).round() as u32) as i32
}

/// What the dive is given once, at its start.
#[derive(Clone, Copy, Debug)]
pub struct Params {
    pub w: u32,
    pub h: u32,
    /// Today's dot grid pitch.
    pub q: i32,
    pub void_rgb: u32,
    /// The room the student lands in.
    pub ground: u32,
    pub dot: u32,
    /// A first sign-in, or a launch.
    pub first: bool,
    /// Picks the order of the forms, so each dive differs.
    pub seed: u32,
    /// Where the portal stands. A launch uses [`launch_layout`].
    pub lay: Layout,
    /// Where LAR starts, on a first sign-in.
    pub lar_from: (f32, f32),
    /// Device px per CSS px, for LAR's size.
    pub dpr: f32,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Timeline {
    pub fly: f32,
    pub build: f32,
    pub zoom: f32,
    pub zoom_end: f32,
    pub forms: u32,
    pub arrive: f32,
    pub arrive_end: f32,
}

/// `ready_at` is when Today has painted under the field, or infinity until then.
pub fn timeline(first: bool, ready_at: f32) -> Timeline {
    let (fly, build, zoom_for, forms, arrive_for) =
        if first { (FLY, 0.0, FIRST_ZOOM, FIRST_FORMS, FIRST_ARRIVE) } else { (0.0, BUILD, LAUNCH_ZOOM, LAUNCH_FORMS, LAUNCH_ARRIVE) };
    let zoom = fly + build;
    let zoom_end = zoom + zoom_for;
    let arrive = zoom_end.max(ready_at);
    Timeline { fly, build, zoom, zoom_end, forms, arrive, arrive_end: arrive + arrive_for }
}

/// A launch's portal: centred across, a little above the middle, its tiles on
/// Today's grid, so the field's dots already sit where Today's will.
pub fn launch_layout(w: u32, h: u32, q: i32, gc: i32, gr: i32) -> Layout {
    let tile = ((q * 11 + 7) / 14).max(1);
    let inset = (q - tile) / 2;
    let col = (w as i32 - gc * q) / 2 / q;
    let row = (h as i32 * 2 / 5 - gr * q / 2) / q;
    Layout { pitch: q, tile, ox: col * q + inset, oy: row.max(0) * q + inset }
}

/// One tile of the mouth's field: everything about it that never changes.
struct Cell {
    /// From the screen's centre, in device px, once it has landed.
    sx: f32,
    sy: f32,
    dx: f32,
    dy: f32,
    r: f32,
    /// Angle as a fraction of a turn.
    a: f32,
    /// Depth down a round and a square tunnel.
    z: f32,
    zs: f32,
    fog: f32,
    halo: f32,
    dither: f32,
}

/// A form's brightness for a cell, 0 to 1, at shader time `s`.
fn form(n: u32, c: &Cell, s: f32) -> f32 {
    match n % FORMS {
        0 => wave(c.a * 5.0 + c.z * 0.6 + s * 0.12) * (0.7 + 0.3 * wave(c.z + s * 0.8)), // spiral arms
        1 => wave(c.z * 1.1 + s * 0.8),                                                  // round rings
        2 => wave(c.zs * 1.1 + s * 0.8),                                                 // square corridor
        3 => wave(c.z + 0.22 * (TAU * c.a * 6.0).cos() + s * 0.6),                       // petals
        4 => 0.5 + 0.5 * (TAU * (c.a * 4.0 + s * 0.08)).cos() * (TAU * (c.z * 1.2 + s * 0.7)).cos(), // polar checks
        _ => 0.5 + 0.25 * ((TAU * (c.dx * 0.055 + s * 0.18)).cos() + (TAU * (c.dy * 0.04 - s * 0.14 + 0.15 * (TAU * c.dx * 0.03).cos())).cos()), // plasma
    }
}

const GLOW: usize = 5;
const GLINT: usize = 6;
const DARK: usize = 7;

/// The look every form shares: dark parts glow at their edges, the far end is
/// a dark eye in a ring of light, and brightness lands on the school's ramp
/// through a Bayer dither. Returns a palette index.
fn shade(c: &Cell, f: f32) -> usize {
    if c.r < EYE {
        return DARK;
    }
    let edge = (-((f - 0.3) / 0.11).powi(2)).exp() * c.fog;
    let glow = c.halo.max(edge) + 0.25 * c.dither;
    if glow > 0.95 {
        return GLINT;
    }
    if glow > 0.7 {
        return GLOW;
    }
    ((f * c.fog * 5.0 + c.dither - 0.5).floor().max(0.0) as usize).min(4)
}

#[derive(Default)]
pub struct Frame {
    pub fill: Option<u32>,
    /// The dark behind the mouth's tiles, as `[x, y, w, h, 0xRRGGBB]`.
    pub back: Option<[i32; 5]>,
    /// Soft colour pools, as `[x, y, radius, 0xRRGGBBAA]`.
    pub pools: Vec<[i32; 4]>,
    pub tiles: Vec<[i32; 4]>,
    /// LAR's centre, device px per art pixel, and opacity. Opacity 0: not drawn.
    pub lar: [f32; 4],
    /// `ready_at` has passed and the field has landed.
    pub done: bool,
}

/// One frame tile: where it sits on the portal's grid and when it builds.
struct Stone {
    c: i32,
    r: i32,
    order: f32,
}

pub struct Dive {
    p: Params,
    look: Look,
    scene: Scene,
    stones: Vec<Stone>,
    mouth: Vec<bool>,
    /// The mouth's box and centre, in device px.
    mouth_box: [f32; 4],
    cx: f32,
    cy: f32,
    /// How far the camera zooms: until the mouth's tiles are the screen's tiles.
    zmax: f32,
    cells: Vec<Cell>,
}

impl Dive {
    pub fn new(seed: u32, look: Look, p: Params) -> Dive {
        let scene = Scene::new(seed, look);
        let (gc, gr) = (scene.gc, scene.gr);
        let mut mouth = vec![false; (gc * gr) as usize];
        let (mut x0, mut x1, mut y0, mut y1) = (gc, 0, gr, 0);
        for &(c, r) in scene.interior_cells() {
            mouth[(r * gc + c) as usize] = true;
            x0 = x0.min(c);
            x1 = x1.max(c + 1);
            y0 = y0.min(r);
            y1 = y1.max(r + 1);
        }
        let lay = p.lay;
        let inset = (lay.pitch - lay.tile) as f32 / 2.0;
        let edge = |o: i32, n: i32| o as f32 + n as f32 * lay.pitch as f32 - inset;
        let mouth_box = [edge(lay.ox, x0), edge(lay.oy, y0), edge(lay.ox, x1), edge(lay.oy, y1)];
        let (cx, cy) = ((mouth_box[0] + mouth_box[2]) / 2.0, (mouth_box[1] + mouth_box[3]) / 2.0);
        let (sw, sh) = (p.w as f32 / 2.0, p.h as f32 / 2.0);
        let q = p.q as f32;
        let in_mouth = |s: f32, t: f32, z: f32| {
            let c = ((cx + s / z - lay.ox as f32 + inset) / lay.pitch as f32).floor() as i32;
            let r = ((cy + t / z - lay.oy as f32 + inset) / lay.pitch as f32).floor() as i32;
            c >= 0 && r >= 0 && c < gc && r < gr && mouth[(r * gc + c) as usize]
        };
        // Zoom until every tile on screen comes from the mouth, whatever its shape.
        let (cols, rows) = ((p.w as f32 / q).ceil() as i32, (p.h as f32 / q).ceil() as i32);
        let pos = |n: i32, half: f32| n as f32 * q + q / 2.0 - half;
        let mut zmax = (p.w as f32 / ((x1 - x0) as f32 * lay.pitch as f32)).max(p.h as f32 / ((y1 - y0) as f32 * lay.pitch as f32));
        while !(0..rows).all(|j| (0..cols).all(|i| in_mouth(pos(i, sw), pos(j, sh), zmax))) && zmax < 64.0 {
            zmax *= 1.04;
        }
        // Every tile the mouth can ever show, on the grid it lands on.
        let reach = |a: f32| (a * zmax / q).ceil() as i32 + 2;
        let (rx, ry) = (reach((x1 - x0) as f32 * lay.pitch as f32), reach((y1 - y0) as f32 * lay.pitch as f32));
        let (mid_i, mid_j) = ((sw / q) as i32, (sh / q) as i32);
        let mut cells = Vec::new();
        for j in mid_j - ry..=mid_j + ry {
            for i in mid_i - rx..=mid_i + rx {
                let (sx, sy) = (pos(i, sw), pos(j, sh));
                if !in_mouth(sx, sy, zmax) {
                    continue;
                }
                let (dx, dy) = (sx / q, sy / q);
                let r = dx.hypot(dy);
                cells.push(Cell {
                    sx,
                    sy,
                    dx,
                    dy,
                    r,
                    a: dy.atan2(dx) / TAU,
                    z: 7.0 / (r + 0.8),
                    zs: 7.0 / (dx.abs().max(dy.abs() * 0.55) + 0.8),
                    fog: 0.45 + 0.55 * clamp01(r / 5.0),
                    halo: (-(r - HALO).powi(2)).exp(),
                    dither: (BAYER[((j & 3) * 4 + (i & 3)) as usize] + 0.5) / 16.0,
                });
            }
        }
        let stones = scene.frame_cells().map(|(c, r, d)| Stone { c, r, order: d / 11.0 * 0.86 }).collect();
        Dive { p, look, scene, stones, mouth, mouth_box, cx, cy, zmax, cells }
    }

    pub fn timeline(&self, ready_at: f32) -> Timeline {
        timeline(self.p.first, ready_at)
    }

    pub fn zmax(&self) -> f32 {
        self.zmax
    }

    /// Draw the frame at `t`. Nothing here keeps state: scrubbing `t` works.
    pub fn frame(&self, t: f32, ready_at: f32, out: &mut Frame) {
        out.pools.clear();
        out.tiles.clear();
        out.fill = None;
        out.back = None;
        out.lar = [0.0; 4];
        let tl = self.timeline(ready_at);
        out.done = t >= tl.arrive_end;
        if out.done {
            return;
        }
        let p = &self.p;
        let (w, h) = (p.w as f32, p.h as f32);
        let (sx, sy) = (w / 2.0, h / 2.0);
        let q = p.q as f32;
        let th = self.look.theme;
        let bk = if p.first { 1.0 } else { clamp01(t / tl.build) };
        let open = if p.first { 1.0 } else { clamp01((bk - 0.8) * 5.0) };

        // Forms: a new one every formT, slower once the camera has landed and data is loading.
        let form_t = (tl.zoom_end - tl.zoom) / tl.forms as f32;
        let fs = if t < tl.zoom_end { (t - tl.zoom).max(0.0) / form_t } else { tl.forms as f32 + (t - tl.zoom_end) / HOLD_FORM };
        let fn_ = fs.floor();
        let fm = smooth((fs - fn_ - 0.4) / 0.6);
        let fl = fn_ + fm;
        let step = 1 + p.seed % (FORMS - 1);
        let form_of = |n: u32| p.seed.wrapping_mul(5).wrapping_add(n.wrapping_mul(step));
        let (form_a, form_b) = (form_of(fn_ as u32), form_of(fn_ as u32 + 1));
        // Speed ramp: shader time and the camera surge through each morph and coast between.
        let tau = t * 0.5 + fl * 1.3;
        let zk = 0.25 * smooth((t - tl.zoom) / (tl.zoom_end - tl.zoom)) + 0.75 * smooth(fl / tl.forms as f32);
        let z = self.zmax.powf(zk);
        let (fx, fy) = (self.cx + (sx - self.cx) * zk, self.cy + (sy - self.cy) * zk);

        let ak = if t < tl.arrive { 0.0 } else { clamp01((t - tl.arrive) / (tl.arrive_end - tl.arrive)) };
        let front = ease(ak) * (w.hypot(h) / q / 2.0 + FRONT * 2.0);
        let warm = smooth((t - (tl.arrive - 0.18)) / 0.3);
        let gap = mix(p.void_rgb, p.ground, warm);
        let home = mix(p.ground, p.dot, 0.35);
        let glint = mix(th.accent, 0xfff6dc, 0.45);

        if ak == 0.0 {
            out.fill = Some(gap);
            let wash = 1.0 - warm;
            if wash > 0.0 {
                let pool = |x: f32, y: f32, r: f32, c: u32, a: f32| [(x * w) as i32, (y * h) as i32, (r * w) as i32, rgba(c, a * wash)];
                out.pools.push(pool(0.26 + 0.18 * (tau * 0.5).sin(), 0.28 + 0.1 * (tau * 0.4).cos(), 0.75, th.ramp[2], 0.42));
                out.pools.push(pool(0.8 + 0.14 * (tau * 0.6).cos(), 0.66 + 0.12 * (tau * 0.35).sin(), 0.85, th.ramp[3], 0.22));
                out.pools.push(pool(0.5 + 0.3 * (tau * 0.3 + 2.0).sin(), 0.95 + 0.04 * tau.cos(), 0.65, th.accent, 0.12));
            }
            self.outside(t, bk, open, z, fx, fy, warm, home, out);
        }

        // The mouth: one palette a frame, warmed to the room, in four steps toward the dot.
        if open > 0.0 {
            let warmed = |c: u32| if warm > 0.0 { mix(c, home, warm * 0.82) } else { c };
            let base: [u32; 8] = [th.ramp[0], th.ramp[1], th.ramp[2], th.ramp[3], th.ramp[4], mix(th.ramp[4], glint, 0.5), glint, mix(p.void_rgb, th.ramp[0], 0.25)].map(warmed);
            let steps = base.map(|c| [0.0, 1.0, 2.0, 3.0].map(|s: f32| rgba(mix(c, p.dot, s / 3.0), open)));
            let rims = base.map(|c| rgba(mix(c, glint, 0.75), open));
            let k = z / self.zmax;
            if ak == 0.0 {
                let [x0, y0, x1, y1] = self.mouth_box;
                let (x0, y0) = ((fx + (x0 - self.cx) * z).max(0.0), (fy + (y0 - self.cy) * z).max(0.0));
                let (x1, y1) = ((fx + (x1 - self.cx) * z).min(w), (fy + (y1 - self.cy) * z).min(h));
                out.back = Some([x0 as i32, y0 as i32, (x1 - x0).ceil() as i32, (y1 - y0).ceil() as i32, mix(mix(p.void_rgb, th.ramp[0], open), gap, warm) as i32]);
            }
            let side = (q - 2.0 * (q / 14.0)) * k;
            let gaps = rgba(gap, 1.0);
            for c in &self.cells {
                let (x, y) = (fx + c.sx * k, fy + c.sy * k);
                let half = q * k / 2.0;
                if x + half < 0.0 || y + half < 0.0 || x - half > w || y - half > h {
                    continue;
                }
                let fa = form(form_a, c, tau);
                let f = if fm > 0.0 { fa + (form(form_b, c, tau) - fa) * fm } else { fa };
                let idx = shade(c, f);
                let mut size = side;
                let mut fill = steps[idx][0];
                if ak > 0.0 {
                    let kk = smooth((front - c.r) / FRONT);
                    let lift = 0.45 + 0.35 * c.dither;
                    if kk > lift {
                        // Lifted: Today's own dot shows here, and the tile leaves a glint that fades.
                        let g = (kk - lift) / GLINT_LIFE;
                        if g < 1.0 {
                            let s = (q / 14.0) * (1.8 + 3.2 * (1.0 - g));
                            out.tiles.push([(x - s / 2.0).round() as i32, (y - s / 2.0).round() as i32, s.round().max(1.0) as i32, rgba(glint, 0.85 * (1.0 - g) * (1.0 - g))]);
                        }
                        continue;
                    }
                    // The front glows: tiles flare and swell as it reaches them, then shrink to a dot.
                    let rim = (1.0 - (kk - 0.18).abs() / 0.18).max(0.0);
                    let sk = clamp01(kk / lift);
                    out.tiles.push([(x - q / 2.0).round() as i32, (y - q / 2.0).round() as i32, p.q, gaps]);
                    size = (size + ((q / 14.0) * 1.8 - size) * sk) * (1.0 + 0.28 * rim);
                    fill = if rim > 0.5 { rims[idx] } else { steps[idx][(sk * 3.0).round() as usize] };
                }
                out.tiles.push([(x - size / 2.0).round() as i32, (y - size / 2.0).round() as i32, size.round().max(1.0) as i32, fill]);
            }
        }

        // LAR leads: to the mouth, then in ahead of the camera, gone into the tunnel before it lands.
        if p.first && ak == 0.0 {
            let fly = ease(t / tl.fly);
            let (x0, y0) = p.lar_from;
            let (mx, my) = (self.cx, self.cy + (self.mouth_box[3] - self.cy) * 0.8);
            let (mut x, mut y, mut sc, mut alpha) = (x0 + (mx - x0) * fly, y0 + (my - y0) * fly - (fly * PI).sin() * 46.0 * p.dpr, 2.0, 1.0);
            if zk > 0.0 {
                x = mx + (sx - mx) * zk;
                y = my + (sy - my) * zk;
                sc = 2.0 - 1.5 * zk;
                alpha = 1.0 - smooth((zk - 0.65) / 0.3);
            }
            out.lar = [x, y, sc * p.dpr, alpha];
        }
    }

    /// The field outside the mouth: dots lit by the portal, and the frame built
    /// from them. They grow and fly past as the camera dives.
    #[allow(clippy::too_many_arguments)]
    fn outside(&self, t: f32, bk: f32, open: f32, z: f32, fx: f32, fy: f32, warm: f32, home: u32, out: &mut Frame) {
        let p = &self.p;
        let lay = p.lay;
        let (w, h) = (p.w as f32, p.h as f32);
        let pitch = lay.pitch as f32;
        let (gc, gr) = (self.scene.gc, self.scene.gr);
        let unit = pitch / 14.0;
        let th = self.look.theme;
        let tone = |c: u32| if warm > 0.0 { mix(c, home, warm * 0.82) } else { c };
        let lo_c = -((self.cx + 1.0) / pitch).ceil() as i32 - 1;
        let hi_c = ((w - self.cx) / pitch).ceil() as i32 + 1;
        let lo_r = -((self.cy + 1.0) / pitch).ceil() as i32 - 1;
        let hi_r = ((h - self.cy) / pitch).ceil() as i32 + 1;
        let (mid_c, mid_r) = (((self.cx - lay.ox as f32) / pitch).round() as i32, ((self.cy - lay.oy as f32) / pitch).round() as i32);
        // The frame takes its real colours from the portal scene, so a first sign-in lines up with the landing.
        let mut frame_rgb = vec![0u32; (gc * gr) as usize];
        let mut shown = Vec::new();
        self.scene.frame(&Input { t: FORM + 8.0, prev: FORM + 8.0, stage: Stage::Open, opened_at: 0.0, returning: false, reduce: true, vel: 0.0, poke: crate::scene::NO_POKE }, &Layout { pitch: 1, tile: 1, ox: 0, oy: 0 }, 0.0, &mut shown);
        for s in shown.iter().filter(|s| s.frame) {
            frame_rgb[(s.r * gc + s.c) as usize] = s.rgb;
        }
        let dim = mix(p.void_rgb, th.accent, 0.35);
        let spot = |c: i32, r: i32, size: f32, rgb: u32, a: f32, out: &mut Frame| {
            let x = fx + (lay.ox as f32 + c as f32 * pitch + lay.tile as f32 / 2.0 - self.cx) * z;
            let y = fy + (lay.oy as f32 + r as f32 * pitch + lay.tile as f32 / 2.0 - self.cy) * z;
            let half = pitch * z / 2.0;
            if x + half < 0.0 || y + half < 0.0 || x - half > w || y - half > h || a <= 0.01 {
                return;
            }
            let s = (size * z).max(1.0);
            out.tiles.push([(x - s / 2.0).round() as i32, (y - s / 2.0).round() as i32, s.round() as i32, rgba(tone(rgb), a)]);
        };
        for rr in lo_r..=hi_r {
            for cc in lo_c..=hi_c {
                let (c, r) = (mid_c + cc, mid_r + rr);
                let inside = c >= 0 && r >= 0 && c < gc && r < gr;
                let n = (r * gc + c) as usize;
                if inside && frame_rgb[n] != 0 {
                    continue;
                }
                let is_mouth = inside && self.mouth[n];
                if is_mouth && open >= 1.0 {
                    continue;
                }
                let (dx, dy) = (cc as f32, rr as f32);
                let d = dx.hypot(dy);
                let light = (-(d - 7.0).max(0.0) / 3.4).exp() * bk;
                let turn = 0.5 + 0.5 * (dy.atan2(dx) * 3.0 - t * 2.2 + d * 0.7).sin();
                let size = unit * (2.0 + light * (1.5 + 3.0 * turn));
                let lit = if turn > 0.6 { th.ramp[4] } else { th.ramp[3] };
                let a = (0.32 + light * 0.6) * if is_mouth { 1.0 - open } else { 1.0 };
                spot(c, r, size, mix(dim, lit, light), a, out);
            }
        }
        for s in &self.stones {
            let k = clamp01((bk - s.order) * 7.0);
            let pop = if k < 1.0 { 1.0 + (k * PI).sin() * 0.14 } else { 1.0 };
            let rgb = frame_rgb[(s.r * gc + s.c) as usize];
            let size = 2.0 * unit + (lay.tile as f32 - 2.0 * unit) * k * pop;
            spot(s.c, s.r, size, mix(dim, rgb, k), 0.32 + 0.68 * k, out);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scene::{Corner, Motif, Shape, Theme};

    const THEME: Theme = Theme { ramp: [0x3b1220, 0x7a1c2c, 0xb5412a, 0xe08a35, 0xf3cf6a], accent: 0xe8b04a };
    fn look(shape: Shape) -> Look {
        Look { shape, motif: Motif::Swirl, theme: THEME }
    }
    const SIS: Shape = Shape { cols: 6, rows: 8, corner: Corner::Square };
    const SHAPES: [Shape; 4] = [SIS, Shape { cols: 7, rows: 7, corner: Corner::Cut }, Shape { cols: 6, rows: 9, corner: Corner::Arch }, Shape { cols: 8, rows: 7, corner: Corner::Square }];

    fn params(first: bool, shape: Shape) -> Params {
        let (w, h, q) = (1179, 2556, 42);
        let lay = if first { Layout { pitch: 63, tile: 50, ox: 200, oy: 300 } } else { launch_layout(w, h, q, shape.cols * 2, shape.rows * 2) };
        Params { w, h, q, void_rgb: 0x060607, ground: 0xf4f2ef, dot: 0x7a1128, first, seed: 3, lay, lar_from: (400.0, 1800.0), dpr: 3.0 }
    }
    fn dive(first: bool) -> Dive {
        Dive::new(5, look(SIS), params(first, SIS))
    }
    fn at(d: &Dive, t: f32, ready: f32) -> Frame {
        let mut f = Frame::default();
        d.frame(t, ready, &mut f);
        f
    }

    #[test]
    fn c26_a_launch_lasts_at_least_the_minimum_and_ends_with_the_data() {
        let quick = timeline(false, 0.0);
        assert!((quick.arrive_end - 1.8).abs() < 0.01, "{quick:?}");
        assert_eq!(quick.forms, 2);
        let slow = timeline(false, 2.6);
        assert_eq!(slow.arrive, 2.6);
        assert!((slow.arrive_end - 3.0).abs() < 1e-5);
    }

    #[test]
    fn c26_the_tunnel_holds_until_data_is_ready() {
        let d = dive(false);
        let f = at(&d, 30.0, f32::INFINITY);
        assert!(!f.done && f.fill.is_some(), "still fully covered while waiting");
        assert!(at(&d, 31.0, 30.0).done);
    }

    #[test]
    fn c27_a_first_sign_in_takes_about_two_and_a_half_seconds() {
        let tl = timeline(true, 0.0);
        assert!((tl.arrive_end - 2.42).abs() < 0.01, "{tl:?}");
        assert_eq!(tl.forms, 3);
    }

    #[test]
    fn c25_the_dive_is_a_pure_function_of_time() {
        let d = dive(true);
        let (a, b) = (at(&d, 1.3, 0.0), at(&d, 1.3, 0.0));
        assert_eq!(a.tiles, b.tiles);
        assert_eq!(a.pools, b.pools);
    }

    #[test]
    fn c29_the_field_covers_the_screen_until_arrival_for_every_shape() {
        for shape in SHAPES {
            for first in [true, false] {
                let p = params(first, shape);
                let d = Dive::new(5, look(shape), p);
                let tl = d.timeline(0.0);
                let f = at(&d, tl.arrive - 0.001, 0.0);
                assert!(f.fill.is_some(), "{shape:?}");
                // At the top of the zoom, the mouth's tiles reach every corner.
                let hit = |x: i32, y: i32| f.tiles.iter().any(|t| x >= t[0] && y >= t[1] && x < t[0] + t[2] && y < t[1] + t[2]);
                for (x, y) in [(21, 21), (1155, 21), (21, 2541), (1155, 2541), (609, 1281)] {
                    assert!(hit(x, y), "{shape:?} first={first} missing ({x},{y})");
                }
            }
        }
    }

    #[test]
    fn c29_the_tiles_land_on_todays_dots() {
        let d = dive(true);
        let tl = d.timeline(0.0);
        let f = at(&d, tl.arrive + 0.001, 0.0);
        // Covers are the size of the dot grid, sit on it, and hold a dot's centre.
        let covers: Vec<_> = f.tiles.iter().filter(|t| t[2] == 42).collect();
        assert!(covers.len() > 1000);
        assert!(covers.iter().all(|t| t[0] % 42 == 0 && t[1] % 42 == 0), "off grid: {:?}", covers.iter().find(|t| t[0] % 42 != 0));
    }

    #[test]
    fn c29_arrival_lifts_from_the_centre_out_and_ends_with_nothing() {
        let d = dive(true);
        let tl = d.timeline(0.0);
        let covers = |t: f32| at(&d, t, 0.0).tiles.iter().filter(|x| x[2] == 42).count();
        let mid = tl.arrive + (tl.arrive_end - tl.arrive) * 0.2;
        let f = at(&d, mid, 0.0);
        assert!(f.fill.is_none());
        let (cx, cy) = (1179 / 2, 2556 / 2);
        assert!(!f.tiles.iter().any(|t| t[2] == 42 && (t[0] + 21 - cx).abs() < 42 && (t[1] + 21 - cy).abs() < 42), "the centre lifts first");
        assert!(covers(mid) > covers(tl.arrive + (tl.arrive_end - tl.arrive) * 0.5));
        let end = at(&d, tl.arrive_end, 0.0);
        assert!(end.done && end.tiles.is_empty() && end.fill.is_none());
    }

    #[test]
    fn c29_nothing_is_left_on_screen_just_before_the_end() {
        let d = dive(true);
        let tl = d.timeline(0.0);
        assert_eq!(at(&d, tl.arrive_end - 0.001, 0.0).tiles.iter().filter(|x| x[2] == 42).count(), 0);
    }

    #[test]
    fn c29a_no_form_has_a_seam() {
        // Cells either side of where the angle wraps must match.
        let cell = |a: f32| {
            let r = 12.0f32;
            let (dx, dy) = (r * (a * TAU).cos(), r * (a * TAU).sin());
            Cell { sx: 0.0, sy: 0.0, dx, dy, r, a, z: 7.0 / (r + 0.8), zs: 7.0 / (dx.abs().max(dy.abs() * 0.55) + 0.8), fog: 1.0, halo: 0.0, dither: 0.5 }
        };
        for n in 0..FORMS {
            let (a, b) = (form(n, &cell(0.4999), 2.3), form(n, &cell(-0.4999), 2.3));
            assert!((a - b).abs() < 0.02, "form {n}: {a} vs {b}");
        }
    }

    #[test]
    fn c29a_the_far_end_is_a_dark_eye_in_a_ring_of_light() {
        let cell = |r: f32| Cell { sx: 0.0, sy: 0.0, dx: r, dy: 0.0, r, a: 0.0, z: 7.0 / (r + 0.8), zs: 0.0, fog: 0.45 + 0.55 * clamp01(r / 5.0), halo: (-(r - HALO).powi(2)).exp(), dither: 0.5 };
        assert_eq!(shade(&cell(0.5), 1.0), DARK);
        assert_eq!(shade(&cell(HALO), 0.9), GLINT);
    }

    #[test]
    fn c29a_each_seed_takes_its_own_order_and_never_repeats_a_form() {
        for seed in 0..24u32 {
            let step = 1 + seed % (FORMS - 1);
            for n in 0..12u32 {
                let (a, b) = (seed.wrapping_mul(5).wrapping_add(n * step) % FORMS, seed.wrapping_mul(5).wrapping_add((n + 1) * step) % FORMS);
                assert_ne!(a, b);
            }
        }
    }

    #[test]
    fn c29a_the_camera_surges_during_a_morph_and_coasts_between() {
        // Screen speed of the mouth's scale at a morph's middle against a held stretch.
        let tl = timeline(true, 0.0);
        let form_t = (tl.zoom_end - tl.zoom) / tl.forms as f32;
        let zk = |t: f32| {
            let fs = (t - tl.zoom) / form_t;
            let fl = fs.floor() + smooth((fs - fs.floor() - 0.4) / 0.6);
            0.25 * smooth((t - tl.zoom) / (tl.zoom_end - tl.zoom)) + 0.75 * smooth(fl / tl.forms as f32)
        };
        let speed = |t: f32| (zk(t + 0.01) - zk(t)) / 0.01;
        let coast = speed(tl.zoom + form_t * 1.1);
        let surge = speed(tl.zoom + form_t * 1.7);
        assert!(surge > coast * 2.0, "surge {surge} coast {coast}");
    }

    #[test]
    fn c28_lar_flies_in_ahead_and_is_gone_before_it_lands() {
        let d = dive(true);
        let tl = d.timeline(0.0);
        let start = at(&d, 0.0, 0.0).lar;
        assert_eq!((start[0], start[1]), (400.0, 1800.0));
        assert!(at(&d, tl.zoom + 0.5, 0.0).lar[2] < start[2]);
        assert_eq!(at(&d, tl.zoom_end, 0.0).lar[3], 0.0);
        assert_eq!(at(&dive(false), 0.2, 0.0).lar[3], 0.0, "no LAR on a launch");
    }

    #[test]
    fn c26_a_launch_builds_the_frame_from_the_bottom_centre() {
        let d = dive(false);
        let solid = |t: f32| at(&d, t, 0.0).tiles.iter().filter(|x| x[2] >= d.p.lay.tile - 2 && x[2] <= d.p.lay.tile + 6 && (x[3] & 0xff) > 200).count();
        assert!(solid(0.02) < solid(0.15));
    }

    #[test]
    fn a_frame_stays_small_enough_for_a_phone() {
        let d = dive(true);
        let tl = d.timeline(0.0);
        for t in [0.0, tl.zoom + 0.3, tl.zoom + 0.8, tl.zoom_end, tl.arrive + 0.1] {
            assert!(at(&d, t, 0.0).tiles.len() < 7000, "t={t}: {}", at(&d, t, 0.0).tiles.len());
        }
    }
}
