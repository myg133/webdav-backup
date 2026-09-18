/**
 * E2ECrypto.test.ts — AES-256-GCM 文件加密 / 解密单元测试
 *
 * 覆盖（REQ-004 F2/F3）：
 *   - encrypt → decrypt roundtrip 字节一致
 *   - 同样输入两次 → 不同密文（nonce 唯一）
 *   - 篡改 1 个字节 → decrypt 抛 E2E_AUTH_ERROR
 *   - chunk 边界：5MB（2 chunks）+ 4MB（1 chunk）
 *   - 错误主密钥 → decrypt 抛 E2E_AUTH_ERROR
 *   - 文件名加密 + 解密（含 unicode）
 *
 * 用法：node --experimental-strip-types E2ECrypto.test.ts
 */

import {
  encryptFile,
  decryptFile,
  encryptFilename,
  decryptFilename,
  E2E_AUTH_ERROR,
  CHUNK_SIZE,
  FILENAME_EXT,
  MAGIC,
  NONCE_LEN,
  TAG_LEN,
} from './E2ECrypto.pure.ts';

const tests: { name: string; run: () => Promise<void> | void }[] = [];
function test(name: string, run: () => Promise<void> | void) {
  tests.push({ name, run });
}

function makeKey(seed = 0): Uint8Array {
  const k = new Uint8Array(32);
  for (let i = 0; i < 32; i++) k[i] = (i * 7 + 1 + seed) & 0xff;
  return k;
}

function makeData(size: number, seed = 0): Uint8Array {
  const out = new Uint8Array(size);
  for (let i = 0; i < size; i++) out[i] = (i + seed) & 0xff;
  return out;
}

test('encrypt → decrypt roundtrip (100B)', async () => {
  const key = makeKey(1);
  const data = makeData(100, 5);
  const ct = await encryptFile(data.buffer, 'a.bin', 100, key);
  const pt = await decryptFile(ct, key);
  if (pt.name !== 'a.bin') throw new Error(`bad name: ${pt.name}`);
  if (pt.size !== 100) throw new Error(`bad size: ${pt.size}`);
  const got = new Uint8Array(pt.data);
  if (got.length !== 100) throw new Error(`bad length: ${got.length}`);
  for (let i = 0; i < 100; i++) {
    if (got[i] !== (i + 5) & 0xff) throw new Error(`byte ${i} mismatch`);
  }
});

test('encrypt → decrypt roundtrip (5MB = 2 chunks)', async () => {
  const key = makeKey(2);
  const data = makeData(5 * 1024 * 1024, 0);
  const ct = await encryptFile(data.buffer, 'big.bin', data.length, key);
  // 5MB plaintext → header (~26 bytes) + 2 chunks (12+4MB+16) + 2 chunks (12+1MB+16) ≈ 5MB + 108 bytes
  const expectedMin = 5 * 1024 * 1024;
  if (ct.byteLength < expectedMin) throw new Error(`ct too small: ${ct.byteLength}`);
  const pt = await decryptFile(ct, key);
  if (pt.size !== data.length) throw new Error(`size mismatch: ${pt.size}`);
  const got = new Uint8Array(pt.data);
  if (got.length !== data.length) throw new Error(`length mismatch: ${got.length}`);
  // spot check
  if (got[0] !== 0) throw new Error('first byte mismatch');
  if ((got[data.length - 1] & 0xff) !== ((data.length - 1) & 0xff)) throw new Error('last byte mismatch');
  if ((got[CHUNK_SIZE] & 0xff) !== (CHUNK_SIZE & 0xff)) throw new Error('chunk-boundary byte mismatch');
});

test('encrypt → decrypt roundtrip (4MB exactly = 1 chunk)', async () => {
  const key = makeKey(3);
  const size = CHUNK_SIZE;
  const data = makeData(size, 11);
  const ct = await encryptFile(data.buffer, '4mb.bin', size, key);
  const pt = await decryptFile(ct, key);
  if (pt.size !== size) throw new Error(`size mismatch: ${pt.size}`);
  const got = new Uint8Array(pt.data);
  if (got[0] !== 11) throw new Error('first byte mismatch');
  if ((got[size - 1] & 0xff) !== ((size - 1 + 11) & 0xff)) throw new Error('last byte mismatch');
});

test('nonce uniqueness: same plaintext → different ciphertext', async () => {
  const key = makeKey(4);
  const data = makeData(1000, 7);
  const ct1 = await encryptFile(data.buffer, 'same.bin', 1000, key);
  const ct2 = await encryptFile(data.buffer, 'same.bin', 1000, key);
  if (Buffer.from(ct1).equals(Buffer.from(ct2))) {
    throw new Error('two encryptions produced identical ciphertext — nonce reuse!');
  }
});

test('nonce uniqueness: file header has random nonce', async () => {
  const key = makeKey(5);
  const data = makeData(100, 0);
  const ct1 = new Uint8Array(await encryptFile(data.buffer, 'x.bin', 100, key));
  const ct2 = new Uint8Array(await encryptFile(data.buffer, 'x.bin', 100, key));
  // Compare header nonce (4..4+NONCE_LEN)
  for (let i = 4; i < 4 + NONCE_LEN; i++) {
    if (ct1[i] === ct2[i]) {
      throw new Error(`header nonce byte ${i - 4} matched across two encrypts (nonce reused!)`);
    }
  }
});

