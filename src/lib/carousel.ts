// The portal carousel's motion (spec 010 C13): a swipe sets a fractional
// position, letting go picks a portal, and a spring carries the rest of the
// way. Pure, so the feel is testable; PortalStage drives it each frame.

export interface Motion {
  /** Fractional portal index. */
  pos: number;
  /** Portals per second. */
  vel: number;
}

/** The portal to settle on when the student lets go. */
export function release(pos: number, vel: number, count: number): number {
  const from = Math.round(pos);
  // A flick counts even when the drag was short; never more than one portal.
  const aim = Math.abs(vel) > 1.2 ? (vel > 0 ? Math.floor(pos) + 1 : Math.ceil(pos) - 1) : Math.round(pos + vel * 0.15);
  const one = Math.max(from - 1, Math.min(from + 1, aim));
  return Math.max(0, Math.min(count - 1, one));
}

const K = 180;
const C = 2 * Math.sqrt(K) * 0.92;

/** Advance the spring toward `target`, in small sub-steps so long frames stay stable. */
export function step(m: Motion, target: number, dt: number): Motion {
  let { pos, vel } = m;
  const n = Math.max(1, Math.ceil(dt / (1 / 120)));
  const h = Math.min(dt, 0.25) / n;
  for (let i = 0; i < n; i++) {
    vel += (K * (target - pos) - C * vel) * h;
    pos += vel * h;
  }
  return { pos, vel };
}

export const settle = (m: Motion, target: number) => Math.abs(m.pos - target) < 0.002 && Math.abs(m.vel) < 0.02;
