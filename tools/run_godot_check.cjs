// Deadline and exact process-tree cleanup. No global Godot process termination.
// node tools/run_godot_check.cjs seconds log executable [Godot arguments...]
const {spawn, spawnSync} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const [seconds, log, executable, ...args] = process.argv.slice(2);
if (!Number.isFinite(Number(seconds)) || !(Number(seconds) > 0) || !log || !executable) throw Error('Expected seconds, log, executable, arguments');
fs.mkdirSync(path.dirname(log), {recursive: true});
const output = fs.openSync(log, 'w');
const child = spawn(executable, args, {stdio: ['ignore', output, output], detached: process.platform !== 'win32'});
let timedOut = false;
function killOwnedTree() {
  if (child.pid && child.exitCode === null) {
    if (process.platform === 'win32') {
      const cleanup = spawnSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], {timeout: 5000});
      if (cleanup.error) console.error('Process-tree cleanup failed:', cleanup.error);
    } else process.kill(-child.pid, 'SIGKILL');
  }
}
const timer = setTimeout(() => { timedOut = true; killOwnedTree(); }, Number(seconds) * 1000);
child.on('error', error => { console.error(error); killOwnedTree(); process.exitCode = 1; });
child.on('close', code => {
  clearTimeout(timer);
  fs.closeSync(output);
  const text = fs.readFileSync(log, 'utf8');
  const passed = code === 0 && !timedOut && /(?:PERFORMANCE BENCHMARK PASS:|^PASS:)/m.test(text)
    && !/(?:SCRIPT ERROR:|ERROR:|Assertion failed|leaked at exit)/i.test(text);
  const status = `RUNNER exit=${code} timeout=${timedOut} pid=${child.pid} passed=${passed}`;
  fs.appendFileSync(log, '\n' + status + '\n');
  console.log(text + '\n' + status);
  process.exitCode = passed ? 0 : 1;
});
process.on('SIGINT', () => { timedOut = true; killOwnedTree(); });
process.on('SIGTERM', () => { timedOut = true; killOwnedTree(); });
