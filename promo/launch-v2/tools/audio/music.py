"""Original 150 BPM chiptune / synthwave arrangement for the IntPortal trailer.

20 bars, A minor, Am - F - C - G. Returns separate stereo buses so the mixer can
sidechain and duck them. Everything is derived from the bar grid (bar = 1.6 s)."""
import numpy as np
from dsp import *  # noqa

BPM = 150
BEAT = 60.0 / BPM          # 0.4 s
STEP = BEAT / 4            # 16th note = 0.1 s
BAR = BEAT * 4             # 1.6 s
BARS = 20
TOTAL = BARS * BAR         # 32.0 s
TAIL = 1.5

def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12.0)

# chord per bar (index % 4): Am, F, C, G
CHORDS = [[57, 60, 64], [53, 57, 60], [60, 64, 67], [59, 62, 67]]
ROOTS = [33, 29, 36, 31]     # A1, F1, C2, G1 (midi)

# lead melody, 16 steps per bar, value = midi note, 0 = sustain, None = rest
LEAD_A = [
    [69, 0, 0, 0, 72, 0, 71, 0, 69, 0, 0, 0, 67, 0, 69, 0],
    [65, 0, 0, 0, 69, 0, 0, 0, 72, 0, 0, 0, 69, 0, 65, 0],
    [72, 0, 0, 0, 76, 0, 74, 0, 72, 0, 0, 0, 67, 0, 72, 0],
    [71, 0, 0, 0, 74, 0, 0, 0, 71, 0, 69, 0, 67, 0, 0, 0],
]
LEAD_B = [
    [76, 0, 74, 0, 72, 0, 74, 0, 76, 0, 0, 0, 79, 0, 76, 0],
    [77, 0, 76, 0, 72, 0, 76, 0, 77, 0, 0, 0, 81, 0, 77, 0],
    [79, 0, 76, 0, 72, 0, 76, 0, 79, 0, 0, 0, 84, 0, 79, 0],
    [83, 0, 81, 0, 79, 0, 81, 0, 83, 0, 0, 0, 86, 0, 83, 0],
]
ARP_ORDER = [0, 2, 4, 2, 1, 3, 5, 3, 0, 2, 4, 2, 1, 3, 5, 3]


def _mk_bus(n):
    return np.zeros((2, n))


def _kick(dur=0.34, seed=0):
    n = int(dur * SR)
    tt = t_axis(n)
    f = 52 + 125 * np.exp(-tt / 0.022)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.105)
    punch = np.sin(2 * np.pi * np.cumsum(190 * np.exp(-tt / 0.03) + 90) / SR) * np.exp(-tt / 0.022) * 0.35
    click = filt(noise(n, seed), "hp", 3000) * np.exp(-tt / 0.004) * 0.45
    return soft_clip(body * 1.15 + punch + click, 1.5) * 0.85


def _snare(dur=0.28, seed=1):
    n = int(dur * SR)
    tt = t_axis(n)
    nz = filt(noise(n, seed), "bp", 2200, 0.7) * np.exp(-tt / 0.07)
    nz += filt(noise(n, seed + 7), "hp", 6000) * np.exp(-tt / 0.03) * 0.5
    tone = np.sin(2 * np.pi * np.cumsum(190 + 90 * np.exp(-tt / 0.02)) / SR) * np.exp(-tt / 0.05)
    return soft_clip(nz * 0.9 + tone * 0.5, 1.2) * 0.8


def _clap(dur=0.32, seed=2):
    n = int(dur * SR)
    tt = t_axis(n)
    base = filt(noise(n, seed), "bp", 1500, 0.9)
    env = np.zeros(n)
    for off in (0.0, 0.011, 0.023):
        i = int(off * SR)
        env[i:] += np.exp(-(tt[: n - i]) / 0.006)
    env += np.exp(-tt / 0.09) * 0.5
    return base * env * 0.55


def _hat(open_=False, seed=3, vel=1.0):
    dur = 0.22 if open_ else 0.06
    n = int(dur * SR)
    tt = t_axis(n)
    x = filt(noise(n, seed), "hp", 7500) * np.exp(-tt / (0.07 if open_ else 0.014))
    return x * 0.35 * vel


