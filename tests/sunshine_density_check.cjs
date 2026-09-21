// Run: node tests/sunshine_density_check.cjs (stdlib only).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const shader = fs.readFileSync(path.join(__dirname, '../addons/SunshineClouds2/SunshineCloudsCompute.glsl'), 'utf8');
const sample = shader.slice(shader.indexOf('float sampleScene('), shader.indexOf('float sampleLighting('));
const edgeGuard = sample.match(/if \(edgeFade <= 0\.0\)\s*\{[^}]+\}/)?.[0];
const macroGuard = sample.match(/if \(largeShape <= 0\.0\)\s*\{[^}]+\}/)?.[0];
assert(edgeGuard && macroGuard, 'Empty samples must return before detail texture fetches');
assert(sample.indexOf(macroGuard) > sample.indexOf('+ max(effectorAdditive, 0.0)'), 'Positive effectors must survive the macro guard');
assert(sample.indexOf(macroGuard) < sample.indexOf('texture(noise_small'));
assert(sample.indexOf(macroGuard) < sample.indexOf('texture(noise_medium'));
assert(sample.indexOf('vec3 smallNoiseUV = (worldPosition - smallNoisePos) / smallnoisescale;') < sample.indexOf('worldPosition +='), 'Retain original detail coordinates, before wind/curl');
assert(sample.includes('texture(noise_small, smallNoiseUV).r'));
// Evaluate the actual shader tail, not a separately maintained density formula.
const tail = sample.slice(sample.indexOf('float shape ='), sample.lastIndexOf('}')).replace(/\bfloat\b/g, 'let');
const helpers = `
  const {min, max} = Math;
  const clamp = (x, lo, hi) => min(max(x, lo), hi);
  const remap = (x, lo, hi, a, b) => a + (x - lo) * (b - a) / (hi - lo);
`;
const args = ['largeShape', 'smallShape', 'mediumshape', 'effectorAdditive', 'edgeFade'];
const original = new Function(...args, helpers + tail);
const optimized = new Function(...args, helpers + edgeGuard + macroGuard + tail);
let comparisons = 0;
for (const macro of [0, 0.001, 0.2, 0.5, 1]) {
  for (const effector of [-1, -0.1, 0, 0.2, 1]) {
    const large = macro + Math.max(effector, 0);
    for (const detail of [0, 0.01, 0.5, 0.99]) {
      for (const medium of [0, 0.01, 0.5, 0.99, 1]) {
        for (const edge of [0, 0.001, 0.5, 1]) {
          const inputs = [large, detail, medium, effector, edge];
          const before = original(...inputs), after = optimized(...inputs);
          assert(Number.isFinite(after) && after >= 0 && after <= 1);
          // The old 0/0 at a zero macro shape is now explicitly empty.
          if (Number.isFinite(before)) assert.equal(after, before);
          else assert.equal(after, 0);
          comparisons++;
        }
      }
    }
  }
}
assert(optimized(1, 0, 0.5, 1, 1) > 0, 'Positive effectors must still add clouds');
for (const name of ['ambient', 'paintedColor']) {
  assert(shader.includes(`${name} / max(lightingSamples, 1.0)`), 'Empty ray history must stay finite');
}
const main = shader.slice(shader.indexOf('void main()')).replace(/\/\/[^\n]*/g, '');
assert(main.indexOf('directionalPhase[lightI] = pow(HenyeyGreenstein') < main.indexOf('for (int i = 0; i < stepCount; i++)'));
assert(main.includes('float henyeygreenstein = directionalPhase[lightI];'));
assert.equal((main.match(/HenyeyGreenstein\(genericData\.data\.anisotropy, directionalLightSunUpPower/g) || []).length, 1, 'Compute directional phase once per ray/light');
// Execute the actual depth guard: a ray cannot sample or light behind its opaque receiver.
const depthGuard = main.match(/if \(traveledDistance > linear_depth\)\s*\{[^}]+\}/)?.[0];
assert(depthGuard && depthGuard.includes('break;'));
assert(main.indexOf(depthGuard) < main.indexOf('newdensity = pow(sampleScene'));
const march = new Function('linear_depth', 'traveledDistance', `let depthBreak = false, samples = 0;
  for (let i = 0; i < 700; i++) { ${depthGuard} samples++; traveledDistance += 50; }
  return {samples, depthBreak};`);
