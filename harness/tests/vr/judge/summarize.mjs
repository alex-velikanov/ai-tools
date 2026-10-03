// summarize.mjs <out dir>: per-case severities across the runs kept by repeat.sh.
import fs from 'fs';
import { ORDERED } from './cases.mjs';

const out = process.argv[2];
const runs = fs.readdirSync(out).filter(d => /^run\d+$/.test(d)).sort((a, b) => a.slice(3) - b.slice(3));
const reports = runs.map(r => {
  try { return new Map(JSON.parse(fs.readFileSync(`${out}/${r}/vr/report.json`)).map(x => [x.file, x.severity ?? 0])); } catch { return null; }
});
const failed = runs.filter((_, i) => !reports[i]);
console.log(`${runs.length} runs, ${failed.length} without a report${failed.length ? ' (' + failed.join(', ') + ')' : ''}`);
for (const r of failed) {
  const raw = `${out}/${r}/vr/raw_report.txt`;
  console.log(`  ${r}: ${fs.existsSync(raw) ? JSON.stringify(fs.readFileSync(raw, 'utf8').slice(0, 300)) : 'no raw reply (the run died before judging)'}`);
}
console.log('\ncase               expected  severity per run                      flagged (sev>=3)');
const rows = ORDERED.map(c => {
  const sev = reports.map(m => (m ? (m.has(c.file) ? m.get(c.file) : '-') : 'x'));
  const judged = sev.filter(s => s !== 'x');
  const flagged = judged.filter(s => s !== '-' && s >= 3).length;
  return { c, sev, flagged, judged: judged.length };
});
for (const { c, sev, flagged, judged } of rows.sort((a, b) => b.c.gate - a.c.gate || a.c.id.localeCompare(b.c.id))) {
  const wrong = c.gate ? judged - flagged : flagged;
  console.log(`${c.id.padEnd(18)} ${(c.gate ? 'flag' : 'quiet').padEnd(9)} ${sev.join(' ').padEnd(37)} ${flagged}/${judged}${wrong ? `   <- ${wrong} wrong` : ''}`);
}
console.log('\nx = run had no report, - = case absent from the report (never judged, or dropped as identical)');
