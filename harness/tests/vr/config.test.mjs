// Unit tests for vr/config.mjs (pages.json -> screenshot targets). No browser. Run: node config.test.mjs <path to vr/>
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';

const { resolveTargets, DEFAULT_VIEWPORTS, fileName, slug } = await import(pathToFileURL(`${process.argv[2]}/config.mjs`));
const tests = [];
const test = (name, fn) => tests.push([name, fn]);

test('default viewports are desktop 1440x900, tablet 768x1024, mobile 390x844', () => {
  assert.deepEqual(Object.keys(DEFAULT_VIEWPORTS), ['desktop', 'tablet', 'mobile']);
  assert.deepEqual([DEFAULT_VIEWPORTS.desktop.width, DEFAULT_VIEWPORTS.desktop.height], [1440, 900]);
  assert.deepEqual([DEFAULT_VIEWPORTS.tablet.width, DEFAULT_VIEWPORTS.tablet.height], [768, 1024]);
  assert.deepEqual([DEFAULT_VIEWPORTS.mobile.width, DEFAULT_VIEWPORTS.mobile.height], [390, 844]);
  assert.ok(!DEFAULT_VIEWPORTS.desktop.mobile && DEFAULT_VIEWPORTS.tablet.mobile && DEFAULT_VIEWPORTS.mobile.mobile);
});
test('a plain list of paths still works and gets every default viewport', () => {
  const t = resolveTargets(['/', '/pricing']);
  assert.equal(t.length, 6);
  assert.deepEqual(t.map(x => `${x.viewport}:${x.path}`), [
    'desktop:/', 'tablet:/', 'mobile:/', 'desktop:/pricing', 'tablet:/pricing', 'mobile:/pricing']);
});
test('object form uses its own viewports instead of the defaults', () => {
  const t = resolveTargets({ viewports: { phone: { width: 320, height: 568, mobile: true } }, pages: ['/'] });
  assert.equal(t.length, 1);
  assert.deepEqual([t[0].viewport, t[0].width, t[0].height, t[0].mobile], ['phone', 320, 568, true]);
});
test('a page can be limited to some viewports', () => {
  const t = resolveTargets({ pages: ['/', { path: '/checkout', viewports: ['mobile'] }] });
  assert.deepEqual(t.filter(x => x.path === '/checkout').map(x => x.viewport), ['mobile']);
  assert.equal(t.filter(x => x.path === '/').length, 3);
});
test('file names carry viewport, page and tile, and never collide across viewports', () => {
  const names = resolveTargets(['/', '/a/b']).map(x => fileName(x, 0));
  assert.equal(new Set(names).size, names.length);
  assert.ok(names.includes('mobile__home__0.png') && names.includes('tablet__a_b__0.png'));
  assert.equal(slug('/'), 'home');
});
test('rejects unknown viewport names, naming the known ones', () => {
  assert.throws(() => resolveTargets({ pages: [{ path: '/', viewports: ['watch'] }] }), /unknown viewport "watch".*desktop, tablet, mobile/);
});
test('rejects bad paths, empty pages, bad viewport sizes and names', () => {
  assert.throws(() => resolveTargets(['pricing']), /starting with "\/"/);
  assert.throws(() => resolveTargets([]), /non-empty/);
  assert.throws(() => resolveTargets({ pages: ['/'], viewports: { x: { width: 0, height: 10 } } }), /integer width and height/);
  assert.throws(() => resolveTargets({ pages: ['/'], viewports: { 'bad name': { width: 1, height: 1 } } }), /letters, digits/);
  assert.throws(() => resolveTargets({ pages: ['/'], viewports: {} }), /must not be empty/);
});
test('rejects a page listed twice', () => {
  assert.throws(() => resolveTargets(['/', '/']), /listed twice/);
});

let failed = 0;
for (const [name, fn] of tests) {
  try { fn(); console.log(`ok   ${name}`); } catch (e) { failed++; console.log(`FAIL ${name}\n     ${e.message}`); }
}
process.exit(failed ? 1 : 0);
