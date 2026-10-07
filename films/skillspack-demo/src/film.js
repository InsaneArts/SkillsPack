// SkillsPack demo. A seekable film: draw(ctx, t, fmt, assets) paints the exact frame at time t.
// Every app pixel is a real SkillsPack render (assets/ui). Times match shotlist.md.
import { clamp, ease, lerp, span } from "/lib.js";

// "push": the camera eases in on the panel while it is used. "static": a plain screen recording.
const DIRECTION = "push";

const K = 1.2; // film pixels per screen point: a 1600×900 pt Mac screen in a 1920×1080 frame
const SCREEN = { w: 1600, h: 900 };
const ICON = { x: 1237, y: 12 }; // SkillsPack icon in the menu bar (MenuBarStrip.iconCenter)
const PANEL = { x: ICON.x - 200, y: 28, w: 400, h: 600 };
// The camera follows the action, like a screen recorder's auto-zoom. It never leaves the screen:
// at zoom z its center stays within w/2z … w − w/2z and h/2z … h − h/2z.

// Beat times (seconds). The same table drives picture and sound.
const T = {
  open: 0.5, bro: 2.2, codex: 3.9, back1: 5.6, banner: 6.9, fix: 8.3, back2: 9.9,
  plus: 11.0, field: 12.1, paste: 12.6, find: 13.5, found: 14.6, install: 16.0, wide: 16.35, rest: 17.2, card: 19.3,
  toastGone: 19.06, // the app hides a toast 3 s after it appears
};

// Panel point → screen point.
const P = (x, y) => ({ x: PANEL.x + x, y: PANEL.y + y });

// Camera framings, each from its start time: [time, zoom, focus]. Moves take 0.9 s.
const SHOTS = [
  [0, 1.6, { x: ICON.x - 120, y: 0 }], // the menu bar icon and the cursor
  [T.open + 0.1, 1.6, P(200, 270)], // the list
  [T.bro + 0.1, 2.0, P(200, 365)], // the switches and the toast below them
  [T.back1 + 0.1, 1.6, P(200, 270)], // the list with the problem banner
  [T.banner + 0.1, 2.0, P(200, 230)], // the problem and the Fix button
  [T.back2 + 0.1, 1.6, P(200, 270)], // the list and the + button
  [T.plus + 0.1, 1.9, P(200, 170)], // the Add Skills header and the URL field
  [T.find + 0.1, 1.9, P(200, 350)], // the URL field down to the Install button
  [T.wide, 1.35, { x: SCREEN.w, y: 0 }], // the panel on the right, room for the end card
];
const MOVE = 0.9;

// Each click: when, and where the cursor is when it clicks (screen points).
const CLICKS = [
  { t: T.open, at: ICON },
  { t: T.bro, at: P(150, 432) },
  { t: T.codex, at: P(350, 337) },
  { t: T.back1, at: P(34, 20) },
  { t: T.banner, at: P(210, 160) },
  { t: T.fix, at: P(354, 124) },
  { t: T.back2, at: P(34, 20) },
  { t: T.plus, at: P(338, 29) },
  { t: T.field, at: P(190, 139) },
  { t: T.find, at: P(356, 139) },
  { t: T.install, at: P(200, 570) },
  // After the last click the hand moves off the panel. No click.
  { t: T.rest, at: { x: ICON.x + 3, y: 13 }, silent: true }, // rests on the menu bar icon
];
const CURSOR_START = { x: ICON.x - 64, y: 58 };

// Which app screen shows from which time. The app swaps screens in about a tenth of a second.
const STATES = [
  [T.open, "list"], [T.bro + 0.06, "detail"], [T.codex + 0.06, "detailOff", { blend: [322, 318, 56, 38], dur: 0.2 }], [T.back1 + 0.06, "listAfterToggle"],
  [T.banner + 0.06, "health"], [T.fix + 0.06, "healthFixed"], [T.back2 + 0.06, "listAfterFix"],
  [T.plus + 0.06, "installEmpty"], [T.paste, "installPasted"], [T.find + 0.06, "installFinding"],
  [T.found, "installFound"], [T.install + 0.06, "listInstalled"], [T.toastGone, "listFinal"],
];

const FONT = `-apple-system, "SF Pro Display", "Helvetica Neue", sans-serif`;

