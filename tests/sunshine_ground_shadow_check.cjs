// Run: node tests/sunshine_ground_shadow_check.cjs. Scalar GLSL checks; rendering needs Godot Forward+.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const base = 'addons/SunshineClouds2/';
const post = read(base + 'SunshineCloudsPostCompute.comp');
const main = read(base + 'SunshineCloudsCompute.glsl');
const driver = read(base + 'SunshineClouds.gd');
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const mix = (a, b, t) => a + (b - a) * t;
const smoothstep = (a, b, v) => { const t = clamp((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
// Execute the actual projection/opacity/guard expressions. Only texture and vector operations
// are stubbed: this is not a GPU renderer or a separately copied shadow algorithm.
const body = post.slice(post.indexOf('float sampleGroundShadow('), post.indexOf('\nfloat w0('));
const scalarBody = body.slice(body.indexOf('{') + 1, body.lastIndexOf('}'))
  .replace('normalize(sun.direction.xyz)', 'sun.direction') // Unit directions below.
  .replace('worldPosition + sunDirection * travel', 'project(worldPosition, sunDirection, travel)')
  .replace(/texture\(extra_large_noise,[^;]+;/, '1.0;')
  .replace(/sampleSceneCoarse\([\s\S]*?\);/, 'sampleShape(samplePosition);')
  .replace(/\b(float|vec3|DirectionalLight)\b/g, 'let');
const evaluate = new Function('worldPosition', 'genericData', 'ground_shadow', 'directionalLights',
  'sampleShape', 'project', 'clamp', 'mix', 'smoothstep', `const {pow, exp, max} = Math; ${scalarBody}`);
const data = {cloud_floor: 2000, cloud_ceiling: 5500, cloud_density: 0.028,
  cloud_coverage: 0.834, cloud_sharpness: 0.767, max_step_distance: 140, directionalLightsCount: 1};
const project = (p, d, t) => ({x: p.x + d.x * t, y: p.y + d.y * t, z: p.z + d.z * t});
function run({position = {x: 100, y: 200, z: 300}, direction = {x: 0.8, y: 0.6, z: 0},
  strength = 0.3, height = 0.5, energy = 0.6, shape = () => 1, settings = {}} = {}) {
  return evaluate(position, {data: {...data, ...settings}}, {strength, height_fraction: height},
    [{direction, color: {a: energy}}], shape, project, clamp, mix, smoothstep);
}
let sampled;
const darkening = run({shape: p => { sampled = p; return 1; }});
assert(darkening > 0.2 && darkening <= 0.3);
assert.equal(sampled.y, 3750);
assert(Math.abs(sampled.x - (100 + (3750 - 200) * 0.8 / 0.6)) < 1e-8, 'Project toward the sun, not straight down');
assert.equal(sampled.z, 300);
const noSample = () => assert.fail('Disabled/invalid receivers must not sample noise');
for (const options of [
  {strength: 0}, {energy: 0}, {direction: {x: 1, y: 0, z: 0}},
  {direction: {x: 0, y: -1, z: 0}}, {settings: {directionalLightsCount: 0}},
  {settings: {cloud_density: 0}}, {settings: {cloud_coverage: 0}},
  {settings: {cloud_ceiling: 2000}}, {settings: {cloud_ceiling: 1000}},
  {position: {x: 0, y: 3750, z: 0}}, {position: {x: 0, y: 7000, z: 0}},
]) assert.equal(run({...options, shape: noSample}), 0);
assert.equal(run({shape: () => 0}), 0, 'A hole in the shared noise receives no shadow');
assert(run({settings: {cloud_density: 0.0001}}) < darkening);
assert(run({position: {x: 0, y: 3749, z: 0}}) < 0.001, 'Fade crossing the representative slice');
for (const height of [-1, 0.05, 0.5, 0.95, 2]) {
  const value = run({height, settings: {max_step_distance: 0}});
  assert(Number.isFinite(value) && value >= 0 && value <= 0.3);
}
assert(main.includes('#include "./CloudsCoarseDensity.comp"'));
assert(driver.includes('[extra_noise_uniform, noise_uniform, height_gradient_uniform]'), 'Share texture RIDs, not independent noise');
assert(driver.includes('compute_list_set_push_constant(postpass_list, shadow_params, shadow_params.size())'));
assert(post.includes('genericData.data.extralargenoiseposition.xz') && post.includes('genericData.data.largenoiseposition'));
assert(post.includes('depth > 0.0 && ground_shadow.strength > 0.0'), 'Exclude clear sky depth');
assert(post.includes('(vec2(uv) + 0.5) / vec2(size)') && post.includes('ivec2 size = textureSizeMSAA(depth_image)'));
assert(post.indexOf('color.rgb *= 1.0 - sampleGroundShadow') < post.indexOf('vec3 physicalFogColor = color.rgb'), 'Shadow before haze');
assert(post.indexOf('vec3 physicalFogColor = color.rgb') < post.indexOf('color.rgb = mix(color.rgb, currentAccumilation.rgb, density)'));
for (const name of ['SunshineCloudsPostCompute.glsl', 'SunshineCloudsPostCompute.msaa.glsl']) {
  assert(read(base + name).includes('#include "./SunshineCloudsPostCompute.comp"'));
  assert(read(base + name).includes('#include "./CloudsCoarseDensity.comp"'));
}
const presetStrength = Number(read('resources/environments/tutorial_clouds.tres').match(/^ground_shadow_strength = ([\d.]+)$/m)?.[1]);
assert(presetStrength > 0 && presetStrength <= 1, 'Preset enables shadows; artistic tuning is not fixed at 0.3');
console.log('PASS: shared noise wiring, solar projection, opacity, disabled/sky/above-cloud guards, slice fade, MSAA entrypoint parity, pre-atmosphere ordering');
