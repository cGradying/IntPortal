//! The tile portal as a pure function of time and state (spec 010 C25),
//! grown from the portal-v8 prototype. Each portal has its own look (spec 012):
//! a frame shape one block thick, made of 2 by 2 tile blocks, an interior
//! motif, and a theme. Everything sits on a black void.
//!
//! Positions are worked out in "base units", the prototype's 14 px pitch and
//! 11 px tile, then scaled to whole device pixels by [`layout`].

use std::collections::VecDeque;
use std::f32::consts::{PI, TAU};

/// The frame's four obsidian tones, darkest first, before a portal's tint.
pub const TONES: [u32; 4] = [0x1a1622, 0x241f2e, 0x2f2939, 0x3c3548];
/// The light core a tile shows on its first frame.
pub const CORE: u32 = 0xece7dc;
pub const VOID: u32 = 0x060607;

/// Each tile's spawn: it grows from a small light core with a little
/// overshoot, flashes the accent, and eases into its tone over this long.
const POP: f32 = 0.2;
/// When the bottom-centre tiles appear.
const START: f32 = 0.15;
/// The whole ring takes this long to climb from the bottom to the top.
const CLIMB: f32 = 0.495;
/// A tile's delay inside its block, per step right or down.
const SUB: f32 = 0.02;
/// The two sides meet at the top: one haptic tick (C7).
pub const MEET: f32 = START + CLIMB;
/// The frame is standing: the last tile has finished its pop (C6).
pub const FORM: f32 = MEET + 2.0 * SUB + POP;
/// Idle flips start this long after the frame stands, one per tile per slot.
const FLIP_AFTER: f32 = 2.0;
const SLOT: f32 = 6.5;

/// Haptic events in a frame, as bits.
pub const TICK: u32 = 1;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Stage {
    Rest,
    Connecting,
    Open,
}