for (const depth of [0, 49, 50, 51, 1000]) {
  for (const start of [0, 32, 90]) {
    assert.deepEqual(march(depth, start), {samples: Math.max(0, Math.floor((depth - start) / 50) + 1), depthBreak: true});
  }
}
// Execute the shader's slab-entry calculation: even Low must reach the deck
// beyond the old Ultra cutoff, without spending samples in kilometres of clear air.
const entryBody = shader.slice(shader.indexOf('float cloudEntryDistance('), shader.indexOf('float cloudExitDistance('));
const entry = new Function('height', 'directionY', 'cloudfloor', 'cloudceiling', entryBody.slice(entryBody.indexOf('{') + 1, entryBody.lastIndexOf('}')));
for (const height of [0, 2000, 3800, 5500, 7114, 12000]) {
  for (const dy of [-1, -0.1, -0.001, 0, 0.001, 0.1, 1]) {
    const start = entry(height, dy, 2000, 5500);
    assert(Number.isFinite(start) && start >= 0);
    const approaching = (height > 5500 && dy < 0) || (height < 2000 && dy > 0);
    if (approaching) {
      assert(Math.abs(height + dy * start - (dy < 0 ? 5500 : 2000)) < 1e-8);
      assert.equal(march(start - 1, start).samples, 0, 'Opaque terrain before the deck must still occlude it');
    } else assert.equal(start, 0, 'Inside/parallel/away rays retain their original start');
  }
}
const exitBody = shader.slice(shader.indexOf('float cloudExitDistance('), shader.indexOf('void main()'));
const exit = new Function('height', 'directionY', 'cloudfloor', 'cloudceiling', 'depth', helpers + exitBody.slice(exitBody.indexOf('{') + 1, exitBody.lastIndexOf('}')));
assert.equal(exit(3800, 0, 2000, 5500, 5000), 5000);
assert.equal(exit(7114, 1, 2000, 5500, 5000), 0);
const farStep = main.match(/if \(i >= stepCount \/ 2\)\s*\{[^}]+\}/)?.[0];
assert(farStep, 'Reserve distant samples without enlarging the budget');
const advance = new Function('i', 'stepCount', 'newStep', 'cloudEnd', 'traveledDistance', helpers + farStep.replace(/float\(/g, 'Number(') + 'return newStep;');
for (const steps of [128, 256, 384, 700]) {
  for (const [height, dy] of [[7114, -0.001], [5501, -0.0001], [0, 0.001], [1999, 0.0001], [3800, -0.001]]) {
    const end = exit(height, dy, 2000, 5500, 4e7);
    let distance = entry(height, dy, 2000, 5500) + 80, hitInterior = false;
    for (let i = 0; i < steps && distance <= end; i++) {
      const y = height + dy * distance;
      hitInterior ||= y > 2700 && y < 4800;
      const step = advance(i, steps, 140, end, distance);
      if (i < steps / 2) assert.equal(step, 140, 'Near detail stays unchanged');
      assert(step >= 140 && Number.isFinite(step));
      distance += step;
    }
    assert(hitInterior, `Grazing rays must reach the dense interior: ${steps}, ${height}, ${dy}`);
  }
}
assert(entry(7114, -0.01, 2000, 5500) > 700 * 140, 'Test must exceed the old Ultra cutoff');
assert(main.includes('float traveledDistance = cloudStart + newStep;'));
assert(main.includes('if (i == 0 && cloudStart == 0.0)'), 'First-sample fade must not make distant density negative');
assert(main.includes('min(max(traveledDistance, maxTheoreticalStep), linear_depth)'), 'Layer exit must not rewind a distant ray');
assert(!/density\s*\*=.*(?:stepCount|maxTheoreticalStep)/.test(main), 'Quality budgets must not erase the distant sea');
assert(main.includes('for (int i = 0; i < stepCount; i++)'), 'Retain the bounded quality budget');
console.log(`PASS: ${comparisons} density cases, effectors, UVs, history, lighting, depth clipping, horizon slab entry and bounded distant sampling`);
