#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync, execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const TEST_TIMEOUT_MS = 45000;
const IMPORT_TIMEOUT_MS = 120000;
const LARGE_FILE_BYTES = 5 * 1024 * 1024;

function parseArgs(argv) {
  const opts = { godot: null, audit: false, skipImport: false, timeout: TEST_TIMEOUT_MS };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') {
      console.log('Usage: node tools/dev/validate.mjs [--godot <path>] [--audit] [--skip-import] [--timeout <ms>]');
      process.exit(0);
    }
    if (arg === '--audit') {
      opts.audit = true;
      continue;
    }
    if (arg === '--skip-import') {
      opts.skipImport = true;
      continue;
    }
    let key = arg;
    let val = null;
    if (arg.startsWith('--godot=')) [key, val] = ['--godot', arg.slice(8)];
    else if (arg === '--godot') val = argv[++i];
    else if (arg.startsWith('--timeout=')) [key, val] = ['--timeout', arg.slice(10)];
    else if (arg === '--timeout') val = argv[++i];

    if (key === '--godot') {
      if (!val) { console.error('Error: --godot requires path'); process.exit(1); }
      opts.godot = val;
    } else if (key === '--timeout') {
      const ms = Number(val);
      if (!Number.isInteger(ms) || ms <= 0) {
        console.error(`Error: --timeout must be a positive integer, got "${val}"`);
        process.exit(1);
      }
      opts.timeout = ms;
    } else {
      console.error(`Error: unknown argument "${arg}"`);
      process.exit(1);
    }
  }
  return opts;
}

function runGodot(bin, args, timeout, logFile) {
  const start = Date.now();
  const res = spawnSync(bin, args, { cwd: REPO_ROOT, timeout, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  const duration = ((Date.now() - start) / 1000).toFixed(2);
  const combined = (res.stdout || '') + (res.stderr ? (res.stdout ? '\n' : '') + res.stderr : '');
  if (logFile) fs.writeFileSync(logFile, combined, 'utf8');

  const timedOut = Boolean(res.error?.code === 'ETIMEDOUT' || res.signal === 'SIGTERM');
  const errorLines = combined.split(/\r?\n/).filter((l) => /\b(SCRIPT ERROR:|ERROR:|FAIL:)/.test(l)).map((l) => l.trim());
  const failed = Boolean(res.error && !timedOut) || timedOut || res.status !== 0 || errorLines.length > 0;

  return { status: res.status, spawnError: res.error && !timedOut ? res.error.message : null, timedOut, errorLines, failed, duration, logFile };
}

function runValidation(opts) {
  const godot = opts.godot || process.env.GODOT_BIN || 'godot';
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'aero-demons-val-'));
  console.log(`[Aero Demons] Validate | Root: ${REPO_ROOT} | Godot: ${godot} | Logs: ${tmp}\n`);

  // Headless editor import
  if (!opts.skipImport) {
    const importLog = path.join(tmp, '00_import.log');
    console.log(`[IMPORT] --editor --import --quit (${IMPORT_TIMEOUT_MS / 1000}s max)...`);
    const imp = runGodot(godot, ['--headless', '--editor', '--import', '--quit', '--path', REPO_ROOT], IMPORT_TIMEOUT_MS, importLog);
    console.log(`  Log: ${importLog}`);
    if (imp.failed) {
      console.error(`  [FAIL] Import failed (${imp.duration}s) status=${imp.status} timedOut=${imp.timedOut} error=${imp.spawnError || ''}`);
      if (imp.errorLines.length) console.error(`  ${imp.errorLines.slice(0, 5).join('\n  ')}`);
      process.exit(1);
    }
    console.log(`  [PASS] Import OK (${imp.duration}s)\n`);
  } else {
    console.log('[IMPORT] skipped (--skip-import)\n');
  }

  // Sequential tests
  const testsDir = path.join(REPO_ROOT, 'scripts/tests');
  const tests = fs.readdirSync(testsDir).filter((f) => f.endsWith('_check.gd')).sort();
  let failed = 0;

  for (const t of tests) {
    const log = path.join(tmp, `${t.replace(/\.gd$/, '')}.log`);
    process.stdout.write(`[TEST] ${t} ... `);
    const res = runGodot(godot, ['--headless', '--path', REPO_ROOT, '--script', `scripts/tests/${t}`], opts.timeout, log);
    if (res.failed) {
      failed++;
      console.log(`FAIL (${res.duration}s) status=${res.status} timedOut=${res.timedOut}`);
      if (res.spawnError) console.log(`  Spawn error: ${res.spawnError}`);
      if (res.errorLines.length) console.log(`  ${res.errorLines.slice(0, 5).join('\n  ')}`);
    } else {
      console.log(`PASS (${res.duration}s)`);
    }
    console.log(`  Log: ${log}`);
  }

  console.log(`\nResult: ${tests.length - failed}/${tests.length} passed (${failed} failed).`);
  process.exit(failed === 0 ? 0 : 1);
}

