const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'aero-runner-'));
try {
  for (const [name, code, expected, seconds] of [
    ['success', 'console.log("PASS: done")', 0, 5],
    ['missing-marker', 'console.log("done")', 1, 5],
    ['error-after-pass', 'console.log("PASS: done\\nSCRIPT ERROR: regression")', 1, 5],
    ['leak', 'console.log("PASS: done\\nWARNING: 2 ObjectDB instances were leaked at exit")', 1, 5],
    ['exit-failure', 'console.log("PASS: done"); process.exitCode = 2', 1, 5],
    ['deadline', 'console.log("PASS: not finished"); setInterval(() => {}, 1000)', 1, 1],
  ]) {
    const log = path.join(directory, name + '.log');
    const result = spawnSync(process.execPath, ['tools/run_godot_check.cjs', String(seconds), log,
      process.execPath, '-e', code], {timeout: 15000, encoding: 'utf8'});
    assert.equal(result.error, undefined, name);
    assert.equal(result.status, expected, name + ': ' + result.stdout + result.stderr);
    if (name === 'deadline') {
      const output = fs.readFileSync(log, 'utf8');
      assert.match(output, /timeout=true/);
      const pid = Number(output.match(/pid=(\d+)/)[1]);
      assert.throws(() => process.kill(pid, 0), {code: 'ESRCH'}, 'Deadline left its child alive');
    }
  }
  console.log('PASS: runner completion, errors, leaks, exit code and owned-process deadline');
} finally {
  fs.rmSync(directory, {recursive: true, force: true});
}