def _crash(dur=1.8, seed=5):
    n = int(dur * SR)
    tt = t_axis(n)
    x = filt(noise(n, seed), "hp", 3500) * np.exp(-tt / 0.55)
    x += filt(noise(n, seed + 1), "bp", 9000, 0.6) * np.exp(-tt / 0.3) * 0.6
    return x * 0.5


def _tom(f0, dur=0.3):
    n = int(dur * SR)
    tt = t_axis(n)
    f = f0 * (1 + 0.6 * np.exp(-tt / 0.03))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.11) * 0.7


def _bass_note(f, dur, seed=0):
    n = int(dur * SR)
    tt = t_axis(n)
    w = 0.75 * saw(f, n) + 0.55 * pulse(f, n, 0.35) + 0.5 * np.sin(2 * np.pi * np.cumsum(np.full(n, f / 2)) / SR)
    cut = 260 + 2600 * np.exp(-tt / 0.09)
    w = sweep_filt(w, "lp", cut, 1.1, block=128)
    env = adsr(n, 0.004, 0.06, 0.8, 0.03)
    return w * env * 0.62


def _arp_note(f, dur):
    n = int(dur * SR)
    w = pulse(f, n, 0.25)
    env = adsr(n, 0.002, 0.05, 0.35, 0.02) * np.exp(-t_axis(n) / 0.09)
    return w * env * 0.4


def _lead_note(f, dur, pw=0.5, vib=0.0):
    n = int(dur * SR)
    tt = t_axis(n)
    fv = f * (1 + vib * np.sin(2 * np.pi * 5.5 * tt) * np.minimum(1, tt / 0.15))
    w = pulse(fv, n, pw) * 0.6 + pulse(fv * 1.005, n, pw) * 0.4
    w = filt(w, "lp", 5200)
    env = adsr(n, 0.004, 0.08, 0.75, 0.05)
    return w * env * 0.42


def _pad_chord(notes, dur, detune=0.006):
    n = int(dur * SR)
    out = np.zeros(n)
    for k, m in enumerate(notes):
        for d in (-detune, 0.0, detune):
            out += saw(midi(m - 12) * (1 + d), n) * 0.18
    out = sweep_filt(out, "lp", np.linspace(500, 1800, n), 0.8, block=512)
    env = adsr(n, 0.35, 0.3, 0.85, 0.5)
    return out * env


def _riser(dur, seed=9, top=9000, level=0.5):
    n = int(dur * SR)
    tt = np.linspace(0, 1, n)
    nz = noise(n, seed)
    x = sweep_filt(nz, "bp", 300 * (top / 300) ** tt, 2.5, block=256)
    x *= (tt ** 2.2) * level
    tone = saw(np.linspace(110, 880, n), n) * (tt ** 2.5) * level * 0.25
    return x + filt(tone, "lp", 4000)


def _hit(dur=1.6, size=1.0, seed=11):
    n = int(dur * SR)
    tt = t_axis(n)
    f = 34 + 55 * np.exp(-tt / 0.08)
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.4) * 0.8
    nz = filt(noise(n, seed), "lp", 3800) * np.exp(-tt / 0.22) * 0.95
    return soft_clip((sub * 1.2 + nz) * size, 1.3) * 0.9


