// The old portal: a dated, generic student-portal sign-in page drawn in 2D
// canvas (no real school's marks). Pure: drawLogin(ctx, state) paints every
// pixel from the state it is given. The open scene animates it; the magnet
// scene slices it into the shards that become the new portal.
export const PW = 1100, PH = 720;

const CAPTCHA = "x7Kq9";

export function drawLogin(g, s = {}) {
  g.save();
  g.clearRect(0, 0, PW, PH);
  // window chrome
  g.fillStyle = "#d9d9d9"; g.fillRect(0, 0, PW, 44);
  const grad = g.createLinearGradient(0, 0, 0, 44); grad.addColorStop(0, "#ececec"); grad.addColorStop(1, "#c9c9c9");
  g.fillStyle = grad; g.fillRect(0, 0, PW, 44);
  [["#e0625a", 22], ["#e5bf3c", 44], ["#62c254", 66]].forEach(([c, x]) => { g.fillStyle = c; g.beginPath(); g.arc(x, 22, 6.5, 0, 7); g.fill(); });
  g.fillStyle = "#fff"; g.strokeStyle = "#9a9a9a"; g.lineWidth = 1;
  g.fillRect(96, 9, PW - 120, 26); g.strokeRect(96.5, 9.5, PW - 121, 25);
  g.fillStyle = "#666"; g.font = "15px Arial"; g.textBaseline = "middle";
  g.fillText("http://student-portal.example.edu.ph/login.php?session=expired&ref=…", 108, 22);
  // banner
  const bn = g.createLinearGradient(0, 44, 0, 118); bn.addColorStop(0, "#5d6b7d"); bn.addColorStop(1, "#3f4a58");
  g.fillStyle = bn; g.fillRect(0, 44, PW, 74);
  g.fillStyle = "#fff"; g.font = "bold 28px 'Times New Roman'"; g.fillText("Student Information System", 26, 82);
  g.font = "14px Arial"; g.globalAlpha = 0.8; g.fillText("Student Module (Beta) · best viewed in Internet Explorer 8", 420, 84); g.globalAlpha = 1;
  // body
  g.fillStyle = "#f3f4f6"; g.fillRect(0, 118, PW, PH - 118);
  // marquee
  g.fillStyle = "#fff6c7"; g.fillRect(0, 118, PW, 30);
  g.fillStyle = "#8a6d00"; g.font = "bold 14px Arial";
  const mq = ((s.t ?? 0) * 90) % 900;
  g.fillText("*** NOTICE: The system will be under maintenance. Please try again later. ***", PW - mq - 200, 134);
  // login box
  const bx = 300, by = 180, bw = 500, bh = 470;
  g.fillStyle = "#fff"; g.fillRect(bx, by, bw, bh);
  g.strokeStyle = "#b9bec6"; g.strokeRect(bx + 0.5, by + 0.5, bw - 1, bh - 1);
  g.fillStyle = "#dfe3e8"; g.fillRect(bx, by, bw, 44);
  g.fillStyle = "#222"; g.font = "bold 18px Arial"; g.fillText("Student Login", bx + 18, by + 22);
  const field = (label, y, val, focus) => {
    g.fillStyle = "#333"; g.font = "bold 15px Arial"; g.fillText(label, bx + 30, y);
    g.fillStyle = "#fff"; g.fillRect(bx + 30, y + 14, bw - 60, 36);
    g.strokeStyle = focus ? "#3b82f6" : "#9aa0a8"; g.lineWidth = focus ? 2 : 1;
    g.strokeRect(bx + 30.5, y + 14.5, bw - 61, 35);
    g.fillStyle = "#111"; g.font = "18px Arial"; g.fillText(val, bx + 42, y + 33);
    if (focus && Math.floor((s.t ?? 0) * 2.4) % 2 === 0) { g.fillRect(bx + 44 + g.measureText(val).width, y + 22, 2, 22); }
  };
  field("Student Number", by + 76, s.num ?? "", s.focus === 0);
  field("Password", by + 156, "•".repeat(s.pw ?? 0), s.focus === 1);
  // captcha
  g.fillStyle = "#333"; g.font = "bold 15px Arial"; g.fillText("Type the characters below", bx + 30, by + 236);
  g.fillStyle = "#cfd3c0"; g.fillRect(bx + 30, by + 250, 170, 50);
  for (let i = 0; i < 9; i++) { g.strokeStyle = i % 2 ? "#8b8f7a" : "#a3a78f"; g.beginPath(); g.moveTo(bx + 30, by + 256 + i * 5); g.lineTo(bx + 200, by + 250 + ((i * 17) % 50)); g.stroke(); }
  g.font = "italic bold 30px 'Times New Roman'";
  [...CAPTCHA].forEach((c, i) => { g.save(); g.translate(bx + 48 + i * 28, by + 283); g.rotate(((i * 37) % 7 - 3) * 0.09); g.fillStyle = "#2b2b2b"; g.fillText(c, 0, 0); g.restore(); });
  g.fillStyle = "#fff"; g.fillRect(bx + 215, by + 250, bw - 245, 50);
  g.strokeStyle = s.focus === 2 ? "#3b82f6" : "#9aa0a8"; g.lineWidth = s.focus === 2 ? 2 : 1; g.strokeRect(bx + 215.5, by + 250.5, bw - 246, 49);
  g.fillStyle = "#111"; g.font = "20px Arial"; g.fillText(s.cap ?? "", bx + 228, by + 276);
  if (s.err) { g.fillStyle = "#c62828"; g.font = "bold 15px Arial"; g.fillText(s.err, bx + 30, by + 330); }
  // button
  const pressed = s.press ?? 0;
  const bg = g.createLinearGradient(0, by + 360, 0, by + 400); bg.addColorStop(0, pressed > 0.3 ? "#cfcfcf" : "#f6f6f6"); bg.addColorStop(1, "#d6d6d6");
  g.fillStyle = bg; g.fillRect(bx + 30, by + 356, 140, 42);
  g.strokeStyle = "#7d7d7d"; g.lineWidth = 1; g.strokeRect(bx + 30.5, by + 356.5, 139, 41);
  g.fillStyle = "#111"; g.font = "17px Arial"; g.fillText(s.btn ?? "Sign in", bx + 62, by + 378);
  g.fillStyle = "#1a4fb5"; g.font = "14px Arial"; g.fillText("Forgot password?", bx + 200, by + 378);
  g.fillText("Help  |  Privacy  |  Contact the registrar", bx + 30, by + 440);
  // loading overlay
  if (s.dim) { g.fillStyle = `rgba(20,20,26,${s.dim})`; g.fillRect(0, 118, PW, PH - 118); }
  if (s.spin != null) {
    g.save(); g.translate(PW / 2, 420); g.rotate(s.spin);
    g.lineWidth = 9; g.strokeStyle = "rgba(255,255,255,.25)"; g.beginPath(); g.arc(0, 0, 34, 0, 7); g.stroke();
    g.strokeStyle = "#fff"; g.beginPath(); g.arc(0, 0, 34, 0, 1.2); g.stroke(); g.restore();
    if (s.progress != null) {
      g.fillStyle = "rgba(255,255,255,.2)"; g.fillRect(PW / 2 - 160, 480, 320, 10);
      g.fillStyle = "#fff"; g.fillRect(PW / 2 - 160, 480, 320 * s.progress, 10);
      g.font = "bold 15px Arial"; g.textAlign = "center"; g.fillText(`Loading… ${Math.floor(s.progress * 100)}%`, PW / 2, 512); g.textAlign = "left";
    }
  }
  if (s.stamp) {
    g.save(); g.translate(PW / 2, 360); g.rotate(-0.06);
    g.strokeStyle = "#e5484d"; g.lineWidth = 12; g.strokeRect(-330, -110, 660, 220);
    g.fillStyle = "#e5484d"; g.font = "700 104px 'Pixelify Sans'"; g.textAlign = "center";
    g.fillText("SESSION", 0, -34); g.fillText("EXPIRED", 0, 64); g.restore();
  }
  g.restore();
}