export default {
  duration: 23,
  fps: 60,
  formats: ["wide"],
  poster: 22.9,
  assets: {
    menubar: "assets/menubar-white.png",
    list: "assets/ui/01-list.png",
    detail: "assets/ui/03-detail-bro.png",
    detailOff: "assets/ui/04-detail-bro-off.png",
    listAfterToggle: "assets/ui/05-list-after-toggle.png",
    health: "assets/ui/06-health.png",
    healthFixed: "assets/ui/07-health-fixed.png",
    listAfterFix: "assets/ui/07b-list-after-fix.png",
    installEmpty: "assets/ui/08-install-empty.png",
    installPasted: "assets/ui/09-install-pasted.png",
    installFinding: "assets/ui/10-install-finding.png",
    installFound: "assets/ui/11-install-found.png",
    listInstalled: "assets/ui/12-list-installed.png",
    listFinal: "assets/ui/13-list-final.png",
  },

  draw(ctx, t, fmt, assets) {
    ctx.imageSmoothingQuality = "high";
    const cam = camera(t);
    // Screen points → film pixels, through the camera.
    ctx.setTransform(cam.z * K, 0, 0, cam.z * K, fmt.w / 2 - cam.fx * cam.z * K, fmt.h / 2 - cam.fy * cam.z * K);

    wallpaper(ctx);
    const open = panelOpen(t);
    if (open > 0) statusHighlight(ctx, open);
    ctx.drawImage(assets.menubar, 0, 0, SCREEN.w, 24);
    if (open > 0) panel(ctx, t, assets, open);
    cursor(ctx, t);

    ctx.setTransform(1, 0, 0, 1, 0, 0);
    endCard(ctx, t, fmt);
  },

  async audio(ac, out) {
    // A trackpad click is a short, bright tick on press and a softer one on release.
    const noise = ac.createBuffer(1, Math.round(ac.sampleRate * 0.05), ac.sampleRate);
    const data = noise.getChannelData(0);
    let seed = 7;
    for (let i = 0; i < data.length; i++) {
      seed = (seed * 16807) % 2147483647;
      data[i] = (seed / 2147483647) * 2 - 1;
    }
    const tick = (at, gain, freq) => {
      const src = ac.createBufferSource();
      src.buffer = noise;
      const band = ac.createBiquadFilter();
      band.type = "bandpass";
      band.frequency.value = freq;
      band.Q.value = 1.2;
      const g = ac.createGain();
      g.gain.setValueAtTime(0, at);
      g.gain.linearRampToValueAtTime(gain, at + 0.002);
      g.gain.exponentialRampToValueAtTime(0.0001, at + 0.035);
      src.connect(band).connect(g).connect(out);
      src.start(at);
      src.stop(at + 0.05);
    };
    for (const click of CLICKS.filter((c) => !c.silent)) {
      tick(click.t, 0.22, 3200);
      tick(click.t + 0.075, 0.1, 2600);
    }
    // ⌘V: two soft key presses before the link appears.
    tick(T.paste - 0.14, 0.08, 1800);
    tick(T.paste - 0.04, 0.1, 1700);
  },
};

// MARK: Camera

function framing([, z, focus]) {
  const x = clamp(focus.x, SCREEN.w / 2 / z, SCREEN.w - SCREEN.w / 2 / z);
  const y = clamp(focus.y, SCREEN.h / 2 / z, SCREEN.h - SCREEN.h / 2 / z);
  return { z, x, y };
}

function camera(t) {
  if (DIRECTION !== "push") return { z: 1, fx: SCREEN.w / 2, fy: SCREEN.h / 2 };
  let shot = framing(SHOTS[0]);
  for (let i = 1; i < SHOTS.length && t >= SHOTS[i][0]; i++) {
    const p = ease.inOutCubic(span(t, SHOTS[i][0], MOVE));
    const b = framing(SHOTS[i]);
    shot = { z: lerp(shot.z, b.z, p), x: lerp(shot.x, b.x, p), y: lerp(shot.y, b.y, p) };
  }
  return { z: shot.z, fx: shot.x, fy: shot.y };
}

// MARK: Desktop

function wallpaper(ctx) {
  const { w, h } = SCREEN;
  const base = ctx.createLinearGradient(0, 0, w, h);
  base.addColorStop(0, "#0e2747");
  base.addColorStop(0.55, "#22356f");
  base.addColorStop(1, "#3a2c63");
  ctx.fillStyle = base;
  ctx.fillRect(-w, -h, w * 3, h * 3);
  for (const [x, y, r, color] of [[260, 760, 760, "rgba(38, 140, 170, 0.45)"], [1380, 140, 700, "rgba(120, 90, 200, 0.35)"], [820, 420, 520, "rgba(70, 110, 220, 0.25)"]]) {
    const glow = ctx.createRadialGradient(x, y, 0, x, y, r);
    glow.addColorStop(0, color);
    glow.addColorStop(1, "rgba(0, 0, 0, 0)");
    ctx.fillStyle = glow;
    ctx.fillRect(-w, -h, w * 3, h * 3);
  }
}

function statusHighlight(ctx, alpha) {
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.fillStyle = "rgba(255, 255, 255, 0.22)";
  ctx.beginPath();
  ctx.roundRect(ICON.x - 15, 1.5, 30, 21, 5);
  ctx.fill();
  ctx.restore();
}