impl Stage {
    pub fn from_u32(n: u32) -> Stage {
        match n {
            1 => Stage::Connecting,
            2 => Stage::Open,
            _ => Stage::Rest,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Corner {
    Square,
    /// The four corner blocks dropped.
    Cut,
    /// The top corners stepped in, like an arch.
    Arch,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Motif {
    Swirl,
    Ripple,
    Bloom,
    Rain,
    Lattice,
    Aurora,
}

impl Corner {
    pub fn from_u32(n: u32) -> Corner {
        match n {
            1 => Corner::Cut,
            2 => Corner::Arch,
            _ => Corner::Square,
        }
    }
}

impl Motif {
    pub fn from_u32(n: u32) -> Motif {
        match n {
            1 => Motif::Ripple,
            2 => Motif::Bloom,
            3 => Motif::Rain,
            4 => Motif::Lattice,
            5 => Motif::Aurora,
            _ => Motif::Swirl,
        }
    }
}

/// A frame of `cols` by `rows` blocks.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Shape {
    pub cols: i32,
    pub rows: i32,
    pub corner: Corner,
}

/// A portal's look: five ramp tones and one accent, as 0xRRGGBB (spec 012 C7).
#[derive(Clone, Copy, Debug)]
pub struct Theme {
    pub ramp: [u32; 5],
    pub accent: u32,
}

#[derive(Clone, Copy, Debug)]
pub struct Look {
    pub shape: Shape,
    pub motif: Motif,
    pub theme: Theme,
}

#[derive(Clone, Copy, Debug)]
pub struct Input {
    /// Seconds since the landing appeared.
    pub t: f32,
    /// The previous frame's `t`, so events fire once.
    pub prev: f32,
    pub stage: Stage,
    /// When the stage became `Open`, in the same clock as `t`.
    pub opened_at: f32,
    /// Signed in already: the frame is standing from the start (C8).
    pub returning: bool,
    /// Reduce Motion: one still, open portal.
    pub reduce: bool,
}

/// Whole device pixels: the pitch between tiles, the tile's side, and the
/// top-left of the grid, centred in the canvas.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Layout {
    pub pitch: i32,
    pub tile: i32,
    pub ox: i32,
    pub oy: i32,
}

/// Fit a `gc` by `gr` tile grid, with a tile of margin all round, into any
/// canvas, so every phone's aspect ratio gets the largest crisp portal.
pub fn layout(w: u32, h: u32, gc: i32, gr: i32) -> Layout {
    let pitch = (w / (gc as u32 + 2)).min(h / (gr as u32 + 2)).max(1) as i32;
    let tile = ((pitch * 11 + 7) / 14).max(1);
    Layout { pitch, tile, ox: (w as i32 - gc * pitch + (pitch - tile)) / 2, oy: (h as i32 - gr * pitch + (pitch - tile)) / 2 }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Tile {
    pub c: i32,
    pub r: i32,
    pub x: i32,
    pub y: i32,
    pub size: i32,
    pub rgb: u32,
    /// Part of the frame, not the interior.
    pub frame: bool,
}

struct Mark {
    c: i32,
    r: i32,
    tone: usize,
    /// Ring distance from the bottom centre, scaled so the top is 11.
    d: f32,
    /// Position round the ring from the bottom centre, 0 to 24.
    pos: f32,
    start: f32,
    inner: bool,
}

struct Star {
    a: f32,
    d: f32,
    s: f32,
}

pub struct Scene {
    look: Look,
    /// The grid in tiles.
    pub gc: i32,
    pub gr: i32,
    marks: Vec<Mark>,
    interior: Vec<(i32, i32)>,
    stars: Vec<Star>,
    /// The four frame tones with a breath of the portal's colour.
    pub tones: [u32; 4],
}

/// A small, stable hash to [0, 1).
fn hash(a: u32, b: u32) -> f32 {
    let mut x = a.wrapping_mul(0x9E37_79B1) ^ b.wrapping_mul(0x85EB_CA77) ^ 0x27D4_EB2F;
    x ^= x >> 15;
    x = x.wrapping_mul(0x2C1B_3C6D);
    x ^= x >> 12;
    x = x.wrapping_mul(0x297A_2D39);
    x ^= x >> 15;
    (x >> 8) as f32 / (1u32 << 24) as f32
}

pub fn mix(a: u32, b: u32, k: f32) -> u32 {
    let ch = |v: u32, s: u32| ((v >> s) & 0xff) as f32;
    [16, 8, 0].iter().fold(0, |acc, &s| {
        let v = ch(a, s) + (ch(b, s) - ch(a, s)) * k;
        acc | ((v.round().clamp(0.0, 255.0) as u32) << s)
    })
}

/// Ease out with a small overshoot (about 5 %), for the spawn.
fn back(x: f32) -> f32 {
    let (c1, x) = (0.9, x - 1.0);
    1.0 + (c1 + 1.0) * x * x * x + c1 * x * x
}

fn smooth(x: f32) -> f32 {
    let x = x.clamp(0.0, 1.0);
    x * x * (3.0 - 2.0 * x)
}

/// The frame's blocks for a shape, one block thick.
pub fn blocks(s: Shape) -> Vec<(i32, i32)> {
    let (w, h) = (s.cols, s.rows);
    let mut out: Vec<(i32, i32)> = Vec::new();
    for j in 0..h {
        for i in 0..w {
            if i == 0 || j == 0 || i == w - 1 || j == h - 1 {
                out.push((i, j));
            }
        }
    }
    let drop = |out: &mut Vec<(i32, i32)>, b: (i32, i32)| out.retain(|&x| x != b);
    match s.corner {
        Corner::Square => {}
        Corner::Cut => {
            for b in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)] {
                drop(&mut out, b);
            }
        }
        Corner::Arch => {
            for b in [(0, 0), (1, 0), (w - 1, 0), (w - 2, 0), (0, 1), (w - 1, 1)] {
                drop(&mut out, b);
            }
            out.push((1, 1));
            out.push((w - 2, 1));
        }
    }
    out
}

impl Scene {
    pub fn new(seed: u32, look: Look) -> Scene {
        let s = look.shape;
        let set = blocks(s);
        let has = |b: (i32, i32)| set.contains(&b);
        // Ring distance: a breadth-first walk from the bottom-centre block(s).
        let starts: Vec<(i32, i32)> =
            if s.cols % 2 == 0 { vec![(s.cols / 2 - 1, s.rows - 1), (s.cols / 2, s.rows - 1)] } else { vec![((s.cols - 1) / 2, s.rows - 1)] };
        let mut dist = vec![u32::MAX; (s.cols * s.rows) as usize];
        let at = |b: (i32, i32)| (b.1 * s.cols + b.0) as usize;
        let mut q = VecDeque::new();
        for b in starts {
            dist[at(b)] = 0;
            q.push_back(b);
        }
        while let Some(b) = q.pop_front() {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                let n = (b.0 + dx, b.1 + dy);
                if n.0 >= 0 && n.1 >= 0 && n.0 < s.cols && n.1 < s.rows && has(n) && dist[at(n)] == u32::MAX {
                    dist[at(n)] = dist[at(b)] + 1;
                    q.push_back(n);
                }
            }
        }
        let far = set.iter().map(|&b| dist[at(b)]).max().unwrap_or(1).max(1) as f32;
        let (gc, gr) = (s.cols * 2, s.rows * 2);

