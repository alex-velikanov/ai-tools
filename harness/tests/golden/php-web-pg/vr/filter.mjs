import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';
import fs from 'fs';

// A screenshot is "changed" if it exists on only one side, its size differs, or more than
// MIN_DIFF_PX pixels differ. An absolute pixel count (not a % of the image) so a small but
// real change, like a missing button, is not lost on a tall page.
const MIN_DIFF_PX = Number(process.env.VR_MIN_DIFF_PX ?? 50);

const base = fs.readdirSync('baseline');
const cur = fs.readdirSync('current');
const all = [...new Set([...base, ...cur])].sort();
const changed = [];

for (const f of all) {
  if (!fs.existsSync(`baseline/${f}`) || !fs.existsSync(`current/${f}`)) { changed.push(f); continue; }
  const a = PNG.sync.read(fs.readFileSync(`baseline/${f}`));
  const b = PNG.sync.read(fs.readFileSync(`current/${f}`));
  if (a.width !== b.width || a.height !== b.height) { changed.push(f); continue; }
  const d = pixelmatch(a.data, b.data, null, a.width, a.height, { threshold: 0.1 });
  if (d > MIN_DIFF_PX) changed.push(f);
}

fs.writeFileSync('changed.json', JSON.stringify(changed, null, 2));
console.log(`${changed.length} changed of ${all.length}`);
