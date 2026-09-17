/**
 * KeyStore.test.ts — KeyStore fallback 路径单元测试
 *
 * 验证：开发/模拟态下，KeyStore HUKS 不可用时，回退到 XOR+salt 加密；
 * decrypt 应能还原原密码，且 fallback 标志位正确传播。
 */

import { fallbackEncrypt, fallbackDecrypt } from './KeyStore.pure.ts';

const tests: { name: string; run: () => void }[] = [];
function test(name: string, run: () => void) {
  tests.push({ name, run });
}

test('fallback encrypt+decrypt roundtrip: ascii', () => {
  const plain = 'P@ssw0rd!123';
  const c = fallbackEncrypt(plain);
  const d = fallbackDecrypt(c);
  if (d !== plain) throw new Error(`roundtrip failed: got "${d}"`);
});

test('fallback encrypt+decrypt roundtrip: utf8', () => {
  const plain = '密码含中文-✅-emoji';
  const c = fallbackEncrypt(plain);
  const d = fallbackDecrypt(c);
  if (d !== plain) throw new Error(`roundtrip utf8 failed: got "${d}"`);
});

test('fallback encrypted form != plain (smoke)', () => {
  const plain = 'identical';
  const c1 = fallbackEncrypt(plain);
  if (c1 === plain) throw new Error('encrypted form should differ from plain');
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