        // Interior tiles: everything a flood from outside the grid cannot reach.
        let mut frame = vec![false; (gc * gr) as usize];
        for &(i, j) in &set {
            for (a, b) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                frame[((j * 2 + b) * gc + i * 2 + a) as usize] = true;
            }
        }
        let mut outside = vec![false; (gc * gr) as usize];
        let mut q = VecDeque::new();
        for c in 0..gc {
            for r in 0..gr {
                if (c == 0 || r == 0 || c == gc - 1 || r == gr - 1) && !frame[(r * gc + c) as usize] {
                    outside[(r * gc + c) as usize] = true;
                    q.push_back((c, r));
                }
            }
        }
        while let Some((c, r)) = q.pop_front() {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let (nc, nr) = (c + dx, r + dy);
                if nc >= 0 && nr >= 0 && nc < gc && nr < gr {
                    let k = (nr * gc + nc) as usize;
                    if !frame[k] && !outside[k] {
                        outside[k] = true;
                        q.push_back((nc, nr));
                    }
                }
            }
        }
        let interior: Vec<(i32, i32)> =
            (0..gr).flat_map(|r| (0..gc).map(move |c| (c, r))).filter(|&(c, r)| !frame[(r * gc + c) as usize] && !outside[(r * gc + c) as usize]).collect();
        let inside = |c: i32, r: i32| interior.contains(&(c, r));

        let mut marks = Vec::with_capacity(set.len() * 4);
        for &(i, j) in &set {
            let d = dist[at((i, j))] as f32 * 11.0 / far;
            for (a, b) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                let (c, r) = (i * 2 + a, j * 2 + b);
                // The tile nearer the centre line goes first, mirrored on each
                // side; an odd-width frame's centre block starts both at once.
                let centre = s.cols % 2 == 1 && i == (s.cols - 1) / 2;
                let ax = if centre { 0 } else if c < gc / 2 { (c % 2 == 0) as i32 } else { (c % 2 == 1) as i32 };
                let cx = c as f32 + 0.5 - gc as f32 / 2.0;
                let cy = r as f32 + 0.5 - gr as f32 / 2.0;
                let ang = cx.atan2(cy).rem_euclid(TAU) / TAU;
                let k = marks.len() as u32;
                marks.push(Mark {
                    c,
                    r,
                    tone: (hash(seed, k) * 4.0) as usize,
                    d,
                    pos: ang * 24.0,
                    start: START + d / 11.0 * CLIMB + (ax + b) as f32 * SUB,
                    inner: [(1, 0), (-1, 0), (0, 1), (0, -1)].iter().any(|&(dx, dy)| inside(c + dx, r + dy)),
                });
            }
        }
        let stars = (0..40)
            .map(|k| Star { a: hash(seed ^ 0x51, k) * TAU, d: hash(seed ^ 0x52, k), s: 0.3 + hash(seed ^ 0x53, k) * 0.5 })
            .collect();
        let tones = TONES.map(|t| mix(t, look.theme.ramp[1], 0.14));
        Scene { look, gc, gr, marks, interior, stars, tones }
    }

    /// Draw this portal into `out`, dimmed toward the void by `dim`; returns
    /// its haptic events.
    pub fn frame(&self, inp: &Input, lay: &Layout, dim: f32, out: &mut Vec<Tile>) -> u32 {
        let th = self.look.theme;
        let (t, prev, stage, opened) = if inp.reduce {
            (FORM + 30.0, FORM + 30.0, Stage::Open, 0.0)
        } else if inp.returning {
            (inp.t + FORM, inp.prev + FORM, inp.stage, inp.opened_at + FORM)
        } else {
            (inp.t, inp.prev, inp.stage, inp.opened_at)
        };
        let fresh = !inp.reduce && !inp.returning;
        let events = if fresh && prev < MEET && MEET <= t { TICK } else { 0 };
        let standing = t > FORM;
        let shade = |c: u32| if dim > 0.0 { mix(c, VOID, dim) } else { c };
        if standing {
            self.interior(t, stage, opened, lay, dim, out);
        }
        for (i, m) in self.marks.iter().enumerate() {
            let k = t - m.start;
            if k < 0.0 {
                continue;
            }
            let (flips, last) = flips(i as u32, t);
            let tone = (m.tone + flips as usize) % 4;
            let base = self.tones[if m.inner { tone.saturating_sub(1) } else { tone }];
            if k < POP {
                let u = k / POP;
                let size = 0.3 + 0.7 * back((u / 0.55).min(1.0));
                let col = if u < 0.3 { mix(CORE, th.accent, smooth(u / 0.3)) } else { mix(th.accent, base, smooth((u - 0.3) / 0.7)) };
                push(out, lay, m.c, m.r, size, shade(col), true);
                continue;
            }
            // A short, eased shrink when a tile flips tone.
            let since = (t - last) / 0.16;
            let size = if (0.0..1.0).contains(&since) { 1.0 - 0.38 * (since * PI).sin() } else { 1.0 };
            let mut col = base;
            if standing {
                match stage {
                    Stage::Connecting => {
                        let ph = (t * 6.0).rem_euclid(24.0);
                        let dd = (m.pos - ph).abs();
                        let dd = dd.min(24.0 - dd);
                        if dd < 2.5 {
                            col = mix(base, th.accent, smooth(1.0 - dd / 2.5) * 0.55);
                        }
                    }
                    Stage::Open => {
                        let w = (t - opened) * 16.0 - m.d;
                        if w > 0.0 && w < 3.0 {
                            col = mix(base, th.accent, smooth(1.0 - w / 3.0));
                        } else if w >= 3.0 {
                            col = mix(base, th.ramp[1], 0.18);
                        }
                    }
                    Stage::Rest => {}
                }
            }
            push(out, lay, m.c, m.r, size, shade(col), true);
        }
        events
    }

    fn interior(&self, t: f32, stage: Stage, opened: f32, lay: &Layout, dim: f32, out: &mut Vec<Tile>) {
        let th = self.look.theme;
        let reach = (t - FORM) * 260.0;
        let k = if stage == Stage::Open { ((t - opened) / 0.7).clamp(0.0, 1.0) } else { 0.0 };
        let tq = (t * 12.0).floor() / 12.0;
        let (hx, hy) = (self.gc as f32 * 7.0, self.gr as f32 * 7.0);
        for &(c, r) in &self.interior {
            let mx = (c * 14) as f32 + 5.5 - hx;
            let my = ((r * 14) as f32 + 5.5 - hy) * 0.8;
            let rr = mx.hypot(my);
            if rr > reach {
                continue;
            }
            // At rest the motif breathes quietly; connecting shows warp stars;
            // opening dissolves the stars into the full motif.
            let gate = ((c * 7 + r * 13) % 16) as f32 / 16.0;
            let v = if stage == Stage::Rest {
                Some(self.motif(c, r, mx, my, rr, t) * 0.7)
            } else if gate < k {
                Some(self.motif(c, r, mx, my, rr, t))
            } else {
                None
            };
            let (lv, size) = match v {
                Some(v) => ((v * 5.2 - 0.4).floor() as i32, 0.4 + v * 0.55),
                None => {
                    let mut lv = 0;
                    for s in &self.stars {
                        let d = (s.d + tq * s.s).fract();
                        let sr = d * d * 120.0;
                        if (s.a.cos() * sr - mx).abs() < 7.0 && (s.a.sin() * sr - my * 1.25).abs() < 7.0 {
                            lv = lv.max(1 + (d * 4.0) as i32);
                        }
                    }
                    (lv, 0.55 + lv.min(4) as f32 * 0.1)
                }
            };
            if lv > 0 {
                let col = th.ramp[lv.min(4) as usize];
                push(out, lay, c, r, size.min(1.0), if dim > 0.0 { mix(col, VOID, dim) } else { col }, false);
            }
        }
    }

    /// The portal's interior pattern at one tile, 0 to 1.
    fn motif(&self, c: i32, r: i32, mx: f32, my: f32, rr: f32, t: f32) -> f32 {
        let a = my.atan2(mx);
        let v = match self.look.motif {
            Motif::Swirl => 0.5 + 0.5 * (a * 2.0 + rr * 0.045 - t * 2.4).sin(),
            Motif::Ripple => 0.5 + 0.5 * (rr * 0.085 - t * 3.0).sin(),
            Motif::Bloom => {
                let petals = 0.5 + 0.5 * (a * 5.0 - t * 0.9).sin();
                petals * (0.55 + 0.45 * (rr * 0.05 - t * 1.4).cos())
            }
            Motif::Rain => {
                let lane = hash(c as u32, 7);
                let fall = (r as f32 / self.gr as f32 - t * (0.5 + lane * 0.5) - lane).rem_euclid(1.0);
                (1.0 - fall * 2.4).max(0.0)
            }
            Motif::Lattice => 0.5 + 0.5 * ((c + r) as f32 * 1.1 - t * 2.6).sin() * ((c - r) as f32 * 1.1 + t * 1.7).sin(),
            Motif::Aurora => 0.5 + 0.5 * (r as f32 * 0.7 + (c as f32 * 0.55 + t).sin() * 1.6 - t * 1.4).sin(),
        };
        v.clamp(0.0, 1.0)
    }
}

