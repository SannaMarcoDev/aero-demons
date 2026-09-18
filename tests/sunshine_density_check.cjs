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
console.log(`PASS: ${comparisons} density cases, effectors, original UVs, empty history and per-ray phase`);
