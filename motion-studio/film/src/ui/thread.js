// A light-thread: the film's "connection" grammar. A dashed pixel line on a
// soft bezier from one screen point to another, drawn on by `k`, with a gold
// packet riding it. Pure: render() sets everything from its arguments.
import { clamp, css, el } from "../lib/core.js";

export function makeThread(parent, { color = "#f5b227", width = 6, z = 20 } = {}) {
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("width", "1920");
  svg.setAttribute("height", "1080");
  css(svg, { position: "absolute", left: "0", top: "0", overflow: "visible", zIndex: z, pointerEvents: "none" });
  parent.appendChild(svg);
  const ns = (t) => document.createElementNS("http://www.w3.org/2000/svg", t);
  const path = ns("path");
  path.setAttribute("fill", "none");
  path.setAttribute("stroke", color);
  path.setAttribute("stroke-width", String(width));
  path.setAttribute("stroke-dasharray", `${width * 1.6} ${width * 1.2}`);
  svg.appendChild(path);
  const mask = ns("path");
  const pk = ns("rect");
  pk.setAttribute("width", String(width * 2.6));
  pk.setAttribute("height", String(width * 2.6));
  pk.setAttribute("fill", "#fff6dc");
  svg.appendChild(pk);
  const end = ns("rect");
  end.setAttribute("width", String(width * 2));
  end.setAttribute("height", String(width * 2));
  end.setAttribute("fill", color);
  svg.appendChild(end);
  void mask;
  return {
    svg,
    /** a, c: [x, y]; k: draw-on 0..1; flow: packet position 0..1 (or null); bend: arc height */
    render(on, a, c, k = 1, flow = null, bend = -120) {
      svg.style.display = on ? "" : "none";
      if (!on) return;
      k = clamp(k);
      const mx = (a[0] + c[0]) / 2, my = (a[1] + c[1]) / 2 + bend;
      // quadratic bezier sampled to the draw-on length (dash stays put)
      const pt = (u) => [(1 - u) ** 2 * a[0] + 2 * (1 - u) * u * mx + u * u * c[0], (1 - u) ** 2 * a[1] + 2 * (1 - u) * u * my + u * u * c[1]];
      const N = 24;
      let d = "";
      for (let i = 0; i <= N; i++) { const [x, y] = pt((i / N) * k); d += `${i ? "L" : "M"}${x.toFixed(1)},${y.toFixed(1)}`; }
      path.setAttribute("d", d);
      path.setAttribute("stroke-dashoffset", String(-(flow ?? 0) * 60));
      const [ex, ey] = pt(k);
      end.setAttribute("x", String(ex - 6)); end.setAttribute("y", String(ey - 6));
      if (flow != null && k >= 1) {
        const [px, py] = pt(flow % 1);
        pk.setAttribute("x", String(px - 8)); pk.setAttribute("y", String(py - 8));
        pk.style.display = "";
      } else pk.style.display = "none";
    },
  };
}
