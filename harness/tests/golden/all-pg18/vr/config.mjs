// Turns pages.json into the list of (viewport, page) screenshots to take. No browser needed.
//
// pages.json is either a plain list of paths, which uses the default viewports:
//   ["/", "/pricing"]
// or an object with your own viewports and per-page options:
//   { "viewports": { "desktop": { "width": 1440, "height": 900 }, "phone": { "width": 390, "height": 844, "mobile": true } },
//     "pages": ["/", { "path": "/checkout", "viewports": ["phone"] }] }
// "mobile": true emulates a touch device (mobile viewport meta handling, touch events).

export const DEFAULT_VIEWPORTS = {
  desktop: { width: 1440, height: 900 },
  tablet: { width: 768, height: 1024, mobile: true },
  mobile: { width: 390, height: 844, mobile: true },
};

export function slug(path) {
  return path.replace(/\W+/g, '_').replace(/^_+|_+$/g, '') || 'home';
}

export function fileName(target, tile) {
  return `${target.viewport}__${slug(target.path)}__${tile}.png`;
}

export function resolveTargets(raw) {
  const cfg = Array.isArray(raw) ? { pages: raw } : raw;
  if (!cfg || !Array.isArray(cfg.pages) || cfg.pages.length === 0) {
    throw new Error('pages.json needs a non-empty list of pages');
  }
  const viewports = cfg.viewports ?? DEFAULT_VIEWPORTS;
  const names = Object.keys(viewports);
  if (names.length === 0) throw new Error('"viewports" must not be empty');
  for (const n of names) {
    const v = viewports[n];
    if (!/^[a-z0-9-]+$/i.test(n)) throw new Error(`viewport name "${n}" must be letters, digits or "-"`);
    if (!Number.isInteger(v.width) || !Number.isInteger(v.height) || v.width <= 0 || v.height <= 0) {
      throw new Error(`viewport "${n}" needs integer width and height`);
    }
  }

  const targets = [];
  const seen = new Set();
  for (const page of cfg.pages) {
    const p = typeof page === 'string' ? { path: page } : page;
    if (typeof p.path !== 'string' || !p.path.startsWith('/')) {
      throw new Error(`page path must be a string starting with "/": ${JSON.stringify(page)}`);
    }
    for (const name of p.viewports ?? names) {
      if (!viewports[name]) throw new Error(`page "${p.path}" uses unknown viewport "${name}" (known: ${names.join(', ')})`);
      const key = `${name}__${slug(p.path)}`;
      if (seen.has(key)) throw new Error(`page "${p.path}" is listed twice for viewport "${name}" (or its name collides with another path)`);
      seen.add(key);
      targets.push({ path: p.path, viewport: name, ...viewports[name] });
    }
  }
  return targets;
}