def render_music():
    N = int((TOTAL + TAIL) * SR)
    drums, bass, harm, fx = _mk_bus(N), _mk_bus(N), _mk_bus(N), _mk_bus(N)
    kick_times = []
    r = rng(2026)
    kick, snare, clap = _kick(), _snare(), _clap()
    crash = _crash()
    ir = reverb_ir(2.2, seed=4)

    def bar_t(b):
        return b * BAR

    kick_steps = {}
    for b in range(BARS):
        if b in (0, 1):
            ks = [0]
        elif b == 2:
            ks = [0, 4, 8, 12]
        elif b == 3:
            ks = [0, 4, 8]
        elif 4 <= b <= 11:
            ks = [0, 4, 8, 12] + ([14] if b % 2 == 1 and b >= 8 else [])
        elif b in (12, 13):
            ks = [0, 8] if b == 12 else [0, 8]
        elif 14 <= b <= 17:
            ks = [0, 4, 8, 12] + ([14] if b in (15, 17) else [])
        elif b == 18:
            ks = [0]
        else:
            ks = []
        kick_steps[b] = ks

    for b in range(BARS):
        t0 = bar_t(b)
        chord = CHORDS[b % 4]
        root = ROOTS[b % 4]
        full = 4 <= b <= 11 or 14 <= b <= 17
        is_break = b in (12, 13)

        # ---- drums ----
        for s in kick_steps[b]:
            tk = t0 + s * STEP
            place(drums, kick, tk, 1.0)
            kick_times.append(tk)
        # claps/snares on beats 2 and 4
        if full or b == 2:
            for s in (4, 12):
                if b == 3:
                    continue
                place(drums, clap, t0 + s * STEP, 0.85)
                place(drums, snare, t0 + s * STEP, 0.55)
        if is_break and b == 12:
            place(drums, snare, t0 + 8 * STEP, 0.6)   # half-time backbeat
            place(drums, clap, t0 + 8 * STEP, 0.6)
        if b == 13:
            place(drums, snare, t0 + 8 * STEP, 0.6)
        # snare roll leading into the drop (bar 3) and the final drop (bar 13)
        if b in (3, 13):
            steps = [0, 2, 4, 6, 8, 9, 10, 11] if b == 3 else [0, 2, 4, 6, 8, 9, 10, 11]
            for k, s in enumerate(steps):
                vel = 0.35 + 0.65 * (k / len(steps))
                place(drums, snare, t0 + s * STEP, vel)
        # hats
        if b >= 1 and b != 19:
            for s in range(16):
                t = t0 + s * STEP
                if b in (1, 2, 3) and s % 2 == 0:
                    continue
                if is_break and s % 4 != 2:
                    continue
                if b == 3 and s >= 12:
                    continue
                if b == 18 and s >= 8:
                    continue
                if s % 4 == 2:
                    place(drums, _hat(open_=(s in (2, 10)), seed=100 + s + b), t, 0.9)
                elif full or b in (2, 3):
                    place(drums, _hat(False, seed=200 + s + b, vel=0.7 if s % 2 else 1.0), t, 0.7)
        # toms fill at end of bars 7, 11, 17
        if b in (7, 11, 17):
            for k, (s, f0) in enumerate([(12, 180), (13, 150), (14, 120), (15, 95)]):
                place(drums, _tom(f0), t0 + s * STEP, 0.7)
        # crashes on drop entries
        if b in (4, 14, 18):
            place(drums, crash, t0, 0.8)
            place(fx, apply_reverb(crash, ir), t0, 0.35)
        if b == 8:
            place(drums, crash, t0, 0.5)

        # ---- bass ----
        if full or b in (2, 18) or (b == 3):
            steps = [0, 2, 4, 6, 8, 10, 12, 14]
            if b == 3:
                steps = [0, 2, 4, 6, 8, 10]
            if b == 18:
                steps = [0, 2, 4, 6]
            for s in steps:
                m = ROOTS[b % 4] + (12 if s in (6, 14) else 0)
                dur = STEP * (1.8 if s not in (6, 14) else 1.4)
                place(bass, _bass_note(midi(m), dur), t0 + s * STEP, 0.8)
        elif is_break:
            place(bass, _bass_note(midi(root), BEAT * 3.5), t0, 0.7)

        # ---- pad ----
        if b != 3 or True:
            dur = BAR + 0.35
            pad = _pad_chord(chord, dur)
            g = 0.55 if full else (0.8 if is_break else 0.65)
            if b == 19:
                pad = _pad_chord(CHORDS[0], BAR + 1.2, 0.008)
                g = 0.8
            place(harm, pad * g, t0 - 0.05)

        # ---- arp ----
        arp_on = (b <= 3) or full or is_break or b in (18, 19)
        if arp_on:
            tones = [chord[0], chord[1], chord[2], chord[0] + 12, chord[1] + 12, chord[2] + 12]
            for s in range(16):
                if b == 3 and s >= 12:
                    continue
                idx = ARP_ORDER[s]
                f = midi(tones[idx] + 12)
                vel = 0.55 if b <= 1 else (0.5 if is_break else 0.7)
                if b == 0:
                    vel *= (s / 16) * 0.8 + 0.2
                if b == 19:
                    vel = 0.4 * (1 - s / 20)
                note = _arp_note(f, STEP * 1.6)
                place(harm, pan(note, np.sin(s * 0.7) * 0.45), t0 + s * STEP, vel)

        # ---- lead ----
        lead_map = None
        if 4 <= b <= 7:
            lead_map = LEAD_A[b % 4]
        elif 8 <= b <= 11:
            lead_map = LEAD_B[b % 4]
        elif 14 <= b <= 17:
            lead_map = LEAD_B[b % 4]
        elif b == 18:
            lead_map = [69, 0, 0, 0, 0, 0, 0, 0, 72, 0, 0, 0, 0, 0, 0, 0]
        elif b in (12, 13):
            lead_map = [None, None, None, None, 76, 0, 0, 0, 0, 0, 0, 0, 72, 0, 0, 0] if b == 12 else [None] * 8 + [74, 0, 0, 0, 0, 0, 0, 0]
        if lead_map:
            cur, start = None, 0
            events = []
            for s, v in enumerate(lead_map + [None]):
                if v == 0:
                    continue
                if cur is not None:
                    events.append((cur, start, s - start))
                cur, start = v, s
            for m, s0, ln in events:
                vib = 0.006 if ln >= 4 else 0.0
                note = _lead_note(midi(m), STEP * ln * 0.98 + 0.03, pw=0.5 if b < 8 or b >= 14 else 0.25, vib=vib)
                g = 0.62 if not is_break else 0.5
                place(harm, pan(note, 0.1), t0 + s0 * STEP, g)
            if b >= 14 and b <= 17:  # octave-down doubling on the final drop
                for m, s0, ln in events:
                    note = _lead_note(midi(m - 12), STEP * ln * 0.98 + 0.03, pw=0.125, vib=0.0)
                    place(harm, pan(note, -0.15), t0 + s0 * STEP, 0.32)

    # ---- risers, sucks and impacts ----
    place(fx, _riser(3.0, seed=21, top=8000, level=0.55), 3.0)            # into bar 3 -> drop
    place(fx, _riser(1.0, seed=22, top=9500, level=0.6), 5.0)
    place(fx, _riser(2.6, seed=23, top=8000, level=0.5), 19.6)            # breakdown -> final drop
    place(fx, _riser(0.8, seed=24, top=9500, level=0.55), 21.6)
    place(fx, _riser(1.2, seed=25, top=7000, level=0.35), 27.6)
    return {"drums": drums, "bass": bass, "harm": harm, "fx": fx, "kicks": np.array(kick_times)}


def _fm_bell(f, dur):
    n = int(dur * SR)
    tt = t_axis(n)
    mod = np.sin(2 * np.pi * f * 3.5 * tt) * (3.0 * np.exp(-tt / 0.5))
    car = np.sin(2 * np.pi * f * tt + mod) * np.exp(-tt / 0.9)
    car2 = np.sin(2 * np.pi * f * 2.0 * tt + mod * 0.5) * np.exp(-tt / 0.45) * 0.4
    return (car + car2) * 0.6


def kick_duck(kicks, n, depth=0.62, tau=0.13):
    """Sidechain gain curve for harmony/bass buses from the kick times."""
    tt = np.arange(n) / SR
    duck = np.zeros(n)
    for tk in kicks:
        i0 = int(tk * SR)
        if i0 >= n:
            continue
        seg = np.exp(-(tt[i0:i0 + int(0.6 * SR)] - tk) / tau)
        j = min(n, i0 + len(seg))
        duck[i0:j] = np.maximum(duck[i0:j], seg[: j - i0])
    return 1.0 - depth * duck