/// How many times tile `i` has flipped tone by `t`, and when it last did.
fn flips(i: u32, t: f32) -> (u32, f32) {
    let s = t - FORM - FLIP_AFTER;
    if s < 0.0 {
        return (0, -9.0);
    }
    let n = (s / SLOT).floor() as u32;
    let at = |k: u32| FORM + FLIP_AFTER + k as f32 * SLOT + hash(i, k + 1) * SLOT;
    if at(n) <= t {
        (n + 1, at(n))
    } else if n > 0 {
        (n, at(n - 1))
    } else {
        (0, -9.0)
    }
}

fn push(out: &mut Vec<Tile>, lay: &Layout, c: i32, r: i32, frac: f32, rgb: u32, frame: bool) {
    let size = ((frac * lay.tile as f32).round() as i32).max(1);
    let o = ((lay.tile - size) as f32 / 2.0).round() as i32;
    out.push(Tile { c, r, x: lay.ox + c * lay.pitch + o, y: lay.oy + r * lay.pitch + o, size, rgb, frame });
}

/// Room left round the biggest frame, in tiles, for LAR and his flock to fly:
/// three tiles each side, two above, five below where he lands.
const AIR: (i32, i32, i32) = (3, 2, 5);

/// One tile pitch for every portal, so their shapes compare at true size:
/// the largest that still fits the biggest frame plus its air.
fn shared(scenes: &[Scene], w: u32, h: u32) -> Layout {
    let (gc, gr) = (scenes.iter().map(|s| s.gc).max().unwrap_or(12), scenes.iter().map(|s| s.gr).max().unwrap_or(16));
    layout(w, h, gc + 2 * AIR.0 - 2, gr + AIR.1 + AIR.2 - 2)
}