// MARK: Panel

// 0..1: the panel appears when the icon is clicked, as fast as macOS shows it.
function panelOpen(t) {
  return ease.outCubic(span(t, T.open + 0.03, 0.08));
}

function panel(ctx, t, assets, alpha) {
  const { x, y, w, h } = PANEL;
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.shadowColor = "rgba(0, 0, 0, 0.42)";
  ctx.shadowBlur = 48;
  ctx.shadowOffsetY = 14;
  ctx.fillStyle = "#fff";
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, 11);
  ctx.fill();
  ctx.restore();

  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, 11);
  ctx.clip();
  // The current screen, cut on the click like the app. A switch animates in its own small area.
  let index = 0;
  for (let i = 0; i < STATES.length; i++) if (t >= STATES[i][0]) index = i;
  const [start, name, change] = STATES[index];
  ctx.drawImage(assets[name], x, y, w, h);
  if (change && index > 0 && t - start < change.dur) {
    const [bx, by, bw, bh] = change.blend;
    ctx.globalAlpha = alpha * (1 - ease.inOutCubic(span(t, start, change.dur)));
    ctx.beginPath();
    ctx.rect(x + bx, y + by, bw, bh);
    ctx.clip();
    ctx.drawImage(assets[STATES[index - 1][1]], x, y, w, h);
  }
  ctx.restore();

  // The text caret blinks in the URL field after it is clicked, until the link is pasted.
  if (t >= T.field + 0.05 && t < T.paste && Math.floor((t - T.field) / 0.53) % 2 === 0) {
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.fillStyle = "#1d1d1f";
    ctx.fillRect(x + 49, y + 131, 1.2, 16);
    ctx.restore();
  }

  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.strokeStyle = "rgba(0, 0, 0, 0.18)";
  ctx.lineWidth = 0.6;
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, 11);
  ctx.stroke();
  ctx.restore();
}

// MARK: Cursor

function cursorPosition(t) {
  let from = CURSOR_START;
  for (const click of CLICKS) {
    // The hand leaves 1 s before the click at most, and arrives 0.12 s before it.
    const leave = Math.max(click.t - 1.05, 0);
    const arrive = click.t - 0.12;
    if (t < leave) return from;
    if (t < arrive) {
      const p = ease.inOutCubic(span(t, leave, arrive - leave));
      const dx = click.at.x - from.x, dy = click.at.y - from.y;
      const bow = Math.sin(p * Math.PI) * Math.min(40, Math.hypot(dx, dy) * 0.08);
      const len = Math.hypot(dx, dy) || 1;
      return { x: lerp(from.x, click.at.x, p) - (dy / len) * bow, y: lerp(from.y, click.at.y, p) + (dx / len) * bow };
    }
    from = click.at;
  }
  return from;
}

function cursor(ctx, t) {
  const { x, y } = cursorPosition(t);
  let press = 1;
  for (const click of CLICKS.filter((c) => !c.silent)) {
    const d = t - click.t;
    if (d > -0.02 && d < 0.12) press = Math.min(press, 1 - 0.12 * Math.sin(clamp((d + 0.02) / 0.14) * Math.PI));
  }
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(press, press);
  ctx.shadowColor = "rgba(0, 0, 0, 0.35)";
  ctx.shadowBlur = 6;
  ctx.shadowOffsetY = 2;
  ctx.beginPath();
  const pts = [[0, 0], [0, 17], [4.2, 13], [7, 19.4], [9.8, 18.2], [7.1, 12.1], [12.4, 12.1]];
  pts.forEach(([px, py], i) => (i ? ctx.lineTo(px, py) : ctx.moveTo(px, py)));
  ctx.closePath();
  ctx.fillStyle = "#111";
  ctx.fill();
  ctx.shadowColor = "transparent";
  ctx.lineWidth = 1.3;
  ctx.strokeStyle = "#fff";
  ctx.lineJoin = "round";
  ctx.stroke();
  ctx.restore();
}

// MARK: End card

function endCard(ctx, t, fmt) {
  const p = ease.outExpo(span(t, T.card, 0.6));
  if (p <= 0) return;
  const { y, h } = fmt.safe;
  const x = fmt.safe.x + 40;
  ctx.save();
  ctx.globalAlpha = p;
  ctx.fillStyle = "#fff";
  ctx.textBaseline = "alphabetic";
  ctx.font = `600 104px ${FONT}`;
  ctx.fillText("SkillsPack", x, y + h - 150 + (1 - p) * 14);
  ctx.globalAlpha = p * 0.82;
  ctx.font = `400 44px ${FONT}`;
  const lines = ["Skills for Claude Code, Codex, and pi.", "In your menu bar."];
  lines.forEach((line, i) => ctx.fillText(line, x + 3, y + h - 66 + i * 56 + (1 - p) * 14));
  ctx.restore();
}
