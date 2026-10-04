// The "steps" of a page in pages.json: actions run after it loads and before it is shot (see config.mjs for the list).
// A step that cannot run stops the whole run and says which one, so a state that can no longer be reached
// (a button that went missing) is a failure, never a screenshot of the wrong thing.
const configuredTimeout = Number(process.env.VR_STEP_TIMEOUT_MS);
const TIMEOUT = Number.isInteger(configuredTimeout) && configuredTimeout > 0 ? configuredTimeout : 10000;

// What a step is called in an error: never the value of a fill or select, which may be something you typed in.
export function describeStep(step) {
  const [action] = Object.keys(step);
  const v = step[action];
  if (action === 'wait') return `wait ${v}ms`;
  return `${action} "${typeof v === 'object' ? v.selector : v}"`;
}

export async function runSteps(page, steps, where) {
  for (const [i, step] of steps.entries()) {
    const [action] = Object.keys(step);
    const v = step[action];
    try {
      if (action === 'click') await page.click(v, { timeout: TIMEOUT });
      else if (action === 'hover') await page.hover(v, { timeout: TIMEOUT });
      else if (action === 'fill') await page.fill(v.selector, v.value, { timeout: TIMEOUT });
      else if (action === 'select') await page.selectOption(v.selector, v.value, { timeout: TIMEOUT });
      else if (action === 'press') await page.keyboard.press(v);
      else if (action === 'waitFor') await page.waitForSelector(v, { timeout: TIMEOUT });
      else if (action === 'wait') await page.waitForTimeout(v);
    } catch (e) {
      throw new Error(`${where}: step ${i + 1} (${describeStep(step)}) failed: ${String(e.message).split('\n')[0]}`);
    }
  }
  await page.waitForLoadState('networkidle', { timeout: TIMEOUT });     // a click may start a request: let it finish
}