/// Where portal `s` sits, `off` device px along the carousel: centred across,
/// and lifted so the air below it is wider than above.
fn place(s: &Scene, base: &Layout, w: u32, h: u32, off: i32) -> Layout {
    let lift = (AIR.2 - AIR.1) * base.pitch / 2;
    Layout {
        pitch: base.pitch,
        tile: base.tile,
        ox: (w as i32 - s.gc * base.pitch + (base.pitch - base.tile)) / 2 + off,
        oy: (h as i32 - s.gr * base.pitch + (base.pitch - base.tile)) / 2 - lift,
    }
}

/// Each portal's centre along the carousel, in tiles: neighbours sit three
/// tiles apart edge to edge, whatever their widths.
fn centres(scenes: &[Scene]) -> Vec<f32> {
    let mut at = 0.0;
    let mut out = Vec::with_capacity(scenes.len());
    for (i, s) in scenes.iter().enumerate() {
        if i > 0 {
            at += (scenes[i - 1].gc + s.gc) as f32 / 2.0 + 3.0;
        }
        out.push(at);
    }
    out
}

/// Device px a swipe must travel per portal, on average.
pub fn gap(scenes: &[Scene], w: u32, h: u32) -> f32 {
    let c = centres(scenes);
    if c.len() < 2 {
        return w as f32;
    }
    (c[c.len() - 1] - c[0]) / (c.len() - 1) as f32 * shared(scenes, w, h).pitch as f32
}

/// The frame box of the portal nearest `pos`, in device px, where it is drawn
/// right now: `[x, y, w, h]`. LAR and the flock steer round it.
pub fn rect(scenes: &[Scene], pos: f32, w: u32, h: u32) -> [i32; 4] {
    if scenes.is_empty() {
        return [0; 4];
    }
    let n = scenes.len();
    let pos = pos.clamp(0.0, (n - 1) as f32);
    let sel = pos.round() as usize;
    let base = shared(scenes, w, h);
    let c = centres(scenes);
    let (lo, hi) = (pos.floor() as usize, pos.ceil() as usize);
    let here = c[lo] + (c[hi] - c[lo]) * (pos - lo as f32);
    let s = &scenes[sel];
    let off = ((c[sel] - here) * base.pitch as f32).round() as i32;
    let lay = place(s, &base, w, h, off);
    [lay.ox, lay.oy, (s.gc - 1) * base.pitch + base.tile, (s.gr - 1) * base.pitch + base.tile]
}

/// The carousel (spec 010 C13): the portal at `pos` centred, its neighbours
/// beside it, dimmed by distance. Fractional `pos` is a swipe in progress.
/// Only the selected portal follows the stage; the others rest.
pub fn carousel(scenes: &[Scene], pos: f32, inp: &Input, w: u32, h: u32, out: &mut Vec<Tile>) -> u32 {
    out.clear();
    if scenes.is_empty() {
        return 0;
    }
    let n = scenes.len() as i32;
    let pos = pos.clamp(0.0, (n - 1) as f32);
    let sel = pos.round() as i32;
    let base = shared(scenes, w, h);
    let c = centres(scenes);
    let (lo, hi) = (pos.floor() as usize, pos.ceil() as usize);
    let here = c[lo] + (c[hi] - c[lo]) * (pos - lo as f32);
    let mut events = 0;
    for (p, s) in scenes.iter().enumerate() {
        let off = ((c[p] - here) * base.pitch as f32).round() as i32;
        let half = s.gc * base.pitch / 2;
        if off - half >= w as i32 / 2 + base.pitch || off + half <= -(w as i32) / 2 - base.pitch {
            continue;
        }
        let lay = place(s, &base, w, h, off);
        let dim = smooth((p as f32 - pos).abs()) * 0.68;
        let mine = if p as i32 == sel { *inp } else { Input { stage: Stage::Rest, ..*inp } };
        let ev = s.frame(&mine, &lay, dim, out);
        if p as i32 == sel {
            events = ev;
        }
    }
    events
}

#[cfg(test)]
mod tests {
    use super::*;

    const SIS: Look = Look {
        shape: Shape { cols: 6, rows: 8, corner: Corner::Square },
        motif: Motif::Swirl,
        theme: Theme { ramp: [0x3b1220, 0x7a1c2c, 0xb5412a, 0xe08a35, 0xf3cf6a], accent: 0xe8b04a },
    };
    const LAY: Layout = Layout { pitch: 14, tile: 11, ox: 0, oy: 0 };
    const SHAPES: [Shape; 6] = [
        Shape { cols: 6, rows: 8, corner: Corner::Square },
        Shape { cols: 7, rows: 7, corner: Corner::Cut },
        Shape { cols: 6, rows: 9, corner: Corner::Arch },
        Shape { cols: 8, rows: 7, corner: Corner::Square },
        Shape { cols: 5, rows: 9, corner: Corner::Square },
        Shape { cols: 7, rows: 8, corner: Corner::Cut },
    ];
    const MOTIFS: [Motif; 6] = [Motif::Swirl, Motif::Ripple, Motif::Bloom, Motif::Rain, Motif::Lattice, Motif::Aurora];

