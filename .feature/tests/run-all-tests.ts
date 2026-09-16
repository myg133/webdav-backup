#!/usr/bin/env node
// run-all-tests.ts - Run all unit tests and integration tests
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';

const tests = [
  { name: 'Fingerprint', file: 'Fingerprint.test.ts' },
  { name: 'WebDAVClient (parseMultistatus)', file: 'WebDAVClient.test.ts' },
  { name: 'KeyStore (fallback encrypt)', file: 'KeyStore.test.ts' },
  { name: 'UploadQueue (retry/backoff)', file: 'UploadQueue.test.ts' },
];

let passed = 0, failed = 0;

console.log('=== Unit tests ===\n');
for (const t of tests) {
  if (!existsSync(t.file)) {
    console.log(`  [SKIP] ${t.name}: ${t.file} not found`);
    continue;
  }
  const r = spawnSync(process.execPath, ['--experimental-strip-types', t.file], { stdio: 'inherit' });
  if (r.status === 0) {
    passed += 1;
  } else {
    failed += 1;
  }
  console.log('');
}

console.log('=== Integration tests ===\n');
console.log('Run with: cd ..\\\\\scripts && powershell -ExecutionPolicy Bypass -File integration-test.ps1');
console.log('See: ../scripts/integration-result.json (after run)');

console.log(`\n=== Total: ${passed} passed, ${failed} failed ===`);
process.exit(failed > 0 ? 1 : 0);