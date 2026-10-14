//! The tile portal as a pure function of time and state (spec 010 C25), ported
//! from the portal-v8 prototype. A 6 by 8 block frame, one block thick, each
//! block 2 by 2 tiles, on a black void; warp stars or a swirl inside.
//!
//! Everything is laid out in "base units", the prototype's 14 px pitch and
//! 11 px tile, then scaled to whole device pixels by [`layout`].

use std::f32::consts::TAU;

pub const COLS: i32 = 12;
pub const ROWS: i32 = 16;
/// The frame's four obsidian tones, darkest first.
pub const TONES: [u32; 4] = [0x1a1622, 0x241f2e, 0x2f2939, 0x3c3548];
/// The light core a tile shows on its first frame.
pub const CORE: u32 = 0xece7dc;

const FPS: f32 = 30.0;
/// When the bottom-centre tiles appear, and the delay per block of ring distance.
const START: f32 = 0.15;
const STEP: f32 = 0.045;
/// A tile's delay inside its block, per step right or down.
const SUB: f32 = 0.02;
/// Ring distance from the bottom-centre blocks to the top-centre ones.
const FAR: u32 = 11;
/// The two sides meet at the top: one haptic tick (C7).
pub const MEET: f32 = START + FAR as f32 * STEP;
/// The frame is standing: the last tile has finished its pop (C6).
pub const FORM: f32 = MEET + 2.0 * SUB + 0.1;
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

