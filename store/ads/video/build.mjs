// T-102 (video v2) — renders the ad video from scene.html, with ONE command:
//
//     cd store/ads/video && npm i --no-save playwright-core@1.56.1 && node build.mjs
//
// Input: src/<state>.png, the app's real screens written by
//   `cd app && fvm flutter test store_ads/video_frames_test.dart`.
// Output, per cut (25 s master, 15 s) and canvas:
//   entrelares-v2[-15s]-{9x16,4x5,16x9}.mp4 — H.264, yuv420p, 30 fps, faststart,
//   NO audio track (no licensed music — owner, 04/10/2026), plus
//   frames/<same name>-first.png and -end.png (the first frame and the card).
//
// Chromium: the Playwright cache when there is one, else the installed Chrome.
// ffmpeg: from the PATH when there is one, otherwise the pinned Docker image
// render_video.sh already uses.
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const { chromium } = (() => {
  for (const base of [here, process.env.PLAYWRIGHT_CORE_DIR].filter(Boolean)) {
    try { return createRequire(join(base, 'noop.js'))('playwright-core'); } catch { /* next */ }
  }
  return require('playwright-core');
})();

const FPS = 30;
const CANVASES = [
  { name: '9x16', w: 1080, h: 1920 },
  { name: '4x5', w: 1080, h: 1350 },
  { name: '16x9', w: 1920, h: 1080 },
];
const CUTS = (process.env.CUTS || '25,15').split(',').map(Number);
const only = process.env.ONLY; // e.g. ONLY=9x16 while iterating

// ── hotspots: the boxes the pointers aim at, measured on the source screens ──
// Done in Python (Pillow) so the measure is a colour match on the REAL pixels,
// never a hand-typed coordinate: the card of today's carer (rose container),
// the Aprovar button (brand solid), the swapped day (amber container) and the
// first notification row.
function measure() {
  const out = execFileSync('python', ['-I', join(here, 'hotspots.py')], { encoding: 'utf8' });
  const hot = JSON.parse(out);
  writeFileSync(join(here, 'src', 'hotspots.json'), JSON.stringify(hot, null, 2));
  return hot;
}

function chromePath() {
  const cache = join(process.env.LOCALAPPDATA || '', 'ms-playwright');
  if (existsSync(cache)) {
    const dirs = readdirSync(cache).filter(d => /^chromium_headless_shell-\d+$/.test(d)).sort().reverse();
    for (const d of dirs) {
      const p = join(cache, d, 'chrome-headless-shell-win64', 'chrome-headless-shell.exe');
      if (existsSync(p)) return p;
    }
  }
  for (const p of ['C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe']) {
    if (existsSync(p)) return p;
  }
  return undefined;
}

function ffmpeg(args, cwd) {
  try {
    execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...args], { cwd, stdio: 'inherit' });
  } catch (e) {
    if (e.code !== 'ENOENT') throw e;
    execFileSync('docker', ['run', '--rm', '-v', `${cwd}:/w`, '-w', '/w', 'jrottenberg/ffmpeg:6.1-alpine',
      '-hide_banner', '-loglevel', 'error', '-y', ...args], { stdio: 'inherit' });
  }
}

async function render(browser, hot, canvas, cut) {
  const name = `entrelares-v2${cut === 25 ? '' : `-${cut}s`}-${canvas.name}`;
  const work = join(here, 'tmp', name);
  rmSync(work, { recursive: true, force: true }); mkdirSync(work, { recursive: true });
  const page = await browser.newPage({ viewport: { width: canvas.w, height: canvas.h }, deviceScaleFactor: 1 });
  await page.addInitScript(h => { window.HOTSPOTS = h; }, hot);
  const url = pathToFileURL(join(here, 'scene.html')).href + `?w=${canvas.w}&h=${canvas.h}&cut=${cut}`;
  await page.goto(url);
  await page.evaluate(() => Promise.all([document.fonts.ready,
    ...[...document.images].map(i => i.complete ? null : new Promise(r => { i.onload = i.onerror = r; }))]));
  const frames = cut * FPS;
  const t0 = Date.now();
  for (let i = 0; i < frames; i++) {
    await page.evaluate(t => window.seek(t), i / FPS);
    await page.screenshot({ path: join(work, `f${String(i).padStart(4, '0')}.png`), type: 'png' });
    if (i % 150 === 0) console.log(`${name}: frame ${i}/${frames} (${((Date.now() - t0) / 1000).toFixed(0)} s)`);
  }
  await page.close();
  mkdirSync(join(here, 'frames'), { recursive: true });
  // The two stills the campaign uploads next to the video.
  for (const [i, suffix] of [[0, 'first'], [frames - 1, 'end']]) {
    const src = join(work, `f${String(i).padStart(4, '0')}.png`);
    writeFileSync(join(here, 'frames', `${name}-${suffix}.png`), require('node:fs').readFileSync(src));
  }
  // Paths relative to this folder: it is the one Docker mounts, so the file
  // lands HERE under both ffmpegs.
  ffmpeg(['-framerate', String(FPS), '-i', `tmp/${name}/f%04d.png`, '-c:v', 'libx264', '-preset', 'slow', '-crf', '19',
    '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-an', `${name}.mp4`], here);
  rmSync(work, { recursive: true, force: true });
  console.log(`wrote ${name}.mp4`);
}

const hot = measure();
console.log('hotspots', JSON.stringify(hot));
const browser = await chromium.launch({ executablePath: chromePath(), headless: true });
try {
  for (const cut of CUTS) for (const canvas of CANVASES) {
    if (only && canvas.name !== only) continue;
    await render(browser, hot, canvas, cut);
  }
} finally {
  await browser.close();
  rmSync(join(here, 'tmp'), { recursive: true, force: true });
}
