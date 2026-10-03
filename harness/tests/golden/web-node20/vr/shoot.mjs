import { chromium } from 'playwright';
import fs from 'fs';
import { resolveTargets, fileName } from './config.mjs';

const base  = process.env.BASE_URL;
const out   = process.env.OUT;
const targets = resolveTargets(JSON.parse(fs.readFileSync(new URL('./pages.json', import.meta.url))));
const MAX_TILES = 6;

const browser = await chromium.launch();
fs.mkdirSync(out, { recursive: true });

// One browser context per viewport: size, touch and mobile emulation are set per context.
for (const name of new Set(targets.map(t => t.viewport))) {
  const group = targets.filter(t => t.viewport === name);
  const { width, height, mobile } = group[0];
  const ctx = await browser.newContext({
    viewport: { width, height },
    reducedMotion: 'reduce',
    ...(mobile ? { isMobile: true, hasTouch: true } : {}),
  });
  const page = await ctx.newPage();

  for (const t of group) {
    await page.goto(base + t.path, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);

    const h     = await page.evaluate(() => document.documentElement.scrollHeight);
    const tiles = Math.min(Math.ceil(h / height), MAX_TILES);

    for (let i = 0; i < tiles; i++) {
      await page.evaluate(y => window.scrollTo(0, y), i * height);
      await page.waitForTimeout(300);
      await page.screenshot({ path: `${out}/${fileName(t, i)}` });
    }
  }
  await ctx.close();
}
await browser.close();
