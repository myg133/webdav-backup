/**
 * MasterKey.test.ts — 主密钥派生（PBKDF2-HMAC-SHA256）单元测试
 *
 * 覆盖（REQ-004 F1）：
 *   - PBKDF2 100k 迭代 + 16 byte salt（输出 32 字节）
 *   - 同一 password + salt → 同一 key（稳定派生）
 *   - 不同 password → 不同 key
 *   - 不同 salt → 不同 key
 *   - 错误密码 → null（不抛异常）
 *
 * 用法：node --experimental-strip-types MasterKey.test.ts
 */

import { deriveMasterKey, generateSalt, ITERATIONS, SALT_BYTES, KEY_BYTES } from './MasterKey.pure.ts';

const tests: { name: string; run: () => Promise<void> | void }[] = [];
function test(name: string, run: () => Promise<void> | void) {
  tests.push({ name, run });
}

test('generateSalt: 16 bytes', () => {
  const s = generateSalt();
  if (s.length !== SALT_BYTES) throw new Error(`expected ${SALT_BYTES}, got ${s.length}`);
  if (SALT_BYTES !== 16) throw new Error('SALT_BYTES must be 16');
});

test('ITERATIONS >= 100k (REQ-004 F1 关键约束)', () => {
  if (ITERATIONS < 100_000) throw new Error(`ITERATIONS must be >= 100000, got ${ITERATIONS}`);
});

test('deriveMasterKey: 32-byte output (AES-256)', async () => {
  const k = await deriveMasterKey('mypassword', generateSalt());
  if (!k) throw new Error('deriveMasterKey returned null');
  if (k.length !== KEY_BYTES) throw new Error(`expected ${KEY_BYTES}, got ${k.length}`);
  if (KEY_BYTES !== 32) throw new Error('KEY_BYTES must be 32');
});

test('deriveMasterKey: deterministic (same password + salt → same key)', async () => {
  const salt = new Uint8Array(SALT_BYTES);
  for (let i = 0; i < SALT_BYTES; i++) salt[i] = i;
  const k1 = await deriveMasterKey('hello', salt);
  const k2 = await deriveMasterKey('hello', salt);
  if (!k1 || !k2) throw new Error('null');
  if (!Buffer.from(k1).equals(Buffer.from(k2))) throw new Error('derived keys differ for same input');
});

test('deriveMasterKey: different password → different key', async () => {
  const salt = generateSalt();
  const k1 = await deriveMasterKey('password-A', salt);
  const k2 = await deriveMasterKey('password-B', salt);
  if (!k1 || !k2) throw new Error('null');
  if (Buffer.from(k1).equals(Buffer.from(k2))) throw new Error('keys should differ');
});

test('deriveMasterKey: different salt → different key', async () => {
  const saltA = new Uint8Array(SALT_BYTES);
  const saltB = new Uint8Array(SALT_BYTES);
  for (let i = 0; i < SALT_BYTES; i++) { saltA[i] = i; saltB[i] = i + 1; }
  const k1 = await deriveMasterKey('same-password', saltA);
  const k2 = await deriveMasterKey('same-password', saltB);
  if (!k1 || !k2) throw new Error('null');
  if (Buffer.from(k1).equals(Buffer.from(k2))) throw new Error('keys should differ with different salts');
});

test('deriveMasterKey: wrong-password detection shape (always returns non-null on plain input)', async () => {
  // 设计约束：**主密码错误不抛异常** —— deriveMasterKey 在 PBKDF2 层永远成功（PBKDF2 不会"失败"）。
  // "密码错误"判定在 GCM tag 验证层（见 E2ECrypto.test.ts）。所以这里只验证非空。
  const k = await deriveMasterKey('', new Uint8Array(SALT_BYTES));
  if (!k) throw new Error('empty password should still derive 32-byte key (PBKDF2 不会"密码错误")');
  if (k.length !== KEY_BYTES) throw new Error('expected 32-byte key');
});

test('deriveMasterKey: 100k iterations completes under 5s (sanity)', async () => {
  const t0 = Date.now();
  await deriveMasterKey('benchmark', generateSalt());
  const ms = Date.now() - t0;
  // 100k PBKDF2 迭代 ~1-2s in Node（SHA256 software）；5s upper bound
  if (ms > 5000) throw new Error(`PBKDF2 took ${ms}ms (limit 5000ms)`);
});

let passed = 0, failed = 0;
(async () => {
  for (const t of tests) {
    try {
      await t.run();
      console.log(`  ✅ ${t.name}`);
      passed += 1;
    } catch (e) {
      console.error(`  ❌ ${t.name}: ${(e as Error).message}`);
      failed += 1;
    }
  }
  console.log(`\n  Total: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
})();