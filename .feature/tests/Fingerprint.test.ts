/**
 * Fingerprint.test.ts — Node.js 兼容版单元测试
 *
 * Hypium 在某些 CI 环境（如无 DevEco 模拟器）下无法跑；提供一个 Node 可跑的实现
 * 验证 sha1Hex 算法的正确性（与 ArkTS 版本是同一段算法）。
 */

import { sha1Hex, isFingerprintMatch } from './Fingerprint.pure.ts';

const tests: { name: string; run: () => void }[] = [];

function test(name: string, run: () => void) {
  tests.push({ name, run });
}

test('sha1("abc")', () => {
  const bytes = new Uint8Array([0x61, 0x62, 0x63]);
  if (sha1Hex(bytes) !== 'a9993e364706816aba3e25717850c26c9cd0d89d') {
    throw new Error('expected a9993e36...');
  }
});

test('sha1("")', () => {
  if (sha1Hex(new Uint8Array(0)) !== 'da39a3ee5e6b4b0d3255bfef95601890afd80709') {
    throw new Error('expected da39a3ee...');
  }
});

test('isFingerprintMatch: identical', () => {
  const a = { size: 100, mtime: 1700000000, hashHead: 'h1', hashTail: 't1' };
  const b = { size: 100, mtime: 1700000000, hashHead: 'h1', hashTail: 't1' };
  if (!isFingerprintMatch(a, b)) throw new Error('expected match');
});

test('isFingerprintMatch: diff size', () => {
  const a = { size: 100, mtime: 1700000000, hashHead: 'h1', hashTail: 't1' };
  const b = { size: 200, mtime: 1700000000, hashHead: 'h1', hashTail: 't1' };
  if (isFingerprintMatch(a, b)) throw new Error('expected mismatch');
});

let passed = 0, failed = 0;
for (const t of tests) {
  try {
    t.run();
    console.log(`  ✅ ${t.name}`);
    passed += 1;
  } catch (e) {
    console.error(`  ❌ ${t.name}: ${(e as Error).message}`);
    failed += 1;
  }
}
console.log(`\n  Total: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);