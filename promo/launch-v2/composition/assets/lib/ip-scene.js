/* Scene helpers: cue lookup, keyframe tracks, typewriter timing, dive/warp curves. Pure + deterministic. */
(function () {
  const IP = window.IP;
  const CUES = window.CUES || { cues: [], scenes: [], vo: [], blips: [] };
  IP.BEAT = CUES.beat || 0.4;
  IP.bt = (b) => b * IP.BEAT;
  const byId = {};
  (CUES.cues || []).forEach((c) => (byId[c.id] = c));
  (CUES.vo || []).forEach((c) => (byId[c.id] = c));
  (CUES.blips || []).forEach((c) => (byId[c.id] = c));
  IP.cue = (id) => { if (!byId[id]) throw new Error("missing cue " + id); return byId[id].t; };
  IP.scene = (id) => (CUES.scenes || []).find((s) => s.id === id);

  // keyframe track: keys = [[t, v, ease?], ...] -> f(t). ease: 'lin' | 'io' | 'out' | 'in' (applied on the segment ENDING at that key)
  const E = { lin: (u) => u, io: (u) => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2), out: (u) => 1 - Math.pow(1 - u, 3), in: (u) => u * u * u, out5: (u) => 1 - Math.pow(1 - u, 5), in2: (u) => u * u, back: (u) => { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(u - 1, 3) + c1 * Math.pow(u - 1, 2); } };
  IP.E = E;
  IP.track = function (keys) {
    return function (t) {
      if (t <= keys[0][0]) return keys[0][1];
      for (let i = 1; i < keys.length; i++) {
        if (t <= keys[i][0]) {
          const [t0, v0] = keys[i - 1], [t1, v1, e] = keys[i];
          const u = (t - t0) / (t1 - t0);
          return v0 + (v1 - v0) * (E[e || "io"](u));
        }
      }
      return keys[keys.length - 1][1];
    };
  };
  IP.step = (t, t0, t1) => IP.clamp((t - t0) / (t1 - t0));
  IP.steps = (u, n) => Math.floor(IP.clamp(u) * n) / n;   // pixel-y stepped easing

  // Isko's talk blips: onset offsets per character (must match tools/audio/vo.py blip_line)
  IP.blipTimes = function (text, speed = 1) {
    const out = [];
    let t = 0;
    for (const ch of text) {
      const c = ch.toLowerCase();
      if (/[a-z]/.test(c)) { out.push(t); t += 0.062 / speed; }
      else if (c === " ") t += 0.045 / speed;
      else if (c === "," || c === ";") t += 0.11 / speed;
      else t += 0.16 / speed;
    }
    return out;
  };
  // reveal text char by char at the blip times (returns [[t, nChars], ...])
  IP.typeSchedule = function (text, t0, speed = 1) {
    let n = 0, t = 0;
    const s = [];
    for (const ch of text) {
      const c = ch.toLowerCase();
      n++;
      s.push([t0 + t, n]);
      if (/[a-z]/.test(c)) t += 0.062 / speed;
      else if (c === " ") t += 0.045 / speed;
      else if (c === "," || c === ";") t += 0.11 / speed;
      else t += 0.16 / speed;
    }
    return s;
  };
  // drive an element's text by a schedule using one seek-safe tween
  IP.driveText = function (tl, el, sched, endT) {
    const st = { n: 0 };
    const text = el.dataset.full;
    tl.fromTo(st, { n: 0 }, {
      n: 1, duration: Math.max(0.01, endT - sched[0][0]), ease: "none", immediateRender: false,
      onUpdate: function () {
        // find count for local time
        const now = tl.time();
        let k = 0;
        for (let i = 0; i < sched.length; i++) if (sched[i][0] <= now + 1e-6) k = sched[i][1];
        el.textContent = text.slice(0, k);
      },
    }, sched[0][0]);
  };

  // deterministic screen shake offsets
  IP.shake = function (t, t0, dur = 0.3, amp = 8) {
    const u = (t - t0) / dur;
    if (u < 0 || u > 1) return [0, 0];
    const k = (1 - u) * amp;
    return [Math.sin(t * 91) * k, Math.cos(t * 77) * k * 0.7];
  };
})();