    fn at(t: f32, stage: Stage) -> Input {
        Input { t, prev: t - 1.0 / 60.0, stage, opened_at: 0.0, returning: false, reduce: false }
    }

    fn draw_look(look: Look, inp: Input) -> (Vec<Tile>, u32) {
        let mut out = Vec::new();
        let ev = Scene::new(5, look).frame(&inp, &LAY, 0.0, &mut out);
        (out, ev)
    }

    fn draw(inp: Input) -> (Vec<Tile>, u32) {
        draw_look(SIS, inp)
    }

    fn frame_tiles(inp: Input) -> Vec<Tile> {
        draw(inp).0.into_iter().filter(|t| t.frame).collect()
    }

    fn sis_tones() -> [u32; 4] {
        Scene::new(5, SIS).tones
    }

    #[test]
    fn c1_c2_frame_is_24_blocks_of_2x2_on_a_12x16_grid() {
        let tiles = frame_tiles(at(1.5, Stage::Rest));
        assert_eq!(tiles.len(), 96);
        assert!(tiles.iter().all(|t| (0..12).contains(&t.c) && (0..16).contains(&t.r)));
        assert!(tiles.iter().all(|t| t.c < 2 || t.c >= 10 || t.r < 2 || t.r >= 14));
        assert!(tiles.iter().all(|t| t.size == 11));
    }

    #[test]
    fn c3_flat_tones_with_a_breath_of_the_theme_and_a_darker_inner_edge() {
        let tones = sis_tones();
        assert!(tones.iter().zip(TONES).all(|(a, b)| a != &b), "tinted toward the portal");
        let tiles = frame_tiles(at(1.5, Stage::Rest));
        assert!(tiles.iter().all(|t| tones.contains(&t.rgb)));
        // The tiles that touch the opening (columns 2 to 9, rows 2 to 13).
        let inner = |t: &Tile| ((t.c == 1 || t.c == 10) && (2..14).contains(&t.r)) || ((t.r == 1 || t.r == 14) && (2..10).contains(&t.c));
        assert!(tiles.iter().filter(|t| inner(t)).all(|t| t.rgb != tones[3]));
    }

    #[test]
    fn c4_builds_from_the_bottom_centre_up_both_sides_for_every_shape() {
        for s in SHAPES {
            let look = Look { shape: s, ..SIS };
            let gc = s.cols * 2;
            let tiles = |t: f32| draw_look(look, at(t, Stage::Rest)).0.into_iter().filter(|x| x.frame).collect::<Vec<_>>();
            let first = tiles(START + 0.005);
            assert!(!first.is_empty() && first.iter().all(|t| t.r >= s.rows * 2 - 2), "{s:?}");
            for k in 0..40 {
                let set: Vec<(i32, i32)> = tiles(START + k as f32 / 60.0).iter().map(|t| (t.c, t.r)).collect();
                assert!(set.iter().all(|&(c, r)| set.contains(&(gc - 1 - c, r))), "{s:?} frame {k} is lopsided");
            }
            assert!(tiles(MEET - 0.04).len() < tiles(FORM + 0.01).len(), "{s:?}");
        }
    }

    #[test]
    fn c5_each_tile_grows_from_a_light_core_through_the_accent_into_its_tone() {
        let pick = |t: f32| frame_tiles(at(t, Stage::Rest)).into_iter().find(|x| x.c == 6 && x.r == 15).unwrap();
        let early = pick(0.17 + 0.004);
        assert!(early.size < 6, "starts small");
        assert!(!sis_tones().contains(&early.rgb), "starts light, not in its tone");
        assert_eq!(pick(0.17 + 0.3 * POP).rgb, SIS.theme.accent);
        // It overshoots a touch, never past the gap.
        let sizes: Vec<i32> = (0..40).map(|k| pick(0.17 + k as f32 * POP / 40.0).size).collect();
        assert!(sizes.windows(2).take(18).all(|w| w[1] >= w[0]), "grows without stepping back");
        assert!(sizes.iter().all(|&s| s <= 12));
        let done = pick(0.17 + POP + 0.01);
        assert!(sis_tones().contains(&done.rgb) && done.size == 11);
    }

    #[test]
    fn c6_the_build_takes_about_six_tenths_of_a_second_for_every_shape() {
        const { assert!(FORM - START < 0.8 && FORM - START > 0.5) };
        const { assert!(FORM <= 0.9, "landing.ts FORM must cover the build") };
        for s in SHAPES {
            let look = Look { shape: s, ..SIS };
            let n = draw_look(look, at(FORM + 0.01, Stage::Rest)).0.iter().filter(|t| t.frame).count();
            assert_eq!(n, blocks(s).len() * 4, "{s:?}");
        }
    }

    #[test]
    fn c7_one_tick_when_the_sides_meet() {
        let ticks: Vec<f32> = (1..120).map(|n| n as f32 / 60.0).filter(|&t| draw(at(t, Stage::Rest)).1 == TICK).collect();
        assert_eq!(ticks.len(), 1);
        assert!((ticks[0] - MEET).abs() < 1.0 / 60.0);
    }

