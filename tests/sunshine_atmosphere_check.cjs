// Run: node tests/sunshine_atmosphere_check.cjs (stdlib only; GPU rendering checked by survey).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const sources = ['SunshineCloudsCompute.glsl', 'SunshineCloudsPostCompute.comp'].map(name =>
  fs.readFileSync(path.join(root, 'addons/SunshineClouds2', name), 'utf8'));
const block = source => source.slice(source.indexOf('void sampleAtmospherics('), source.indexOf('\nvoid main()'));
const clean = source => source.replace(/\/\/[^\n]*/g, '').replace(/\s+/g, '');
assert.equal(clean(block(sources[0])), clean(block(sources[1])), 'Cloud and post atmosphere must stay identical');
for (const shader of sources) assert(shader.includes('/ 20.0, 20.0, atmosphericDensity'), 'Both callers use 20 samples');
assert(sources[1].includes('step(maxTheoreticalStep, linear_depth)'), 'No undefined equal-edge smoothstep');
const source = block(sources[0]);
// Evaluate the actual scalar GLSL expressions, not a separately copied exponential.
const profileSource = source.slice(source.indexOf('float height ='), source.indexOf('iOdRlh +='));
const profile = new Function('curPos', 'distanceTraveled', `
  const {max, exp} = Math;
  const atmosphericHeight = 40000, Rayleighscaleheight = 8000, Miescaleheight = 1200;
  ${profileSource.replace(/\bfloat\b/g, 'const')}
  return [odStepRlh, odStepMie, iHeight];`);
assert(Math.abs(profile({y: 20000}, 1)[0] - Math.exp(-2.5)) < 1e-12);
assert(Math.abs(profile({y: 20000}, 1)[1] - Math.exp(-20000 / 1200)) < 1e-12);
assert.deepEqual(profile({y: -1e7}, 1), profile({y: 0}, 1));
for (const y of [-1e7, 0, 5000, 19500, 40000, 1e7]) {
  for (const value of profile({y}, 1e7)) assert(Number.isFinite(value) && value >= 0);
}
const intervalSource = source.slice(source.indexOf('if (stepDistance <='), source.indexOf('vec3 totalRlh ='));
const interval = new Function('worldPos', 'rayDirection', 'linear_depth', 'stepDistance', 'stepCount', `
  const {min} = Math;
  ${intervalSource.replace('return vec4(0.0);', 'return [0, 0];')}
  return [linear_depth, stepDistance];`);
for (const [depth, step, count] of [[0, 1, 10], [1, 0, 10], [1, 1, 0], [-1, 1, 10]]) {
  assert.deepEqual(interval({y: 19500}, {y: -1}, depth, step, count), [0, 0]);
}
for (const y of [5000, 19500]) {
  for (const dy of [-1, -Math.SQRT1_2, 0, 1]) {
    const [depth, step] = interval({y}, {y: dy}, 1e7, 9800, 10);
    assert(Number.isFinite(step) && step > 0 && step * 10 <= depth + 1e-8);
    if (dy < 0) assert(Math.abs(depth - y / -dy) < 1e-8, 'Sky rays stop at sea level');
    for (let i = 0; i < 10; i++) assert(y + dy * step * (i + 0.5) >= 0);
  }
}
assert(source.includes('stepDistance * (i + 0.5)'), 'Midpoint integration');
assert(source.includes('vec3 atmospherics = 2.2 *') && !source.includes('/ sampleCount'), 'No 1/N brightness bias');
// Rayleigh quadrature convergence (optical-depth kernel, not the final artistic RGB model).
const integrate = n => Array.from({length: n}, (_, i) => profile({y: 5000 + 98000 / n * (i + 0.5)}, 98000 / n)[0]).reduce((a, b) => a + b, 0);
const exact = 8000 * (Math.exp(-5000 / 8000) - Math.exp(-103000 / 8000));
const error10 = Math.abs(integrate(10) / exact - 1), error20 = Math.abs(integrate(20) / exact - 1);
assert(error20 < error10 && error20 < 0.02);
console.log(`PASS: shader parity, metre profiles, negative/zero/far rays, sampling gain; Rayleigh errors 10=${error10.toFixed(4)}, 20=${error20.toFixed(4)}`);
