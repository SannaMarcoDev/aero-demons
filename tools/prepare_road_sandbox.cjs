// Run once before opening garda_roads_test.tscn. Never overwrites an existing sandbox.
// node tools/prepare_road_sandbox.cjs
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'terrain/garda_geographic_250km');
const target = path.join(root, 'terrain/garda_roads_test');
if (fs.existsSync(target)) throw Error(`Sandbox already exists; refusing to overwrite ${target}`);
if (!fs.readdirSync(source).some(name => /^terrain3d.*\.res$/.test(name))) {
  throw Error('Source Garda terrain regions are missing');
}
fs.cpSync(source, target, {recursive: true, force: false, errorOnExist: true});
console.log(`PASS: independent terrain copy created at ${target}`);
