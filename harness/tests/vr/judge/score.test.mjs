// Unit tests for judge/score.mjs and the calibration cases. No browser, no model. Run: node score.test.mjs
import assert from 'node:assert/strict';
import { score } from './score.mjs';
import { CASES, ORDERED } from './cases.mjs';

const tests = [];
const test = (name, fn) => tests.push([name, fn]);
const cases = [
  { id: 'a', file: 'p1__0.png', gate: true }, { id: 'b', file: 'p2__0.png', gate: true },
  { id: 'c', file: 'p3__0.png', gate: false }, { id: 'd', file: 'p4__0.png', gate: false },
];
const all = cases.map(c => c.file);

test('perfect report: recall 100%, no false alarms', () => {
  const s = score(cases, [{ file: 'p1__0.png', severity: 4 }, { file: 'p2__0.png', severity: 3 }, { file: 'p3__0.png', severity: 0 }, { file: 'p4__0.png', severity: 2 }], all);
  assert.equal(s.recall, 1); assert.equal(s.fpr, 0); assert.deepEqual(s.missed, []); assert.deepEqual(s.falseAlarms, []);
});
test('severity 2 does not count as flagged, 3 does (the vr.sh gate)', () => {
  const s = score(cases, [{ file: 'p1__0.png', severity: 2 }, { file: 'p2__0.png', severity: 3 }, { file: 'p3__0.png', severity: 3 }], all);
  assert.deepEqual(s.missed, ['a']); assert.deepEqual(s.falseAlarms, ['c']);
  assert.equal(s.recall, 0.5); assert.equal(s.fpr, 0.5);
});
test('a broken page missing from the report is a miss, with the reason', () => {
  const s = score(cases, [{ file: 'p2__0.png', severity: 5 }], ['p2__0.png']);
  assert.deepEqual(s.missed, ['a']);
  assert.match(s.rows.find(r => r.id === 'a').note, /dropped by the pixel filter/);
  const t = score(cases, [{ file: 'p2__0.png', severity: 5 }], all);
  assert.match(t.rows.find(r => r.id === 'a').note, /missing from the report/);
});
test('a fine page the filter drops (identical) is correctly quiet', () => {
  const s = score(cases, [], []);
  assert.deepEqual(s.falseAlarms, []);
});
test('a non-array report scores as nothing flagged', () => {
  assert.equal(score(cases, null, all).recall, 0);
});
test('calibration cases: unique ids, opaque unique file names, both kinds present', () => {
  assert.equal(new Set(CASES.map(c => c.id)).size, CASES.length);
  assert.equal(ORDERED.length, CASES.length);
  assert.equal(new Set(ORDERED.map(c => c.file)).size, ORDERED.length);
  for (const c of ORDERED) assert.match(c.file, /^page\d\d__0\.png$/, 'file names must not reveal the case');
  assert.ok(CASES.filter(c => c.gate).length >= 10 && CASES.filter(c => !c.gate).length >= 6);
});
test('the file order is shuffled so position does not reveal the label', () => {
  const labels = ORDERED.map(c => c.gate);
  const firstHalf = labels.slice(0, labels.length / 2).filter(Boolean).length;
  assert.ok(firstHalf > 0 && firstHalf < labels.filter(Boolean).length, 'broken cases must be in both halves');
});

let failed = 0;
for (const [name, fn] of tests) {
  try { fn(); console.log(`ok   ${name}`); } catch (e) { failed++; console.log(`FAIL ${name}\n     ${e.message}`); }
}
process.exit(failed ? 1 : 0);