/// A portal's look: five ramp tones and one accent, as 0xRRGGBB (spec 012 C7).
#[derive(Clone, Copy, Debug)]
pub struct Theme {
    pub ramp: [u32; 5],
    pub accent: u32,
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

/// Fit the 12 by 16 grid, with a tile of margin all round, into any canvas,
/// so every phone's aspect ratio gets the largest crisp portal that fits.
pub fn layout(w: u32, h: u32) -> Layout {
    let pitch = (w / (COLS as u32 + 2)).min(h / (ROWS as u32 + 2)).max(1) as i32;
    let tile = ((pitch * 11 + 7) / 14).max(1);
    Layout {
        pitch,
        tile,
        ox: (w as i32 - COLS * pitch + (pitch - tile)) / 2,
        oy: (h as i32 - ROWS * pitch + (pitch - tile)) / 2,
    }
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
    /// Ring distance in blocks from the bottom centre.
    d: u32,
    /// Ring position from the bottom centre, for the connecting pulse.
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
    marks: Vec<Mark>,
    stars: Vec<Star>,
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

/// The 24 frame blocks clockwise from the top-left.
fn ring() -> Vec<(i32, i32)> {
    let mut r = Vec::with_capacity(24);
    r.extend((0..6).map(|x| (x, 0)));
    r.extend((1..8).map(|y| (5, y)));
    r.extend((0..5).rev().map(|x| (x, 7)));
    r.extend((1..7).rev().map(|y| (0, y)));
    r
}

fn mix(a: u32, b: u32, k: f32) -> u32 {
    let ch = |v: u32, s: u32| ((v >> s) & 0xff) as f32;
    [16, 8, 0].iter().fold(0, |acc, &s| {
        let v = ch(a, s) + (ch(b, s) - ch(a, s)) * k;
        acc | ((v.round().clamp(0.0, 255.0) as u32) << s)
    })
}

fn steps(t: f32, fps: f32) -> f32 {
    (t * fps).floor() / fps
}

impl Scene {
    pub fn new(seed: u32) -> Scene {
        let ring = ring();
        let dist = |a: usize, b: usize| {
            let d = a.abs_diff(b);
            d.min(24 - d)
        };
        // Blocks (3, 7) and (2, 7) are the bottom centre; both start at once.
        let (b0, b1) = (14, 15);
        let mut marks = Vec::with_capacity(96);
        for (n, &(i, j)) in ring.iter().enumerate() {
            let d = dist(n, b0).min(dist(n, b1)) as u32;
            for (a, b) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                let k = marks.len() as u32;
                // Mirror the in-block delay on the left half so both sides match.
                let ax = if i < 3 { 1 - a } else { a };
                marks.push(Mark {
                    c: i * 2 + a,
                    r: j * 2 + b,
                    tone: (hash(seed, k) * 4.0) as usize,
                    d,
                    pos: ((n + 24 - b0) % 24) as f32,
                    start: START + d as f32 * STEP + (ax + b) as f32 * SUB,
                    inner: (a == 1 && i == 0) || (a == 0 && i == 5) || (b == 1 && j == 0) || (b == 0 && j == 7),
                });
            }
        }
        let stars = (0..40)
            .map(|k| Star {
                a: hash(seed ^ 0x51, k) * TAU,
                d: hash(seed ^ 0x52, k),
                s: 0.3 + hash(seed ^ 0x53, k) * 0.5,
            })
            .collect();
        Scene { marks, stars }
    }

    /// Draw one frame into `out` and return its haptic events.
    pub fn frame(&self, inp: &Input, th: &Theme, lay: &Layout, out: &mut Vec<Tile>) -> u32 {
        out.clear();
        let (t, prev, stage, opened) = if inp.reduce {
            (FORM + 30.0, FORM + 30.0, Stage::Open, 0.0)
        } else if inp.returning {
            (inp.t + FORM, inp.prev + FORM, inp.stage, inp.opened_at + FORM)
        } else {
            (inp.t, inp.prev, inp.stage, inp.opened_at)
        };
        let tq = steps(t, FPS);
        let fresh = !inp.reduce && !inp.returning;
        let events = if fresh && prev < MEET && MEET <= t { TICK } else { 0 };
        let standing = tq > FORM;
        if standing {
            self.interior(t, stage, opened, th, lay, out);
        }
        for (i, m) in self.marks.iter().enumerate() {
            let k = tq - m.start;
            if k < 0.0 {
                continue;
            }
            if k < 1.0 / FPS {
                push(out, lay, m.c, m.r, 0.45, CORE, true);
                continue;
            }
            if k < 2.0 / FPS {
                push(out, lay, m.c, m.r, 1.0, th.accent, true);
                continue;
            }
            let (flips, last) = flips(i as u32, t);
            let tone = (m.tone + flips as usize) % 4;
            let base = TONES[if m.inner { tone.saturating_sub(1) } else { tone }];
            let since = t - last;
            let size = if (0.0..0.05).contains(&since) {
                0.6
            } else if (0.05..0.1).contains(&since) {
                0.85
            } else {
                1.0
            };
            let mut col = base;
            if standing {
                match stage {
                    Stage::Connecting => {
                        let ph = (t * 6.0).rem_euclid(24.0);
                        let dd = (m.pos - ph).abs();
                        let dd = dd.min(24.0 - dd);
                        if dd < 2.5 {
                            col = mix(base, th.accent, (1.0 - dd / 2.5) * 0.55);
                        }
                    }
                    Stage::Open => {
                        let w = (t - opened) * 16.0 - m.d as f32;
                        if w > 0.0 && w < 3.0 {
                            col = mix(base, th.accent, 1.0 - w / 3.0);
                        } else if w >= 3.0 {
                            col = mix(base, th.ramp[1], 0.18);
                        }
                    }
                    Stage::Rest => {}
                }
            }
            push(out, lay, m.c, m.r, size, col, true);
        }
        events
    }

    fn interior(&self, t: f32, stage: Stage, opened: f32, th: &Theme, lay: &Layout, out: &mut Vec<Tile>) {
        let reach = (t - FORM) * 260.0;
        let k = if stage == Stage::Open { ((t - opened) / 0.7).clamp(0.0, 1.0) } else { 0.0 };
        let tq = steps(t, 12.0);
        for r in 2..14 {
            for c in 2..10 {
                let mx = (c * 14) as f32 + 5.5 - 84.0;
                let my = ((r * 14) as f32 + 5.5 - 112.0) * 0.8;
                let rr = mx.hypot(my);
                if rr > reach {
                    continue;
                }
                // The dither dissolve: each tile turns to swirl at its own threshold.
                let gate = ((c * 7 + r * 13) % 16) as f32 / 16.0;
                let mut lv = 0;
                if gate < k {
                    let v = 0.5 + 0.5 * (my.atan2(mx) * 2.0 + rr * 0.045 - t * 2.4).sin();
                    lv = (v * 5.2 - 0.4).floor() as i32;
                } else {
                    for s in &self.stars {
                        let d = (s.d + tq * s.s).fract();
                        let sr = d * d * 120.0;
                        if (s.a.cos() * sr - mx).abs() < 7.0 && (s.a.sin() * sr - my * 1.25).abs() < 7.0 {
                            lv = lv.max(1 + (d * 4.0) as i32);
                        }
                    }
                }
                if lv > 0 {
                    let lv = lv.min(4);
                    push(out, lay, c, r, 0.55 + lv as f32 * 0.1, th.ramp[lv as usize], false);
                }
            }
        }
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

#[cfg(test)]
mod tests {
    use super::*;

    const SIS: Theme = Theme { ramp: [0x3b1220, 0x7a1c2c, 0xb5412a, 0xe08a35, 0xf3cf6a], accent: 0xe8b04a };
    const LAY: Layout = Layout { pitch: 14, tile: 11, ox: 0, oy: 0 };

    fn at(t: f32, stage: Stage) -> Input {
        Input { t, prev: t - 1.0 / 30.0, stage, opened_at: 0.0, returning: false, reduce: false }
    }

    fn draw(inp: Input) -> (Vec<Tile>, u32) {
        let mut out = Vec::new();
        let ev = Scene::new(5).frame(&inp, &SIS, &LAY, &mut out);
        (out, ev)
    }

    fn frame_tiles(inp: Input) -> Vec<Tile> {
        draw(inp).0.into_iter().filter(|t| t.frame).collect()
    }

    #[test]
    fn c1_c2_frame_is_24_blocks_of_2x2_on_a_12x16_grid() {
        let tiles = frame_tiles(at(1.5, Stage::Rest));
        assert_eq!(tiles.len(), 96);
        assert!(tiles.iter().all(|t| (0..COLS).contains(&t.c) && (0..ROWS).contains(&t.r)));
        // One block thick: every frame tile is in the outer two rows or columns.
        assert!(tiles.iter().all(|t| t.c < 2 || t.c >= COLS - 2 || t.r < 2 || t.r >= ROWS - 2));
        assert!(tiles.iter().all(|t| t.size == 11));
    }

    #[test]
    fn c3_flat_tones_and_a_darker_inner_edge() {
        let tiles = frame_tiles(at(1.5, Stage::Rest));
        assert!(tiles.iter().all(|t| TONES.contains(&t.rgb)));
        let inner = |t: &Tile| (t.c == 1 && t.r > 0 && t.r < 15) || (t.c == 10 && t.r > 0 && t.r < 15) || (t.r == 1 && t.c > 0 && t.c < 11) || (t.r == 14 && t.c > 0 && t.c < 11);
        assert!(tiles.iter().filter(|t| inner(t)).all(|t| t.rgb != TONES[3]));
    }

    #[test]
    fn c4_builds_from_the_bottom_centre_up_both_sides() {
        let first = frame_tiles(at(5.5 / 30.0, Stage::Rest));
        assert!(!first.is_empty());
        assert!(first.iter().all(|t| t.r >= 14 && (4..8).contains(&t.c)));
        // Mirror image at every step of the build.
        for k in 0..25 {
            let set: Vec<(i32, i32)> = frame_tiles(at(0.15 + k as f32 / 30.0, Stage::Rest)).iter().map(|t| (t.c, t.r)).collect();
            assert!(set.iter().all(|&(c, r)| set.contains(&(COLS - 1 - c, r))), "frame {k} is lopsided");
        }
        // The top centre is the last to appear.
        let late = frame_tiles(at(MEET - 0.04, Stage::Rest));
        assert!(!late.iter().any(|t| t.r < 2 && (4..8).contains(&t.c)));
    }

    #[test]
    fn c5_each_tile_pops_core_then_accent_then_tone() {
        // Tile (6, 15) starts at START + SUB = 0.17: core at frame 6, accent at 7, tone after.
        let pick = |t: f32| frame_tiles(at(t, Stage::Rest)).into_iter().find(|x| x.c == 6 && x.r == 15).unwrap();
        let core = pick(6.5 / 30.0);
        assert_eq!((core.rgb, core.size), (CORE, 5));
        assert_eq!(pick(7.5 / 30.0).rgb, SIS.accent);
        assert!(TONES.contains(&pick(8.5 / 30.0).rgb));
    }

    #[test]
    fn c6_the_build_takes_about_six_tenths_of_a_second() {
        const { assert!(FORM - START < 0.7 && FORM - START > 0.5) };
        const { assert!(FORM <= 0.8, "landing.ts FORM must cover the build") };
        assert_eq!(frame_tiles(at(FORM + 0.04, Stage::Rest)).len(), 96);
    }

    #[test]
    fn c7_one_tick_when_the_sides_meet() {
        let ticks: Vec<f32> = (1..60).map(|n| n as f32 / 30.0).filter(|&t| draw(at(t, Stage::Rest)).1 == TICK).collect();
        assert_eq!(ticks.len(), 1);
        assert!((ticks[0] - MEET).abs() < 1.0 / 30.0);
    }

    #[test]
    fn c8_a_returning_student_sees_the_frame_standing() {
        let inp = Input { returning: true, ..at(0.0, Stage::Open) };
        assert_eq!(frame_tiles(inp).len(), 96);
        let ev = (0..40).map(|n| draw(Input { returning: true, ..at(n as f32 / 30.0, Stage::Open) }).1).sum::<u32>();
        assert_eq!(ev, 0);
    }

    #[test]
    fn c9_at_rest_a_few_tiles_flip_with_a_short_shrink() {
        let start = frame_tiles(at(FORM + 1.0, Stage::Rest));
        let later = frame_tiles(at(FORM + 20.0, Stage::Rest));
        let changed = start.iter().zip(&later).filter(|(a, b)| a.rgb != b.rgb).count();
        assert!(changed > 20, "tones should drift, {changed} changed");
        for n in 0..300 {
            let shrunk = frame_tiles(at(FORM + 3.0 + n as f32 / 30.0, Stage::Rest)).iter().filter(|t| t.size < 11).count();
            assert!(shrunk <= 12, "too many flipping at once: {shrunk}");
        }
    }

    #[test]
    fn c10_a_pulse_travels_while_connecting() {
        let lit = |t: f32| -> Vec<(i32, i32)> {
            frame_tiles(at(t, Stage::Connecting)).iter().filter(|x| !TONES.contains(&x.rgb)).map(|x| (x.c, x.r)).collect()
        };
        let now = lit(FORM + 0.5);
        assert!(!now.is_empty());
        assert_ne!(now, lit(FORM + 1.0));
        assert!(frame_tiles(at(FORM + 0.5, Stage::Rest)).iter().all(|x| TONES.contains(&x.rgb)));
    }

    #[test]
    fn c11_opening_runs_a_wave_up_then_settles_into_a_tint() {
        let open = |t: f32| frame_tiles(Input { opened_at: 2.0, ..at(t, Stage::Open) });
        let early = open(2.1);
        let near = |c: i32, r: i32, ts: &[Tile]| ts.iter().find(|x| x.c == c && x.r == r).unwrap().rgb;
        assert_ne!(near(6, 15, &early), near(6, 15, &frame_tiles(at(2.1, Stage::Rest))), "bottom centre lights first");
        assert_eq!(near(6, 0, &early), near(6, 0, &frame_tiles(at(2.1, Stage::Rest))), "the top has not lit yet");
        let settled = open(5.0);
        assert!(settled.iter().all(|x| !TONES.contains(&x.rgb) && x.rgb != SIS.accent));
    }

    #[test]
    fn c12_stars_while_connecting_then_a_swirl_once_open() {
        let inside = |inp: Input| draw(inp).0.into_iter().filter(|t| !t.frame).collect::<Vec<_>>();
        let stars = inside(at(FORM + 2.0, Stage::Connecting));
        let swirl = inside(Input { opened_at: FORM + 1.0, ..at(FORM + 2.0, Stage::Open) });
        assert!(!stars.is_empty());
        assert!(swirl.len() > stars.len() * 2, "{} swirl vs {} stars", swirl.len(), stars.len());
        assert!(stars.iter().chain(&swirl).all(|t| SIS.ramp.contains(&t.rgb)));
        // Nothing inside before the frame stands.
        assert!(inside(at(0.5, Stage::Connecting)).is_empty());
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
    fn layout_fits_every_aspect_ratio_crisp_and_centred() {
        // Device px: short and wide, tall and narrow, phone portrait areas at 3x.
        for (w, h) in [(390, 300), (430, 520), (320, 220), (1179, 1400), (1290, 900), (750, 1600), (14, 18), (1, 1)] {
            let l = layout(w, h);
            assert!(l.pitch >= 1 && l.tile >= 1 && l.tile <= l.pitch);
            let gw = 11 * l.pitch + l.tile;
            let gh = 15 * l.pitch + l.tile;
            if w >= 14 && h >= 18 {
                assert!(l.ox >= 0 && l.oy >= 0 && l.ox + gw <= w as i32 && l.oy + gh <= h as i32, "{w}x{h}: {l:?}");
                assert!((w as i32 - gw - 2 * l.ox).abs() <= 1 && (h as i32 - gh - 2 * l.oy).abs() <= 1, "{w}x{h} not centred");
            }
        }
        assert_eq!(layout(14 * 14, 18 * 14), Layout { pitch: 14, tile: 11, ox: 14 + 1, oy: 14 + 1 });
    }
}