    #[test]
    fn c8_a_returning_student_sees_the_frame_standing() {
        let inp = Input { returning: true, ..at(0.0, Stage::Open) };
        assert_eq!(frame_tiles(inp).len(), 96);
        let ev = (0..60).map(|n| draw(Input { returning: true, ..at(n as f32 / 60.0, Stage::Open) }).1).sum::<u32>();
        assert_eq!(ev, 0);
    }

    #[test]
    fn c9_at_rest_a_few_tiles_flip_with_a_short_eased_shrink() {
        let tones = sis_tones();
        let start = frame_tiles(at(FORM + 1.0, Stage::Rest));
        let later = frame_tiles(at(FORM + 20.0, Stage::Rest));
        assert!(start.iter().zip(&later).filter(|(a, b)| a.rgb != b.rgb).count() > 20);
        for n in 0..300 {
            let shrunk = frame_tiles(at(FORM + 3.0 + n as f32 / 30.0, Stage::Rest)).iter().filter(|t| t.size < 11).count();
            assert!(shrunk <= 14, "too many flipping at once: {shrunk}");
        }
        assert!(start.iter().all(|t| tones.contains(&t.rgb)));
    }

    #[test]
    fn c10_a_pulse_travels_while_connecting() {
        let tones = sis_tones();
        let lit = |t: f32| -> Vec<(i32, i32)> { frame_tiles(at(t, Stage::Connecting)).iter().filter(|x| !tones.contains(&x.rgb)).map(|x| (x.c, x.r)).collect() };
        assert!(!lit(FORM + 0.5).is_empty());
        assert_ne!(lit(FORM + 0.5), lit(FORM + 1.0));
        assert!(frame_tiles(at(FORM + 0.5, Stage::Rest)).iter().all(|x| tones.contains(&x.rgb)));
    }

    #[test]
    fn c11_opening_runs_a_wave_up_then_settles_into_a_tint() {
        let tones = sis_tones();
        let open = |t: f32| frame_tiles(Input { opened_at: 2.0, ..at(t, Stage::Open) });
        let near = |c: i32, r: i32, ts: &[Tile]| ts.iter().find(|x| x.c == c && x.r == r).unwrap().rgb;
        let early = open(2.1);
        let rest = frame_tiles(at(2.1, Stage::Rest));
        assert_ne!(near(6, 15, &early), near(6, 15, &rest), "bottom centre lights first");
        assert_eq!(near(6, 0, &early), near(6, 0, &rest), "the top has not lit yet");
        assert!(open(5.0).iter().all(|x| !tones.contains(&x.rgb) && x.rgb != SIS.theme.accent));
    }

    #[test]
    fn c12_stars_while_connecting_then_the_motif_once_open() {
        let inside = |inp: Input| draw(inp).0.into_iter().filter(|t| !t.frame).collect::<Vec<_>>();
        let stars = inside(at(FORM + 2.0, Stage::Connecting));
        let open = inside(Input { opened_at: FORM + 1.0, ..at(FORM + 2.0, Stage::Open) });
        assert!(!stars.is_empty());
        assert!(open.len() > stars.len() * 2, "{} open vs {} stars", open.len(), stars.len());
        assert!(stars.iter().chain(&open).all(|t| SIS.theme.ramp.contains(&t.rgb)));
        assert!(inside(at(0.5, Stage::Connecting)).is_empty());
    }

    #[test]
    fn at_rest_the_motif_breathes_quietly() {
        let rest: Vec<Tile> = draw(at(FORM + 2.0, Stage::Rest)).0.into_iter().filter(|t| !t.frame).collect();
        assert!(!rest.is_empty());
        assert!(rest.iter().all(|t| SIS.theme.ramp[1..=3].contains(&t.rgb)), "rest never reaches the brightest tone");
    }

    #[test]
    fn every_shape_has_a_closed_symmetric_one_block_frame_and_an_interior() {
        for s in SHAPES {
            let b = blocks(s);
            assert!(b.iter().all(|&(i, j)| b.contains(&(s.cols - 1 - i, j))), "{s:?} mirror");
            let sc = Scene::new(1, Look { shape: s, ..SIS });
            assert!(sc.interior.len() > 8, "{s:?} interior");
            assert!(sc.interior.iter().all(|&(c, r)| c > 0 && r > 0 && c < sc.gc - 1 && r < sc.gr - 1), "{s:?}");
            assert!(sc.gc <= 16 && sc.gr <= 18, "{s:?} fits");
        }
    }

    #[test]
    fn every_motif_stays_in_its_ramp_and_moves() {
        for m in MOTIFS {
            let look = Look { motif: m, ..SIS };
            let open = |t: f32| draw_look(look, Input { opened_at: FORM, ..at(t, Stage::Open) }).0.into_iter().filter(|t| !t.frame).collect::<Vec<_>>();
            let a = open(FORM + 3.0);
            assert!(!a.is_empty(), "{m:?}");
            assert!(a.iter().all(|t| SIS.theme.ramp.contains(&t.rgb)), "{m:?}");
            assert_ne!(a, open(FORM + 3.5), "{m:?} is still");
        }
    }

