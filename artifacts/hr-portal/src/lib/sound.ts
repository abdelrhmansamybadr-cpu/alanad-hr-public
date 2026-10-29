/**
 * Sounds for the website (Web Audio, nothing to download).
 *
 * Browsers keep a page silent until the person has clicked or pressed a key on it at least once, so the audio engine is
 * "unlocked" on the first click / key / touch anywhere on the site. After that the meeting ring and the notification chime
 * play even when the tab is in the background.
 */

let ctx: AudioContext | null = null;
let unlocked = false;

function engine(): AudioContext | null {
  if (ctx) return ctx;
  try {
    const AC = window.AudioContext || (window as any).webkitAudioContext;
    if (!AC) return null;
    ctx = new AC();
  } catch {
    ctx = null;
  }
  return ctx;
}

/** Create / resume the audio engine. Must run inside a click, key or touch (the page's first one is enough). */
export function unlockAudio(): boolean {
  const c = engine();
  if (!c) return false;
  if (c.state === "suspended") void c.resume().catch(() => {});
  unlocked = c.state === "running" || unlocked;
  return c.state === "running";
}

/** True once sound is allowed (the person has interacted with the page). */
export function audioReady(): boolean {
  return !!ctx && ctx.state === "running";
}

if (typeof window !== "undefined") {
  const once = () => {
    if (unlockAudio() || unlocked) {
      for (const ev of ["pointerdown", "keydown", "touchstart"]) window.removeEventListener(ev, once, true);
    }
  };
  for (const ev of ["pointerdown", "keydown", "touchstart"]) window.addEventListener(ev, once, true);
}

function tone(c: AudioContext, at: number, dur: number, freqs: number[], volume: number) {
  const g = c.createGain();
  g.gain.setValueAtTime(0.0001, at);
  g.gain.exponentialRampToValueAtTime(volume, at + 0.03);
  g.gain.setValueAtTime(volume, at + Math.max(0.04, dur - 0.06));
  g.gain.exponentialRampToValueAtTime(0.0001, at + dur);
  g.connect(c.destination);
  for (const f of freqs) {
    const o = c.createOscillator();
    o.type = "sine";
    o.frequency.value = f;
    o.connect(g);
    o.start(at);
    o.stop(at + dur + 0.02);
  }
}

/** A loud, phone-like ring (two bursts, a pause, repeat). Returns a function that stops it. */
export function startRing(): () => void {
  let stopped = false;
  const cycle = () => {
    const c = engine();
    if (!c || stopped) return;
    if (c.state === "suspended") { void c.resume().catch(() => {}); return; } // still locked: retry on the next cycle
    const t = c.currentTime + 0.02;
    tone(c, t, 0.45, [440, 480], 0.5);
    tone(c, t + 0.6, 0.45, [440, 480], 0.5);
  };
  cycle();
  const timer = setInterval(cycle, 2200);
  return () => { stopped = true; clearInterval(timer); };
}

/** A short two-note chime for a normal notification. */
export function chime(): void {
  const c = engine();
  if (!c) return;
  if (c.state === "suspended") { void c.resume().catch(() => {}); if (c.state === "suspended") return; }
  const t = c.currentTime + 0.02;
  tone(c, t, 0.2, [880], 0.4);
  tone(c, t + 0.2, 0.35, [1175], 0.4);
}