function runAudit() {
  console.log(`[Aero Demons] Audit (Read-Only) | Root: ${REPO_ROOT}\n`);
  let files = [];
  try {
    const raw = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard', '-z'], {
      cwd: REPO_ROOT, encoding: 'utf8', timeout: 15000, maxBuffer: 16 * 1024 * 1024,
    });
    files = raw.split('\0').filter(Boolean);
  } catch (err) {
    console.error(`Error listing git files: ${err.message}`);
    process.exit(1);
  }

  // Large files
  console.log(`--- Large Files (>= ${(LARGE_FILE_BYTES / 1048576).toFixed(0)} MB) ---`);
  const large = [];
  for (const f of files) {
    try {
      const size = fs.statSync(path.join(REPO_ROOT, f)).size;
      if (size >= LARGE_FILE_BYTES) large.push({ path: f, size });
    } catch {}
  }
  large.sort((a, b) => b.size - a.size);
  for (const item of large) {
    console.log(`  ${(item.size / 1048576).toFixed(2).padStart(7)} MB  ${item.path}`);
  }

  // Literal quoted res:// scan
  console.log(`\n--- Quoted res:// References Scan ---`);
  const scannable = files.filter((f) => f === 'project.godot' || f.endsWith('.gd') || f.endsWith('.tscn') || f.endsWith('.tres'));
  const missing = { active: [], dynamic: [], comment: [], vendor: [], demo: [] };

  for (const sf of scannable) {
    const abs = path.join(REPO_ROOT, sf);
    let content = '';
    try { content = fs.readFileSync(abs, 'utf8'); } catch { continue; }
    const lines = content.split(/\r?\n/);
    const isVendor = sf.startsWith('addons/');
    const isDemo = sf.startsWith('demo/');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trim();
      const isComment = trimmed.startsWith('#') || trimmed.startsWith(';');
      const isDynamic = trimmed.includes('%') || trimmed.includes('{') || trimmed.includes('+');

      // Complete quoted strings: "res://..." or 'res://...' (supports spaces in path)
      const matches = line.matchAll(/(['"])(res:\/\/[^\r\n'"]+)\1/g);
      for (const m of matches) {
        const fullRef = m[2];
        const diskPath = path.join(REPO_ROOT, fullRef.slice(6));
        if (!fs.existsSync(diskPath)) {
          const entry = `${sf}:${i + 1} -> ${fullRef}`;
          if (isComment) missing.comment.push(entry);
          else if (isVendor) missing.vendor.push(entry);
          else if (isDemo) missing.demo.push(entry);
          else if (isDynamic) missing.dynamic.push(entry);
          else missing.active.push(entry);
        }
      }
    }
  }

  console.log(`Scanned files: ${scannable.length}`);
  console.log(`Missing active project references: ${missing.active.length}`);
  console.log(`Warnings - dynamic path references: ${missing.dynamic.length}`);
  console.log(`Warnings - comment references:      ${missing.comment.length}`);
  console.log(`Warnings - vendor addon references: ${missing.vendor.length}`);
  console.log(`Warnings - demo references:          ${missing.demo.length}`);

  if (missing.active.length) {
    console.log(`\nActive Missing References:`);
    for (const e of missing.active.slice(0, 15)) console.log(`  ${e}`);
  }
  if (missing.dynamic.length) {
    console.log(`\nDynamic Path Reference Warnings:`);
    for (const e of missing.dynamic.slice(0, 10)) console.log(`  ${e}`);
  }
}

const opts = parseArgs(process.argv.slice(2));
if (opts.audit) runAudit();
else runValidation(opts);