test('tampering 1 byte → decrypt throws E2E_AUTH_ERROR', async () => {
  const key = makeKey(6);
  const data = makeData(200, 0);
  const ct = new Uint8Array(await encryptFile(data.buffer, 't.bin', 200, key));
  // Flip a byte in first chunk (byte 50, well past header ~26 bytes)
  ct[50] ^= 0x01;
  let caught = false;
  let caughtName = '';
  try {
    await decryptFile(ct.buffer, key);
  } catch (e) {
    caught = true;
    caughtName = (e as Error).name;
  }
  if (!caught) throw new Error('tampered ciphertext was accepted!');
  if (caughtName !== 'E2E_AUTH_ERROR') throw new Error(`expected E2E_AUTH_ERROR, got ${caughtName}`);
});

test('tampering tag byte → decrypt throws E2E_AUTH_ERROR', async () => {
  const key = makeKey(7);
  const data = makeData(100, 0);
  const ct = new Uint8Array(await encryptFile(data.buffer, 't.bin', 100, key));
  // Flip last byte (in chunk tag)
  ct[ct.length - 1] ^= 0x01;
  let caught = false;
  let caughtName = '';
  try {
    await decryptFile(ct.buffer, key);
  } catch (e) {
    caught = true;
    caughtName = (e as Error).name;
  }
  if (!caught) throw new Error('tampered tag was accepted!');
  if (caughtName !== 'E2E_AUTH_ERROR') throw new Error(`expected E2E_AUTH_ERROR, got ${caughtName}`);
});

test('wrong master key → decrypt throws E2E_AUTH_ERROR', async () => {
  const key = makeKey(8);
  const wrongKey = makeKey(99);
  const data = makeData(100, 0);
  const ct = await encryptFile(data.buffer, 't.bin', 100, key);
  let caught = false;
  try {
    await decryptFile(ct, wrongKey);
  } catch (e) {
    caught = (e as Error).name === 'E2E_AUTH_ERROR';
  }
  if (!caught) throw new Error('wrong master key was accepted!');
});

test('chunk boundary: 4MB+1 byte = 2 chunks', async () => {
  const key = makeKey(10);
  const size = CHUNK_SIZE + 1;
  const data = makeData(size, 3);
  const ct = await encryptFile(data.buffer, 'edge.bin', size, key);
  const pt = await decryptFile(ct, key);
  if (pt.size !== size) throw new Error(`size mismatch: ${pt.size}`);
  const got = new Uint8Array(pt.data);
  if ((got[size - 1] & 0xff) !== ((size - 1 + 3) & 0xff)) throw new Error('last byte mismatch');
});

test('empty file (0 bytes): "主流"用例 = 1 个空 chunk', async () => {
  const key = makeKey(11);
  const data = new Uint8Array(0);
  const ct = await encryptFile(data.buffer, 'empty.bin', 0, key);
  const pt = await decryptFile(ct, key);
  if (pt.size !== 0) throw new Error(`expected 0, got ${pt.size}`);
  if (new Uint8Array(pt.data).length !== 0) throw new Error('expected empty data');
  if (pt.name !== 'empty.bin') throw new Error('name mismatch');
});

test('filename encryption: ascii roundtrip', async () => {
  const key = makeKey(20);
  const orig = 'hello.txt';
  const enc = await encryptFilename(orig, key);
  if (!enc.endsWith(FILENAME_EXT)) throw new Error(`expected .wde suffix, got "${enc}"`);
  const dec = await decryptFilename(enc, key);
  if (dec !== orig) throw new Error(`roundtrip failed: "${dec}"`);
});

test('filename encryption: unicode roundtrip', async () => {
  const key = makeKey(21);
  const orig = '照片-2026-✅-file.jpg';
  const enc = await encryptFilename(orig, key);
  const dec = await decryptFilename(enc, key);
  if (dec !== orig) throw new Error(`unicode roundtrip failed: "${dec}"`);
});

test('filename encryption: wrong key fails', async () => {
  const key = makeKey(22);
  const enc = await encryptFilename('test.bin', key);
  const wrongKey = makeKey(99);
  let caught = false;
  try {
    await decryptFilename(enc, wrongKey);
  } catch (e) {
    caught = (e as Error).name === 'E2E_AUTH_ERROR';
  }
  if (!caught) throw new Error('wrong key was accepted for filename decrypt');
});

test('ciphertext starts with magic "WDVE"', async () => {
  const key = makeKey(30);
  const ct = new Uint8Array(await encryptFile(new Uint8Array(10).buffer, 'm.bin', 10, key));
  for (let i = 0; i < 4; i++) {
    if (ct[i] !== MAGIC[i]) throw new Error(`magic byte ${i} mismatch: got ${ct[i]}, want ${MAGIC[i]}`);
  }
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