    #[test]
    fn reduce_motion_holds_one_still_open_frame() {
        let still = |t: f32| draw(Input { reduce: true, ..at(t, Stage::Rest) });
        assert_eq!(still(0.0), still(9.0));
        assert_eq!(still(0.0).1, 0);
        assert!(still(0.0).0.iter().any(|t| !t.frame));
    }

    #[test]
    fn c25_same_input_same_tiles() {
        assert_eq!(draw(at(3.3, Stage::Connecting)), draw(at(3.3, Stage::Connecting)));
    }

    #[test]
    fn c13_the_carousel_centres_the_selected_portal_and_dims_its_neighbours() {
        let scenes: Vec<Scene> = SHAPES.iter().zip(MOTIFS).map(|(&shape, motif)| Scene::new(5, Look { shape, motif, ..SIS })).collect();
        let inp = at(FORM + 2.0, Stage::Rest);
        let mut out = Vec::new();
        // A phone's portal area: wider than tall.
        let (w, h) = (1110, 820);
        carousel(&scenes, 1.0, &inp, w, h, &mut out);
        let pitch = shared(&scenes, w, h).pitch;
        let [x, _, rw, _] = rect(&scenes, 1.0, w, h);
        let (l, r) = (x, x + rw);
        let mid: Vec<&Tile> = out.iter().filter(|t| t.frame && t.x >= l && t.x < r).collect();
        assert!(mid.iter().any(|t| scenes[1].tones.contains(&t.rgb)), "the selected portal is undimmed");
        let sides: Vec<&Tile> = out.iter().filter(|t| t.frame && (t.x < l - pitch || t.x >= r + pitch)).collect();
        assert!(!sides.is_empty(), "a neighbour peeks in");
        assert!(sides.iter().all(|t| !scenes[0].tones.contains(&t.rgb) && !scenes[2].tones.contains(&t.rgb)), "neighbours are dimmed");
        // Neighbours keep a clear gap from the selected portal.
        assert!(out.iter().filter(|t| t.frame && !(t.x >= l && t.x < r)).all(|t| t.x + t.size <= l - pitch || t.x >= r + pitch));
        assert!(gap(&scenes, w, h) > 0.0);
        out.clear();
        carousel(&scenes, 0.5, &inp, w, h, &mut out);
        assert!(!out.is_empty());
    }

    #[test]
    fn the_portal_leaves_air_round_it_for_lar_most_of_all_below() {
        let scenes: Vec<Scene> = SHAPES.iter().zip(MOTIFS).map(|(&shape, motif)| Scene::new(5, Look { shape, motif, ..SIS })).collect();
        for (w, h) in [(1110, 820), (1110, 1300), (900, 600)] {
            for sel in 0..scenes.len() {
                let [x, y, rw, rh] = rect(&scenes, sel as f32, w, h);
                let pitch = shared(&scenes, w, h).pitch;
                assert!(x >= 2 * pitch && x + rw <= w as i32 - 2 * pitch, "{w}x{h} #{sel} sides");
                assert!(y >= pitch && h as i32 - (y + rh) >= 4 * pitch, "{w}x{h} #{sel} below");
            }
        }
    }

    #[test]
    fn rect_bounds_every_frame_tile_of_the_selected_portal() {
        let scenes: Vec<Scene> = SHAPES.iter().zip(MOTIFS).map(|(&shape, motif)| Scene::new(5, Look { shape, motif, ..SIS })).collect();
        let (w, h) = (1110, 820);
        for sel in 0..scenes.len() {
            let mut out = Vec::new();
            carousel(&scenes, sel as f32, &at(FORM + 1.0, Stage::Rest), w, h, &mut out);
            let [x, y, rw, rh] = rect(&scenes, sel as f32, w, h);
            let mine: Vec<&Tile> = out.iter().filter(|t| t.frame && t.x >= x - 2 && t.x < x + rw + 2).collect();
            assert!(!mine.is_empty());
            assert!(mine.iter().all(|t| t.x >= x && t.y >= y && t.x + t.size <= x + rw && t.y + t.size <= y + rh), "portal {sel}");
        }
    }

    #[test]
    fn layout_fits_every_aspect_ratio_crisp_and_centred() {
        for (gc, gr) in [(12, 16), (16, 14), (10, 18)] {
            for (w, h) in [(390, 300), (430, 520), (320, 220), (1179, 1400), (1290, 900), (750, 1600)] {
                let l = layout(w, h, gc, gr);
                assert!(l.pitch >= 1 && l.tile >= 1 && l.tile <= l.pitch);
                let gw = (gc - 1) * l.pitch + l.tile;
                let gh = (gr - 1) * l.pitch + l.tile;
                assert!(l.ox >= 0 && l.oy >= 0 && l.ox + gw <= w as i32 && l.oy + gh <= h as i32, "{w}x{h}: {l:?}");
                assert!((w as i32 - gw - 2 * l.ox).abs() <= 1 && (h as i32 - gh - 2 * l.oy).abs() <= 1);
            }
        }
        assert_eq!(layout(14 * 14, 18 * 14, 12, 16), Layout { pitch: 14, tile: 11, ox: 15, oy: 15 });
    }
}
