// The campus fragment shader. It draws the sky per pixel by the hour (Bayer
// dithered bands, stars, a sun or moon with a dithered halo, drifting clouds)
// and lights the scene's cells from build(): night shading, water shimmer,
// window glow, the class's lit window and the jeepney. Flat colours only; the
// Bayer threshold is the one gradient. One body for WebGL2 and WebGL1.

const BODY = /* glsl */ `
uniform sampler2D u_cells;
uniform sampler2D u_pal;
uniform float u_time;
uniform float u_hour;
uniform float u_lit;
uniform float u_haze;
uniform float u_road;
uniform float u_skyH[10];
uniform vec3 u_skyT[10];
uniform vec3 u_skyB[10];

const float W = 192.0;
const float H = 80.0;
const float ROWS = 88.0;
const vec3 NIGHT = vec3(10.0, 12.0, 30.0) / 255.0;
const vec3 WARM = vec3(232.0, 196.0, 106.0) / 255.0;

vec4 cell(vec2 p) { return TEX(u_cells, (p + 0.5) / vec2(W, ROWS)); }
vec4 pal(float i, float row) { return TEX(u_pal, vec2((i + 0.5) / 256.0, (row + 0.5) / 2.0)); }
float b2(vec2 a) { return fract(a.x * 0.5 + a.y * a.y * 0.75); }
float bayer(vec2 p) { return b2(floor(p / 2.0)) * 0.25 + b2(mod(p, 2.0)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float byte(float v) { return floor(v * 255.0 + 0.5); }

void skyAt(float h, out vec3 top, out vec3 bot) {
  top = u_skyT[0]; bot = u_skyB[0];
  for (int i = 0; i < 9; i++) {
    if (h >= u_skyH[i] && (h < u_skyH[i + 1] || i == 8)) {
      float t = clamp((h - u_skyH[i]) / (u_skyH[i + 1] - u_skyH[i]), 0.0, 1.0);
      float e = t * t * (3.0 - 2.0 * t);
      top = mix(u_skyT[i], u_skyT[i + 1], e);
      bot = mix(u_skyB[i], u_skyB[i + 1], e);
    }
  }
}
float lightAt(float h) {
  float l = h < 5.5 || h > 19.0 ? 0.0 : h < 7.0 ? (h - 5.5) / 1.5 : h > 17.5 ? (19.0 - h) / 1.5 : 1.0;
  return clamp(l, 0.0, 1.0);
}
vec2 arc(float t) { return vec2(floor(12.0 + t * (W - 24.0) + 0.5), floor(40.0 - sin(t * 3.14159265) * 32.0 + 0.5)); }

// A cloud: three stacked bars, the bottom one shaded, dithered to 85% of the daylight.
bool cloud(vec2 p, float cx, float cy, float cw, float th, float light, inout vec3 col) {
  float x = floor(mod(cx + u_time * 1.1111, W + 40.0) - 20.0 + 0.5);
  vec2 q = p - vec2(x, cy);
  bool body = (q.y >= 0.0 && q.y < 2.0 && q.x >= 2.0 && q.x < cw - 2.0) || (q.y >= 2.0 && q.y < 4.0 && q.x >= 0.0 && q.x < cw);
  bool belly = q.y == 4.0 && q.x >= 1.0 && q.x < cw - 1.0;
  // Solid by day; dawn and dusk thin them out, one dither step at a time, then they are gone.
  if ((body || belly) && th < (light - 0.45) * 2.0) {
    vec3 c = belly ? vec3(0.874, 0.91, 0.949) : vec3(1.0);
    col = mix(c, vec3(0.7, 0.72, 0.76), u_haze);
    return true;
  }
  return false;
}

vec3 sky(vec2 p, vec3 top, vec3 bot, float light, float frame, float th) {
  // Seven flat bands from the top to the horizon, dithered where they meet.
  float b = clamp(floor((p.y / 65.0) * 7.0 + th - 0.5), 0.0, 6.0);
  vec3 col = mix(top, bot, b / 6.0);
  float night = 1.0 - light;
  if (night > 0.3 && p.y < 34.0) {
    float s = hash(p);
    if (s > 0.9935 && mod(frame + floor(fract(s * 977.0) * 40.0), 37.0) > 2.0) col = fract(s * 131.0) > 0.8 ? vec3(1.0, 0.953, 0.769) : vec3(0.788, 0.804, 0.91);
  }
  float h = u_hour;
  if (h >= 5.8 && h <= 18.4) {
    vec2 d = p - arc((h - 5.8) / 12.6);
    vec2 a = abs(d);
    float r = length(d);
    if ((a.x <= 1.0 && a.y <= 1.0)) return vec3(1.0, 0.82, 0.4);
    if ((a.x <= 2.0 && a.y <= 1.0) || (a.x <= 1.0 && a.y <= 2.0)) return vec3(1.0, 0.945, 0.722);
    if (r < 7.0 && th < (1.0 - (r - 2.5) / 4.5) * 0.55) col = mix(col, vec3(1.0, 0.945, 0.722), 0.4);
  } else {
    float t = clamp(((h < 12.0 ? h + 24.0 : h) - 18.4) / 11.4, 0.0, 1.0);
    vec2 d = p - arc(t);
    float r = length(d + vec2(0.5, 0.0));
    bool body = (d.x >= -2.0 && d.x <= 1.0 && d.y >= -1.0 && d.y <= 1.0) || (d.x >= -1.0 && d.x <= 0.0 && d.y >= -2.0 && d.y <= 2.0);
    bool bite = d.x >= 0.0 && d.x <= 1.0 && d.y >= -1.0 && d.y <= 0.0;
    if (body && !bite) return vec3(0.957, 0.937, 0.851);
    if (r < 6.0 && !body && th < (1.0 - (r - 2.5) / 3.5) * 0.4) col = mix(col, vec3(0.957, 0.937, 0.851), 0.25);
  }
  if (light > 0.2) {
    vec3 c = col;
    if (cloud(p, 20.0, 10.0, 16.0, th, light, c) || cloud(p, 96.0, 16.0, 22.0, th, light, c) || cloud(p, 150.0, 7.0, 14.0, th, light, c)) col = c;
  }
  return col;
}

vec3 shade(float id, vec3 bot, float night, float th) {
  vec4 a = pal(id, 0.0);
  float far = pal(id, 1.0).r;
  vec3 c = mix(a.rgb, bot, far);
  c = mix(c, NIGHT, night * a.a);
  // Rainy-season haze: the far layer dissolves toward the horizon, one dither step at a time.
  if (far > 0.0 && th < u_haze * far * 1.4) c = mix(bot, NIGHT, night * 0.4);
  return c;
}

void main() {
  vec2 p = vec2(floor(gl_FragCoord.x), H - 1.0 - floor(gl_FragCoord.y));
  float frame = floor(u_time * 12.0);
  vec3 top; vec3 bot;
  skyAt(u_hour, top, bot);
  float light = lightAt(u_hour);
  float night = 1.0 - light;
  float th = bayer(p);
  vec4 c = cell(p);
  float id = byte(c.r);
  float role = byte(c.g);
  float win = byte(c.b);
  vec3 col;
  if (id < 0.5) {
    col = sky(p, top, bot, light, frame, th);
  } else {
    col = shade(id, bot, night, th);
    if (role == 1.0) {
      // Water: short flat streaks of the sky's horizon on every third row, drifting once a second,
      // and a rare glint.
      float step1 = floor(u_time * 1.2);
      if (mod(p.y, 3.0) == 1.0 && hash(vec2(floor((p.x + step1) / 5.0), p.y)) > 0.55) col = mix(col, mix(bot, NIGHT, night * 0.5), 0.45);
      if (hash(vec2(p.x, p.y + step1 * 7.0)) > 0.985) col = night > 0.5 ? WARM : mix(col, vec3(1.0), 0.6);
    } else if (role == 2.0) {
      if (night > 0.4 && hash(vec2(win, 3.0)) < 0.28) col = WARM;
      if (win == u_lit) col = mod(frame, 16.0) < 12.0 ? vec3(1.0, 0.843, 0.369) : vec3(0.949, 0.698, 0.2);
    } else if (role == 3.0 && night > 0.4) {
      col = WARM;
    }
  }
  // The lit window's glow: a one-pixel dithered ring, breathing with the frame.
  if (u_lit > 0.0 && win != u_lit) {
    float near = 0.0;
    if (byte(cell(p + vec2(1.0, 0.0)).b) == u_lit) near = 1.0;
    if (byte(cell(p - vec2(1.0, 0.0)).b) == u_lit) near = 1.0;
    if (byte(cell(p + vec2(0.0, 1.0)).b) == u_lit) near = 1.0;
    if (byte(cell(p - vec2(0.0, 1.0)).b) == u_lit) near = 1.0;
    if (near > 0.0 && th < 0.25 + 0.2 * step(8.0, mod(frame, 16.0))) col = mix(col, vec3(1.0, 0.843, 0.369), 0.6);
  }
  // A jeepney every 16 seconds; the body bobs on its wheels.
  float cyc = mod(u_time, 16.0) / 16.0;
  if (cyc < 0.55) {
    float jx = floor(-20.0 + (cyc / 0.55) * (W + 40.0) + 0.5);
    float bob = mod(frame, 4.0) < 2.0 ? 0.0 : 1.0;
    float lx = p.x - jx;
    float ly = p.y - u_road;
    float row = ly == 6.0 ? 6.0 : ly + bob;
    if (lx >= 0.0 && lx < 18.0 && row >= 0.0 && row < 7.0 && (ly == 6.0 || row < 6.0)) {
      float j = byte(cell(vec2(lx, H + row)).r);
      if (j > 0.5) col = shade(j, bot, night, 1.0);
    }
    if (night > 0.4 && ly == 3.0 && lx >= 18.0 && lx < 21.0) col = vec3(1.0, 0.945, 0.722);
  }
  OUT = vec4(col, 1.0);
}
`;

const VERT2 = `#version 300 es
in vec2 a_pos;
void main() { gl_Position = vec4(a_pos, 0.0, 1.0); }`;

const FRAG2 = `#version 300 es
precision highp float;
#define TEX texture
out vec4 fragOut;
#define OUT fragOut
${BODY}`;

const VERT1 = `attribute vec2 a_pos;
void main() { gl_Position = vec4(a_pos, 0.0, 1.0); }`;

const FRAG1 = `#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#define TEX texture2D
#define OUT gl_FragColor
${BODY}`;

export const SHADERS = { 2: { vert: VERT2, frag: FRAG2 }, 1: { vert: VERT1, frag: FRAG1 } } as const;
